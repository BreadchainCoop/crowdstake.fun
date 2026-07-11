"use client";

import { useEffect, useRef, useState } from "react";
import { erc20Abi } from "viem";
import { tokenAbi } from "@/lib/abis";
import { publicClientFor } from "@/lib/instance";
import type { FamilyState } from "@/hooks/use-family";

/** Aggregated live stats across every reachable chain of a family. */
export interface FamilyStats {
  /** Σ totalSupply across siblings, normalized to 18 decimals. */
  totalStaked18?: bigint;
  /** Σ yieldAccrued across siblings, normalized to 18 decimals. */
  yieldAccrued18?: bigint;
  /** Chains included in the sums. */
  chains: number;
  /** True when at least one sibling was unreachable (sums are a floor). */
  partial: boolean;
}

const POLL_MS = 12_000; // match the single-chain token stats cadence
const scaleTo18 = (value: bigint, decimals: number) =>
  decimals >= 18 ? value : value * 10n ** BigInt(18 - decimals);

/**
 * Family-wide staked/yield totals: fans out `totalSupply()` + `yieldAccrued()`
 * to every sibling chain's token, normalizes to 18 decimals (the L2 tokens
 * mirror USDC's 6), and sums. Fail-soft per chain — a dead RPC drops that
 * chain from the sums and flags `partial`. Inert (all-undefined) for classic
 * single-chain instances.
 */
export function useFamilyStats(family: FamilyState): FamilyStats {
  const [stats, setStats] = useState<FamilyStats>({
    chains: 0,
    partial: false,
  });
  // decimals never change per token — read once per sibling, then reuse.
  const decimalsCache = useRef(new Map<string, number>());

  // Key the effect on the family's membership, not object identity.
  const memberKey = family.isFamily
    ? family.perChain
        .filter((c) => c.instance)
        .map((c) => `${c.chainId}:${c.instance!.token.toLowerCase()}`)
        .sort()
        .join(",")
    : "";

  useEffect(() => {
    if (!memberKey) {
      setStats({ chains: 0, partial: false });
      return;
    }
    const members = memberKey.split(",").map((m) => {
      const [chainId, token] = m.split(":");
      return { chainId: Number(chainId), token: token as `0x${string}` };
    });

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
      setStats({
        totalStaked18: ok.length
          ? ok.reduce((s, c) => s + c.staked, 0n)
          : undefined,
        yieldAccrued18: ok.length
          ? ok.reduce((s, c) => s + c.accrued, 0n)
          : undefined,
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
