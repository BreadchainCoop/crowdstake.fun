"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { Address } from "viem";
import { tokenAbi } from "@/lib/abis";
import { useActiveChainId, useInstance } from "@/components/instance-provider";
import { publicClientFor } from "@/lib/instance";
import { chainConfig } from "@/lib/chains";
import {
  loadChainDistributions,
  toDecimal,
  type DistributionRound,
  type DistributionTarget,
} from "@/lib/distribution-history";
import { useFamily, type FamilyState } from "@/hooks/use-family";

/** Yield-token display metadata for one chain. */
interface TokenMeta {
  symbol: string;
  decimals: number;
}

/** One distribution round enriched with its chain's token display metadata. */
export interface EnrichedRound extends DistributionRound {
  symbol: string;
  decimals: number;
}

export interface ChainSummary {
  chainId: number;
  symbol: string;
  decimals: number;
  /** Total distributed on this chain (base units). */
  total: bigint;
  /** Same, normalized to a decimal number (for cross-chain comparison). */
  normalized: number;
  rounds: number;
}

export interface RecipientSummary {
  recipient: Address;
  /** Total received across all chains, normalized to a decimal number. */
  normalized: number;
  perChain: {
    chainId: number;
    amount: bigint;
    decimals: number;
    symbol: string;
  }[];
}

export interface DistributionHistory {
  /** Every distribution round across all chains, newest first. */
  rounds: EnrichedRound[];
  /** Per-chain totals. */
  chains: ChainSummary[];
  /** Per-recipient totals across chains, highest first. */
  recipients: RecipientSummary[];
  /** Family-wide total, normalized (stable-value ~$; each chain's stablecoin). */
  totalNormalized: number;
  roundCount: number;
  recipientCount: number;
  isFamily: boolean;
  /** Chains whose scan errored — their history is missing, so totals are partial. */
  failedChains: number[];
}

async function readTokenMeta(
  chainId: number,
  token: Address,
): Promise<TokenMeta> {
  const client = publicClientFor(chainId);
  try {
    const [decimals, symbol] = await Promise.all([
      client.readContract({
        address: token,
        abi: tokenAbi,
        functionName: "decimals",
      }),
      client.readContract({
        address: token,
        abi: tokenAbi,
        functionName: "symbol",
      }),
    ]);
    return { decimals: Number(decimals), symbol: String(symbol) };
  } catch {
    const cfg = chainConfig(chainId);
    return { decimals: 18, symbol: cfg.wrappedSymbol };
  }
}

function aggregate(
  rounds: DistributionRound[],
  meta: Map<number, TokenMeta>,
  isFamily: boolean,
  failedChains: number[],
): DistributionHistory {
  const metaFor = (chainId: number): TokenMeta =>
    meta.get(chainId) ?? { decimals: 18, symbol: "" };

  const enriched: EnrichedRound[] = rounds
    .map((r) => ({ ...r, ...metaFor(r.chainId) }))
    .sort((a, b) => b.timestamp - a.timestamp);

  // Per chain.
  const chainMap = new Map<number, ChainSummary>();
  for (const r of enriched) {
    const s =
      chainMap.get(r.chainId) ??
      ({
        chainId: r.chainId,
        symbol: r.symbol,
        decimals: r.decimals,
        total: 0n,
        normalized: 0,
        rounds: 0,
      } satisfies ChainSummary);
    s.total += r.total;
    s.normalized += toDecimal(r.total, r.decimals);
    s.rounds += 1;
    chainMap.set(r.chainId, s);
  }

  // Per recipient (aggregated across chains).
  const recMap = new Map<string, RecipientSummary>();
  for (const r of enriched) {
    for (const { recipient, amount } of r.recipients) {
      const key = recipient.toLowerCase();
      const rec =
        recMap.get(key) ??
        ({ recipient, normalized: 0, perChain: [] } satisfies RecipientSummary);
      rec.normalized += toDecimal(amount, r.decimals);
      const pc = rec.perChain.find((x) => x.chainId === r.chainId);
      if (pc) pc.amount += amount;
      else
        rec.perChain.push({
          chainId: r.chainId,
          amount,
          decimals: r.decimals,
          symbol: r.symbol,
        });
      recMap.set(key, rec);
    }
  }

  const chains = [...chainMap.values()].sort(
    (a, b) => b.normalized - a.normalized,
  );
  const recipients = [...recMap.values()].sort(
    (a, b) => b.normalized - a.normalized,
  );

  return {
    rounds: enriched,
    chains,
    recipients,
    totalNormalized: chains.reduce((s, c) => s + c.normalized, 0),
    roundCount: enriched.length,
    recipientCount: recipients.length,
    isFamily,
    failedChains,
  };
}

