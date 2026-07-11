"use client";

import { useEffect, useRef, useState } from "react";
import { erc20Abi, type Address } from "viem";
import { useAccount } from "wagmi";
import { tokenAbi } from "@/lib/abis";
import { publicClientFor } from "@/lib/instance";
import type { FamilyState } from "@/hooks/use-family";

/** Aggregated live stats across every reachable chain of a family. */
export interface FamilyStats {
  /** Σ totalSupply across siblings, normalized to 18 decimals. */
  totalStaked18?: bigint;
  /** Σ yieldAccrued across siblings, normalized to 18 decimals. */
  yieldAccrued18?: bigint;
  /**
   * Measured family-wide accrual rate, 18-dp wei/ms (0 until two polls landed).
   * Same estimator as the single-chain live-yield ticker, over the summed
   * accrued value.
   */
  ratePerMs: number;
  /** Chains included in the sums. */
  chains: number;
  /** True when at least one sibling was unreachable (sums are a floor). */
  partial: boolean;
}

const POLL_MS = 12_000; // match the single-chain token stats cadence
const scaleTo18 = (value: bigint, decimals: number) =>
  decimals >= 18 ? value : value * 10n ** BigInt(18 - decimals);

/** Serialize the family membership so effects key on content, not identity. */
function familyMemberKey(family: FamilyState): string {
  if (!family.isFamily) return "";
  return family.perChain
    .filter((c) => c.instance)
    .map((c) => `${c.chainId}:${c.instance!.token.toLowerCase()}`)
    .sort()
    .join(",");
}

function parseMembers(memberKey: string) {
  return memberKey.split(",").map((m) => {
    const [chainId, token] = m.split(":");
    return { chainId: Number(chainId), token: token as Address };
  });
}

/**
 * Family-wide staked/yield totals: fans out `totalSupply()` + `yieldAccrued()`
 * to every sibling chain's token, normalizes to 18 decimals (the L2 tokens
 * mirror USDC's 6), and sums. Fail-soft per chain — a dead RPC drops that
 * chain from the sums and flags `partial`. Inert (all-undefined) for classic
 * single-chain instances.
 */
