"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { erc20Abi, type Address, type Hex } from "viem";
import { useAccount } from "wagmi";
import { tokenAbi } from "@/lib/abis";
import { chainConfig } from "@/lib/chains";
import { publicClientFor } from "@/lib/instance";
import { parseTxError } from "@/hooks/use-tx";
import { useWalletActions } from "@/components/wallet/wallet-actions";
import type { FamilyState } from "@/hooks/use-family";

/** Per-chain action state for one family chain's withdrawal. */
export type FamilyWithdrawState =
  "idle" | "withdrawing" | "confirming" | "done" | "failed";

export interface FamilyWithdrawRow {
  chainId: number;
  token: Address;
  /** Raw balance in the token's OWN decimals (L2 mirrors are 6-dp USDC). */
  balance?: bigint;
  /**
   * That chain's token decimals — amount parse/format MUST use these, never a
   * global 18, or a "1.0" typed on an L2 would burn 10^12 times too much.
   */
  decimals?: number;
  /** What burning redeems into on this chain (native currency or stablecoin). */
  redeemSymbol: string;
  /** Reads failed on this chain — balance unknown. */
  unreachable?: boolean;
  state: FamilyWithdrawState;
  txHash?: Hex;
  error?: string;
}

const POLL_MS = 12_000; // match the single-chain balance read cadence

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

/**
 * Burning redeems the base asset the instance's vault holds: the native
 * currency on native-yield chains, the stablecoin on stable-yield ones —
 * same rule as the single-chain page's redeem symbol.
 */
function redeemSymbolFor(chainId: number): string {
  const cfg = chainConfig(chainId);
  return cfg.yieldKind === "stable"
    ? cfg.wrappedSymbol
    : cfg.chain.nativeCurrency.symbol;
}

/** The refreshable read fields — patched by polls without touching tx state. */
type ChainReads = Pick<
  FamilyWithdrawRow,
  "balance" | "decimals" | "unreachable"
>;

async function readChain(
  m: Member,
  owner: Address | undefined,
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
  // No wallet → no balance to show (explicit undefined so a disconnect clears
  // the previous account's balance instead of leaving it on screen).
  const balance = owner
    ? await client.readContract({
        address: m.token,
        abi: erc20Abi,
        functionName: "balanceOf",
        args: [owner],
      })
    : undefined;
  return { balance, decimals, unreachable: false };
}

/**
 * Family-wide withdraw: one row per sibling chain with the connected wallet's
 * LOCAL token balance there, each independently burnable — the token is not
 * bridged, so redeeming the whole position means one burn per chain. Writes go
 * through the sponsored wallet layer (gasless on embedded wallets,
 * chain-switching self-paid otherwise) and each receipt is awaited on that
 * chain's OWN client and status-checked (viem's raw wait RETURNS reverted
 * receipts). Fail-soft per chain: a dead RPC marks the row unreachable without
 * breaking the rest.
 */
export function useFamilyWithdraw(family: FamilyState) {
  const { address } = useAccount();
  const { sendSponsored } = useWalletActions();

  const [rows, setRowsState] = useState<FamilyWithdrawRow[]>([]);
  const rowsRef = useRef<FamilyWithdrawRow[]>([]);
  const membersRef = useRef<Member[]>([]);
  // decimals never change per token — read once per sibling, then reuse.
  const decimalsCache = useRef(new Map<number, number>());

  const setRows = useCallback(
    (updater: (prev: FamilyWithdrawRow[]) => FamilyWithdrawRow[]) => {
      rowsRef.current = updater(rowsRef.current);
      setRowsState(rowsRef.current);
    },
    [],
  );

  const patchRow = useCallback(
    (chainId: number, patch: Partial<FamilyWithdrawRow>) => {
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
            redeemSymbol: redeemSymbolFor(m.chainId),
            state: "idle" as FamilyWithdrawState,
          },
      ),
    );

    let cancelled = false;
    const load = async () => {
      await Promise.all(
        members.map(async (m) => {
          try {
            const data = await readChain(m, address, decimalsCache.current);
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

  /**
   * Withdraw on ONE chain: `burn(amount, receiver)` — the exact call the
   * single-chain flow makes (use-token.ts useWithdraw), receiver = the
   * connected wallet. Independent and per-row retryable.
   */
  const withdrawOn = useCallback(
    async (chainId: number, amountRaw: bigint) => {
      const m = membersRef.current.find((x) => x.chainId === chainId);
      const row = rowsRef.current.find((r) => r.chainId === chainId);
      if (!m || !row || !address || amountRaw <= 0n) return;
      if (row.state === "withdrawing" || row.state === "confirming") return;
      patchRow(chainId, {
        state: "withdrawing",
        error: undefined,
        txHash: undefined,
      });
      try {
        const hash = await sendSponsored({
          chainId,
          address: m.token,
          abi: tokenAbi,
          functionName: "burn",
          args: [amountRaw, address],
        });
        patchRow(chainId, { state: "confirming", txHash: hash });
        // Wait on THIS chain's client — the wallet may be pointed elsewhere.
        // viem's raw wait RETURNS reverted receipts (wagmi's throws), so a
        // failed burn must read as failed, not done.
        const receipt = await publicClientFor(
          chainId,
        ).waitForTransactionReceipt({ hash });
        if (receipt.status === "reverted") {
          patchRow(chainId, {
            state: "failed",
            error: "Transaction reverted",
          });
          return;
        }
        patchRow(chainId, { state: "done" });
        // Re-read so the drained balance shows immediately.
        try {
          patchRow(chainId, await readChain(m, address, decimalsCache.current));
        } catch {
          /* transient — the next poll refreshes it */
        }
      } catch (e) {
        patchRow(chainId, { state: "failed", error: parseTxError(e) });
      }
    },
    [address, patchRow, sendSponsored],
  );

  return {
    rows,
    withdrawOn,
    anyBusy: rows.some(
      (r) => r.state === "withdrawing" || r.state === "confirming",
    ),
  };
}
