"use client";

import { useEffect, useState } from "react";
import type { Hex } from "viem";
import { useLiveYieldDetails } from "@/hooks/use-live-yield";
import { useTokenStats } from "@/hooks/use-token";
import { useActiveChainId, useInstance } from "@/components/instance-provider";

const MS_PER_YEAR = 365 * 24 * 60 * 60 * 1000;
const CACHE_PREFIX = "crowdstake.apy.v1";
/** A remeasured APY older than this is shown from cache but re-measured. */
const CACHE_TTL_MS = 24 * 60 * 60 * 1000;

/** Family-wide inputs (from useFamilyStats) — pass to rate the WHOLE family. */
export interface FamilyApyInput {
  familyId: Hex | null;
  ratePerMs: number;
  totalStaked18?: bigint;
}

/**
 * Estimated APY (percent) for the active instance. These vault-agnostic tokens
 * expose no `vaultAPY()` oracle (unlike crowdstaking-v2's sDAI adaptor), so we
 * annualize the observed `yieldAccrued()` growth rate against `totalSupply` —
 * no archive reads, works on any chain/vault. Two on-chain readings (~one
 * stats interval) are needed before a fresh measurement lands, so the last
 * measurement is cached per token for instant display on revisits. Donated
 * yield only: a community keeping part of its yield reads slightly low.
 *
 * Pass `family` (from useFamilyStats) to rate a family across ALL its chains —
 * the single-chain view of a family can be empty (zero supply) on the chain
 * being browsed while the community earns elsewhere.
 */
export function useApy(family?: FamilyApyInput): number | undefined {
  const single = useLiveYieldDetails();
  const { totalSupply } = useTokenStats();
  const a = useInstance();
  const chainId = useActiveChainId();

  const familyMode = Boolean(family?.familyId);
  const ratePerMs = familyMode ? family!.ratePerMs : single.ratePerMs;
  const supply = familyMode ? family!.totalStaked18 : totalSupply;
  const cacheKey = familyMode
    ? `${CACHE_PREFIX}:family:${family!.familyId}`
    : `${CACHE_PREFIX}:${chainId}:${a.token.toLowerCase()}`;

  // The cache is read in an effect — never during render — so the prerendered
  // HTML and the first client paint agree ("—"), then the cached value pops in
  // (the DemoModeProvider hydration pattern). Keyed on the instance so an
  // in-place switch re-reads the right token's entry.
  const [cached, setCached] = useState<number | undefined>(undefined);
  useEffect(() => {
    try {
      const raw = window.localStorage.getItem(cacheKey);
      if (!raw) {
        setCached(undefined);
        return;
      }
      const { apy, t } = JSON.parse(raw) as { apy: number; t: number };
      setCached(Date.now() - t < CACHE_TTL_MS ? apy : undefined);
    } catch {
      setCached(undefined);
    }
  }, [cacheKey]);

  // A live measurement supersedes (and refreshes) the cache.
  const measured =
    supply && supply > 0n && ratePerMs > 0
      ? (ratePerMs * MS_PER_YEAR * 100) / Number(supply)
      : undefined;

  useEffect(() => {
    if (measured === undefined || !Number.isFinite(measured)) return;
    setCached(measured);
    try {
      window.localStorage.setItem(
        cacheKey,
        JSON.stringify({ apy: measured, t: Date.now() }),
      );
    } catch {
      /* storage full/blocked — stay measurement-only */
    }
  }, [measured, cacheKey]);

  // Note: token decimals cancel out of rate/supply (both are in the token's
  // own units), so no scaling is needed.
  return measured ?? cached;
}
