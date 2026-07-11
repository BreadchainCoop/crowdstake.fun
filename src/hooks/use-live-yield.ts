"use client";

import { useEffect, useRef, useState } from "react";
import { useTokenStats } from "@/hooks/use-token";
import { useActiveChainId, useInstance } from "@/components/instance-provider";

export interface LiveYieldDetails {
  /** Extrapolated accrued yield, in wei. */
  live: bigint | undefined;
  /** Measured accrual rate in wei/ms (0 until two on-chain readings landed). */
  ratePerMs: number;
}

/**
 * A continuously-ticking accrued-yield value. It anchors on the on-chain
 * `yieldAccrued()` (refetched on the token stats' interval), estimates the
 * growth rate from successive readings (smoothed against RPC jitter), and
 * extrapolates between them so the number visibly counts up. Resets (after a
 * distribution) just re-anchor lower. The measured rate is exposed so derived
 * stats (APY, projected-at-cycle-end) share one estimator.
 */
export function useLiveYieldDetails(): LiveYieldDetails {
  const { yieldAccrued } = useTokenStats();
  const a = useInstance();
  const chainId = useActiveChainId();
  const tokenKey = `${chainId}:${a.token.toLowerCase()}`;
  const anchor = useRef<{ value: bigint; t: number } | null>(null);
  const rate = useRef(0); // wei per ms
  const [live, setLive] = useState<bigint | undefined>(undefined);
  const [ratePerMs, setRatePerMs] = useState(0);

  // Instance switches happen IN PLACE (no remount): drop the previous token's
  // anchor and rate, or a cross-token delta over a tiny dt would masquerade as
  // an absurd accrual rate (and poison the APY estimate downstream).
  useEffect(() => {
    anchor.current = null;
    rate.current = 0;
    setRatePerMs(0);
    setLive(undefined);
  }, [tokenKey]);

  // Recalibrate on each fresh on-chain reading.
  useEffect(() => {
    if (yieldAccrued === undefined) return;
    const now = Date.now();
    const prev = anchor.current;
    if (prev && yieldAccrued > prev.value && now > prev.t) {
      const r = Number(yieldAccrued - prev.value) / (now - prev.t);
      rate.current = rate.current === 0 ? r : rate.current * 0.5 + r * 0.5;
      setRatePerMs(rate.current);
    }
    anchor.current = { value: yieldAccrued, t: now };
    setLive(yieldAccrued);
  }, [yieldAccrued]);

  // Extrapolate ~10x/second between readings.
  useEffect(() => {
    const id = setInterval(() => {
      const a = anchor.current;
      if (!a) return;
      const extra = rate.current * (Date.now() - a.t);
      setLive(a.value + BigInt(Math.max(0, Math.floor(extra))));
    }, 100);
    return () => clearInterval(id);
  }, []);

  return { live, ratePerMs };
}

/** Just the ticking accrued-yield value, in wei. */
export function useLiveYield(): bigint | undefined {
  return useLiveYieldDetails().live;
}
