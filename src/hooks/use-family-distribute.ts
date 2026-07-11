"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { erc20Abi, type Address, type Hex } from "viem";
import { cycleModuleAbi, distributionManagerAbi, tokenAbi } from "@/lib/abis";
import { publicClientFor } from "@/lib/instance";
import { parseTxError } from "@/hooks/use-tx";
import { useWalletActions } from "@/components/wallet/wallet-actions";
import type { FamilyState } from "@/hooks/use-family";

/** Per-chain action state for one family chain's distribution. */
export type FamilyDistributeState =
  "idle" | "distributing" | "confirming" | "done" | "failed";

export interface FamilyDistributeRow {
  chainId: number;
  distributionManager: Address;
  cycleNumber?: bigint;
  isComplete?: boolean;
  /** The contract's own gate — the only thing that enables the button. */
  isReady?: boolean;
  /** yieldAccrued normalized to 18 decimals (the L2 mirrors are 6-dp USDC). */
  accrued18?: bigint;
  /** Reads failed on this chain — readiness unknown. */
  unreachable?: boolean;
  state: FamilyDistributeState;
  txHash?: Hex;
  error?: string;
}

const POLL_MS = 12_000; // match the single-chain isDistributionReady cadence
const scaleTo18 = (value: bigint, decimals: number) =>
  decimals >= 18 ? value : value * 10n ** BigInt(18 - decimals);

interface Member {
  chainId: number;
  distributionManager: Address;
  cycleModule: Address;
  token: Address;
}

/** Serialize the family membership so effects key on content, not identity. */
function memberKeyOf(family: FamilyState): string {
  if (!family.isFamily) return "";
  return family.perChain
    .filter((c) => c.status === "found" && c.instance)
    .map((c) =>
      [
        c.chainId,
        c.instance!.distributionManager.toLowerCase(),
        c.instance!.cycleModule.toLowerCase(),
        c.instance!.token.toLowerCase(),
      ].join(":"),
    )
    .sort()
    .join(",");
}

function parseMembers(memberKey: string): Member[] {
  return memberKey
    .split(",")
    .map((m) => {
      const [chainId, distributionManager, cycleModule, token] = m.split(":");
      return {
        chainId: Number(chainId),
        distributionManager: distributionManager as Address,
        cycleModule: cycleModule as Address,
        token: token as Address,
      };
    })
    .sort((a, b) => a.chainId - b.chainId);
}

/** The refreshable read fields — patched by polls without touching tx state. */
type ChainReads = Pick<
  FamilyDistributeRow,
  "cycleNumber" | "isComplete" | "isReady" | "accrued18" | "unreachable"
>;

async function readChain(
  m: Member,
  decimalsCache: Map<number, number>,
): Promise<ChainReads> {
  const client = publicClientFor(m.chainId);
  let decimals = decimalsCache.get(m.chainId);
  if (decimals === undefined) {
    decimals = await client.readContract({
      address: m.token,
      abi: erc20Abi,
      functionName: "decimals",
    });
    decimalsCache.set(m.chainId, decimals);
  }
  const [cycleNumber, isComplete, isReady, accrued] = await Promise.all([
    client.readContract({
      address: m.cycleModule,
      abi: cycleModuleAbi,
      functionName: "getCurrentCycle",
    }),
    client.readContract({
      address: m.cycleModule,
      abi: cycleModuleAbi,
      functionName: "isCycleComplete",
    }),
    client.readContract({
      address: m.distributionManager,
      abi: distributionManagerAbi,
      functionName: "isDistributionReady",
    }),
    client.readContract({
      address: m.token,
      abi: tokenAbi,
      functionName: "yieldAccrued",
    }) as Promise<bigint>,
  ]);
  return {
    cycleNumber,
    isComplete,
    isReady,
    accrued18: scaleTo18(accrued, decimals),
    unreachable: false,
  };
}

/**
 * Family-wide distribution checklist: one row per sibling chain with its cycle
 * number, readiness, and accrued pot (18-dp normalized), each independently
 * distributable. `claimAndDistribute` is a public keeper call, so any visitor
 * can run it on every chain from one page — writes go through the sponsored
 * wallet layer (gasless on embedded wallets, chain-switching self-paid
 * otherwise) and each receipt is awaited on that chain's OWN client, never the
 * wallet-chain wait. Fail-soft per chain: a dead RPC marks the row unreachable
 * without breaking the rest.
 */