/**
 * Cross-chain yield-distribution history for the active instance (or its whole
 * family). Reads `Distributed` events from every chain's strategy client-side
 * (no server), then aggregates per chain and per recipient. `loadOlder` extends
 * the scanned window further into the past.
 */
export function useDistributionHistory() {
  return useDistributionHistoryForFamily(useFamily());
}

/**
 * Same, but reusing an already-loaded family — components that call useFamily
 * for other stats (e.g. the instance header) pass it in instead of fanning the
 * sibling resolution out a second time.
 */
export function useDistributionHistoryForFamily(family: FamilyState) {
  const instance = useInstance();
  const activeChainId = useActiveChainId();

  const [history, setHistory] = useState<DistributionHistory | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [seq, setSeq] = useState(0);
  const olderRef = useRef(0n);

  // The chains + strategies to index: family siblings, or the active instance.
  const targets: DistributionTarget[] = useMemo(() => {
    if (family.isFamily) {
      return family.perChain
        .filter((c) => c.status === "found" && c.instance)
        .map((c) => ({
          chainId: c.chainId,
          strategy: c.instance!.distributionStrategy,
        }));
    }
    return [
      { chainId: activeChainId, strategy: instance.distributionStrategy },
    ];
  }, [
    family.isFamily,
    family.perChain,
    activeChainId,
    instance.distributionStrategy,
  ]);

  // Token addresses per chain (for decimals/symbol).
  const tokens = useMemo(() => {
    const m = new Map<number, Address>();
    if (family.isFamily) {
      for (const c of family.perChain)
        if (c.status === "found" && c.instance)
          m.set(c.chainId, c.instance.token);
    } else {
      m.set(activeChainId, instance.token);
    }
    return m;
  }, [family.isFamily, family.perChain, activeChainId, instance.token]);

  const targetKey = targets.map((t) => `${t.chainId}:${t.strategy}`).join("|");

  // A "load older" request is scoped to the current target set — reset it when
  // the instance/family changes so we don't kick off an oversized scan.
  useEffect(() => {
    olderRef.current = 0n;
  }, [targetKey]);

  useEffect(() => {
    if (family.isLoading || targets.length === 0) return;
    let cancelled = false;
    setIsLoading(true);
    setError(null);
    void (async () => {
      try {
        const older = olderRef.current;
        // Per-chain: allSettled so one chain's RPC error surfaces as a partial
        // warning instead of silently undercounting the aggregated totals.
        const [settled, metaEntries] = await Promise.all([
          Promise.allSettled(
            targets.map((t) =>
              loadChainDistributions(t, {
                initialLookback: 200_000n,
                maxRange: 9_000n,
                ...(older > 0n ? { olderBlocks: older } : {}),
              }),
            ),
          ),
          Promise.all(
            [...tokens.entries()].map(async ([chainId, token]) => {
              const meta = await readTokenMeta(chainId, token);
              return [chainId, meta] as const;
            }),
          ),
        ]);
        if (cancelled) return;
        const rounds: DistributionRound[] = [];
        const failedChains: number[] = [];
        settled.forEach((res, i) => {
          if (res.status === "fulfilled") rounds.push(...res.value);
          else failedChains.push(targets[i].chainId);
        });
        // Every target failed → treat it as a hard error, not a partial view.
        if (failedChains.length === targets.length) {
          setError("Couldn't reach any chain to read distribution history.");
          setIsLoading(false);
          return;
        }
        const meta = new Map<number, TokenMeta>(metaEntries);
        setHistory(aggregate(rounds, meta, family.isFamily, failedChains));
      } catch (e) {
        if (!cancelled)
          setError(e instanceof Error ? e.message : "Failed to load history");
      } finally {
        if (!cancelled) setIsLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [targetKey, family.isLoading, seq]);

  const refetch = useCallback(() => setSeq((s) => s + 1), []);
  /** Extend the scanned window ~`blocks` further back and reload. */
  const loadOlder = useCallback((blocks = 400_000n) => {
    olderRef.current = blocks;
    setSeq((s) => s + 1);
  }, []);

  return { history, isLoading, error, refetch, loadOlder };
}
