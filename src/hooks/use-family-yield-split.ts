"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import {
  ContractFunctionExecutionError,
  zeroAddress,
  type Address,
  type Hex,
} from "viem";
import { useAccount } from "wagmi";
import { tokenAbi } from "@/lib/abis";
import { publicClientFor } from "@/lib/instance";
import { parseTxError } from "@/hooks/use-tx";
import { useWalletActions } from "@/components/wallet/wallet-actions";
import type { FamilyState } from "@/hooks/use-family";

/** Per-chain action state for one family chain's setYieldSplit. */
export type FamilySplitState =
  "idle" | "setting" | "confirming" | "done" | "failed";

export interface FamilySplitRow {
  chainId: number;
  token: Address;
  /** Current on-chain keepBps for the connected wallet (undefined until read). */
  keepBps?: number;
  /**
   * false ⇒ the token predates yield splits (`yieldSplitOf` reverts) — the
   * same feature-detection the single-chain useYieldSplit does. Such chains
   * are skipped, never errored.
   */
  supported?: boolean;
  /** Reads failed on this chain (RPC down) — state unknown, not "unsupported". */
  unreachable?: boolean;
  state: FamilySplitState;
  txHash?: Hex;
  error?: string;
}

const POLL_MS = 12_000; // match the single-chain token read cadence

interface Member {
  chainId: number;
  token: Address;
}

/** Serialize the family membership so effects key on content, not identity. */
function memberKeyOf(family: FamilyState): string {
  if (!family.isFamily) return "";
  return family.perChain
    .filter((c) => c.status === "found" && c.instance)
    .map((c) => `${c.chainId}:${c.instance!.token.toLowerCase()}`)
    .sort()
    .join(",");
}

function parseMembers(memberKey: string): Member[] {
  return memberKey
    .split(",")
    .map((m) => {
      const [chainId, token] = m.split(":");
      return { chainId: Number(chainId), token: token as Address };
    })
    .sort((a, b) => a.chainId - b.chainId);
}

/** The refreshable read fields — patched by polls without touching tx state. */
type ChainReads = Pick<FamilySplitRow, "keepBps" | "supported" | "unreachable">;

async function readChain(
  m: Member,
  owner: Address | undefined,
): Promise<ChainReads> {
  const client = publicClientFor(m.chainId);
  try {
    // Probe with the zero address before a wallet connects — the revert-based
    // feature detection works either way, but a stranger's split is not "your
    // current split", so keepBps is only surfaced for a connected wallet.
    const keepBps = await client.readContract({
      address: m.token,
      abi: tokenAbi,
      functionName: "yieldSplitOf",
      args: [owner ?? zeroAddress],
    });
    return {
      keepBps: owner ? Number(keepBps) : undefined,
      supported: true,
      unreachable: false,
    };
  } catch (e) {
    // A contract revert means the token predates splits; anything else
    // (RPC/network failure) means we simply couldn't reach the chain.
    if (e instanceof ContractFunctionExecutionError) {
      return { keepBps: undefined, supported: false, unreachable: false };
    }
    throw e;
  }
}

/**
 * Family-wide yield split: the split is per-chain token state, so "one action"
 * for the user means a per-chain `setYieldSplit(keepBps)` fan-out — one row per
 * sibling chain with its current split, each independently retryable. Writes go
 * through the sponsored wallet layer (gasless + silent on embedded wallets, one
 * confirmation per chain self-paid otherwise); receipts are awaited on the
 * target chain's OWN client and status-checked (viem's raw wait RETURNS
 * reverted receipts). Chains whose token predates splits are reported
 * unsupported and skipped; a dead RPC marks the row unreachable without
 * breaking the rest.
 */
export function useFamilyYieldSplit(family: FamilyState) {
  const { address } = useAccount();
  const { sendSponsored } = useWalletActions();

  const [rows, setRowsState] = useState<FamilySplitRow[]>([]);
  const rowsRef = useRef<FamilySplitRow[]>([]);
  const membersRef = useRef<Member[]>([]);

  const setRows = useCallback(
    (updater: (prev: FamilySplitRow[]) => FamilySplitRow[]) => {
      rowsRef.current = updater(rowsRef.current);
      setRowsState(rowsRef.current);
    },
    [],
  );

  const patchRow = useCallback(
    (chainId: number, patch: Partial<FamilySplitRow>) => {
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
          prev.find((r) => r.chainId === m.chainId && r.token === m.token) ?? {
            chainId: m.chainId,
            token: m.token,
            state: "idle" as FamilySplitState,
          },
      ),
    );

    let cancelled = false;
    const load = async () => {
      await Promise.all(
        members.map(async (m) => {
          try {
            const data = await readChain(m, address);
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
  }, [memberKey, address, patchRow, setRows]);

  /** Set the split on ONE chain — independent, per-row retryable. */
  const setSplitOn = useCallback(
    async (chainId: number, keepBps: number) => {
      const m = membersRef.current.find((x) => x.chainId === chainId);
      const row = rowsRef.current.find((r) => r.chainId === chainId);
      if (!m || !row || !address) return;
      if (row.supported === false) return; // predates splits — would revert
      if (row.state === "setting" || row.state === "confirming") return;
      patchRow(chainId, {
        state: "setting",
        error: undefined,
        txHash: undefined,
      });
      try {
        const hash = await sendSponsored({
          chainId,
          address: m.token,
          abi: tokenAbi,
          functionName: "setYieldSplit",
          args: [keepBps],
        });
        patchRow(chainId, { state: "confirming", txHash: hash });
        // Wait on THIS chain's client — the wallet may be pointed elsewhere.
        // viem's raw wait RETURNS reverted receipts (wagmi's throws), so a
        // reverted update must read as failed, not done.
        const receipt = await publicClientFor(
          chainId,
        ).waitForTransactionReceipt({ hash });
        if (receipt.status === "reverted") {
          patchRow(chainId, { state: "failed", error: "Transaction reverted" });
          return;
        }
        patchRow(chainId, { state: "done" });
        // Re-read so the row's "current split" reflects the new value.
        try {
          patchRow(chainId, await readChain(m, address));
        } catch {
          /* transient — the next poll refreshes it */
        }
      } catch (e) {
        patchRow(chainId, { state: "failed", error: parseTxError(e) });
      }
    },
    [address, patchRow, sendSponsored],
  );

  /**
   * Fan the new split out to every family chain, sequentially — a self-paid
   * wallet has to switch networks between writes, so parallel submits would
   * race the switch (embedded wallets just sign each silently).
   */
  const setSplitEverywhere = useCallback(
    async (keepBps: number) => {
      for (const m of membersRef.current) {
        const row = rowsRef.current.find((r) => r.chainId === m.chainId);
        if (!row) continue;
        if (row.supported === false) continue; // token predates splits — skip
        if (row.unreachable) continue; // can't confirm anything there
        // Skip chains already at the target: the tx would be a pure no-op,
        // burning a signature (and gas, self-paid) to write the same value.
        if (row.keepBps === keepBps) continue;
        await setSplitOn(m.chainId, keepBps);
      }
    },
    [setSplitOn],
  );

  return {
    rows,
    setSplitOn,
    setSplitEverywhere,
    anyBusy: rows.some(
      (r) => r.state === "setting" || r.state === "confirming",
    ),
  };
}