export function useFamilyDistribute(family: FamilyState) {
  const { sendSponsored } = useWalletActions();

  const [rows, setRowsState] = useState<FamilyDistributeRow[]>([]);
  const rowsRef = useRef<FamilyDistributeRow[]>([]);
  const membersRef = useRef<Member[]>([]);
  // decimals never change per token — read once per sibling, then reuse.
  const decimalsCache = useRef(new Map<number, number>());
  // "Distribute all" walk in progress — ref guards re-entry (the walk has
  // idle gaps between chains while re-checking readiness), state drives the UI.
  const allRunningRef = useRef(false);
  const [allRunning, setAllRunning] = useState(false);

  const setRows = useCallback(
    (updater: (prev: FamilyDistributeRow[]) => FamilyDistributeRow[]) => {
      rowsRef.current = updater(rowsRef.current);
      setRowsState(rowsRef.current);
    },
    [],
  );

  const patchRow = useCallback(
    (chainId: number, patch: Partial<FamilyDistributeRow>) => {
      setRows((prev) =>
        prev.map((r) => (r.chainId === chainId ? { ...r, ...patch } : r)),
      );
    },
    [setRows],
  );

  const memberKey = memberKeyOf(family);

  useEffect(() => {
    if (!memberKey) {
      membersRef.current = [];
      setRows(() => []);
      return;
    }
    const members = parseMembers(memberKey);
    membersRef.current = members;
    // Seed idle rows, keeping any in-flight/terminal state for surviving chains.
    setRows((prev) =>
      members.map(
        (m) =>
          prev.find(
            (r) =>
              r.chainId === m.chainId &&
              r.distributionManager === m.distributionManager,
          ) ?? {
            chainId: m.chainId,
            distributionManager: m.distributionManager,
            state: "idle" as FamilyDistributeState,
          },
      ),
    );

    let cancelled = false;
    const load = async () => {
      await Promise.all(
        members.map(async (m) => {
          try {
            const data = await readChain(m, decimalsCache.current);
            if (!cancelled) patchRow(m.chainId, data);
          } catch {
            if (!cancelled) patchRow(m.chainId, { unreachable: true });
          }
        }),
      );
    };
    void load();
    const id = setInterval(() => void load(), POLL_MS);
    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, [memberKey, patchRow, setRows]);

  /** Run claimAndDistribute on ONE chain — independent, per-row retryable. */
  const distributeOn = useCallback(
    async (chainId: number) => {
      const m = membersRef.current.find((x) => x.chainId === chainId);
      const row = rowsRef.current.find((r) => r.chainId === chainId);
      if (!m || !row) return;
      if (row.state === "distributing" || row.state === "confirming") return;
      patchRow(chainId, {
        state: "distributing",
        error: undefined,
        txHash: undefined,
      });
      try {
        const hash = await sendSponsored({
          chainId,
          address: m.distributionManager,
          abi: distributionManagerAbi,
          functionName: "claimAndDistribute",
          args: [],
        });
        patchRow(chainId, { state: "confirming", txHash: hash });
        // Wait on THIS chain's client — the wallet may be pointed elsewhere.
        // viem's raw wait RETURNS reverted receipts (wagmi's throws); distribute
        // is a public keeper race, so a lost race must read as failed, not done.
        const receipt = await publicClientFor(
          chainId,
        ).waitForTransactionReceipt({ hash });
        if (receipt.status === "reverted") {
          patchRow(chainId, {
            state: "failed",
            error: "Transaction reverted — likely already distributed",
          });
          return;
        }
        patchRow(chainId, { state: "done" });
        // Re-read so the advanced cycle / drained pot shows immediately.
        try {
          patchRow(chainId, await readChain(m, decimalsCache.current));
        } catch {
          /* transient — the next poll refreshes it */
        }
      } catch (e) {
        patchRow(chainId, { state: "failed", error: parseTxError(e) });
      }
    },
    [patchRow, sendSponsored],
  );

  /**
   * Distribute on every READY chain, sequentially — a self-paid wallet must
   * switch networks between writes, so parallel submits would race the switch
   * (embedded wallets just sign each silently). Each chain's readiness is
   * RE-CHECKED right before its tx: the row's copy can be up to 12s stale and
   * distribute is a public keeper race, so a chain someone else just
   * distributed is skipped instead of submitting a doomed tx. Fail-soft per
   * chain: not-ready/unreachable rows are skipped without breaking the walk.
   */
  const distributeAll = useCallback(async () => {
    if (allRunningRef.current) return; // one walk at a time
    allRunningRef.current = true;
    setAllRunning(true);
    try {
      for (const m of membersRef.current) {
        const row = rowsRef.current.find((r) => r.chainId === m.chainId);
        if (!row) continue;
        if (row.unreachable) continue; // can't confirm anything there
        if (!row.isReady) continue; // only chains shown ready
        if (row.state === "distributing" || row.state === "confirming")
          continue;
        let fresh: ChainReads;
        try {
          fresh = await readChain(m, decimalsCache.current);
        } catch {
          patchRow(m.chainId, { unreachable: true });
          continue; // dead RPC — skip this chain, keep walking
        }
        patchRow(m.chainId, fresh);
        if (!fresh.isReady) continue; // raced — already distributed elsewhere
        await distributeOn(m.chainId);
      }
    } finally {
      allRunningRef.current = false;
      setAllRunning(false);
    }
  }, [distributeOn, patchRow]);

  return {
    rows,
    distributeOn,
    distributeAll,
    anyBusy:
      allRunning ||
      rows.some((r) => r.state === "distributing" || r.state === "confirming"),
  };
}