export function useFamilyStats(family: FamilyState): FamilyStats {
  const [stats, setStats] = useState<FamilyStats>({
    ratePerMs: 0,
    chains: 0,
    partial: false,
  });
  // decimals never change per token — read once per sibling, then reuse.
  const decimalsCache = useRef(new Map<string, number>());
  // Rate estimation over the summed accrued (only comparable when the same
  // chain set responded — a chain dropping out would fake a negative delta).
  const anchor = useRef<{ value: bigint; t: number; chains: number } | null>(
    null,
  );
  const rate = useRef(0);

  const memberKey = familyMemberKey(family);

  useEffect(() => {
    // New family (or in-place instance switch) — old anchors are meaningless.
    anchor.current = null;
    rate.current = 0;
    if (!memberKey) {
      setStats({ ratePerMs: 0, chains: 0, partial: false });
      return;
    }
    const members = parseMembers(memberKey);

    let cancelled = false;
    const load = async () => {
      const perChain = await Promise.all(
        members.map(async (m) => {
          try {
            const client = publicClientFor(m.chainId);
            const key = `${m.chainId}:${m.token}`;
            let decimals = decimalsCache.current.get(key);
            if (decimals === undefined) {
              decimals = await client.readContract({
                address: m.token,
                abi: erc20Abi,
                functionName: "decimals",
              });
              decimalsCache.current.set(key, decimals);
            }
            const [supply, accrued] = await Promise.all([
              client.readContract({
                address: m.token,
                abi: erc20Abi,
                functionName: "totalSupply",
              }),
              client.readContract({
                address: m.token,
                abi: tokenAbi,
                functionName: "yieldAccrued",
              }) as Promise<bigint>,
            ]);
            return {
              staked: scaleTo18(supply, decimals),
              accrued: scaleTo18(accrued, decimals),
            };
          } catch {
            return null; // chain unreachable — sum what we can
          }
        }),
      );
      if (cancelled) return;
      const ok = perChain.filter((c) => c !== null);
      const accruedSum = ok.length
        ? ok.reduce((s, c) => s + c.accrued, 0n)
        : undefined;

      if (accruedSum !== undefined) {
        const now = Date.now();
        const prev = anchor.current;
        if (
          prev &&
          prev.chains === ok.length && // same coverage — delta is real
          accruedSum > prev.value &&
          now > prev.t
        ) {
          const r = Number(accruedSum - prev.value) / (now - prev.t);
          rate.current = rate.current === 0 ? r : rate.current * 0.5 + r * 0.5;
        }
        anchor.current = { value: accruedSum, t: now, chains: ok.length };
      }

      setStats({
        totalStaked18: ok.length
          ? ok.reduce((s, c) => s + c.staked, 0n)
          : undefined,
        yieldAccrued18: accruedSum,
        ratePerMs: rate.current,
        chains: ok.length,
        partial: ok.length < members.length,
      });
    };

    void load();
    const id = setInterval(() => void load(), POLL_MS);
    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, [memberKey]);

  return stats;
}

/** The connected wallet's family-wide position. */
export interface FamilyPosition {
  /** Σ balanceOf across siblings, normalized to 18 decimals. */
  balance18?: bigint;
  /** Σ getVotes across siblings, normalized to 18 decimals. */
  votes18?: bigint;
  /** Per-chain balances (18-dp), for the "0.5 on Arbitrum" breakdown. */
  perChain: { chainId: number; balance18: bigint }[];
  partial: boolean;
}

/**
 * The connected wallet's position summed across every family chain — a family
 * member usually holds the token on several chains, and the portfolio should
 * headline the whole holding, not just the chain being viewed.
 */
export function useFamilyPosition(family: FamilyState): FamilyPosition {
  const { address } = useAccount();
  const [pos, setPos] = useState<FamilyPosition>({
    perChain: [],
    partial: false,
  });
  const decimalsCache = useRef(new Map<string, number>());

  const memberKey = familyMemberKey(family);
  const account = address?.toLowerCase() ?? "";

  useEffect(() => {
    if (!memberKey || !account) {
      setPos({ perChain: [], partial: false });
      return;
    }
    const members = parseMembers(memberKey);

    let cancelled = false;
    const load = async () => {
      const perChain = await Promise.all(
        members.map(async (m) => {
          try {
            const client = publicClientFor(m.chainId);
            const key = `${m.chainId}:${m.token}`;
            let decimals = decimalsCache.current.get(key);
            if (decimals === undefined) {
              decimals = await client.readContract({
                address: m.token,
                abi: erc20Abi,
                functionName: "decimals",
              });
              decimalsCache.current.set(key, decimals);
            }
            const [balance, votes] = await Promise.all([
              client.readContract({
                address: m.token,
                abi: erc20Abi,
                functionName: "balanceOf",
                args: [account as Address],
              }),
              client
                .readContract({
                  address: m.token,
                  abi: tokenAbi,
                  functionName: "getVotes",
                  args: [account as Address],
                })
                .catch(() => 0n) as Promise<bigint>,
            ]);
            return {
              chainId: m.chainId,
              balance18: scaleTo18(balance, decimals),
              votes18: scaleTo18(votes, decimals),
            };
          } catch {
            return null;
          }
        }),
      );
      if (cancelled) return;
      const ok = perChain.filter((c) => c !== null);
      setPos({
        balance18: ok.length
          ? ok.reduce((s, c) => s + c.balance18, 0n)
          : undefined,
        votes18: ok.length ? ok.reduce((s, c) => s + c.votes18, 0n) : undefined,
        perChain: ok.map(({ chainId, balance18 }) => ({ chainId, balance18 })),
        partial: ok.length < members.length,
      });
    };

    void load();
    const id = setInterval(() => void load(), POLL_MS);
    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, [memberKey, account]);

  return pos;
}
