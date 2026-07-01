"use client";

import { useEffect, useRef, useState } from "react";
import { useTokenStats } from "@/hooks/use-token";

/**
 * A continuously-ticking accrued-yield value. It anchors on the on-chain
 * `yieldAccrued()` (refetched on the token stats' interval), estimates the
 * growth rate from successive readings (smoothed against RPC jitter), and
 * extrapolates between them so the number visibly counts up. Resets (after a
 * distribution) just re-anchor lower. Returns wei (bigint) or undefined.
 */
export function useLiveYield(): bigint | undefined {
  const { yieldAccrued } = useTokenStats();
  const anchor = useRef<{ value: bigint; t: number } | null>(null);
  const rate = useRef(0); // wei per ms
  const [live, setLive] = useState<bigint | undefined>(undefined);

  // Recalibrate on each fresh on-chain reading.
  useEffect(() => {
    if (yieldAccrued === undefined) return;
    const now = Date.now();
    const prev = anchor.current;
    if (prev && yieldAccrued > prev.value && now > prev.t) {
      const r = Number(yieldAccrued - prev.value) / (now - prev.t);
      rate.current = rate.current === 0 ? r : rate.current * 0.5 + r * 0.5;
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

  return live;
}
