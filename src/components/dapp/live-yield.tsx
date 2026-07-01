"use client";

import { formatUnits } from "viem";
import { useLiveYield } from "@/hooks/use-live-yield";
import { useDemoMode, DEMO_MULTIPLIER } from "@/components/demo-mode-provider";
import { TOKEN_DECIMALS } from "@/lib/constants";

/**
 * The instance's accrued yield, ticking up live. Applies the demo multiplier
 * and shows extra fractional digits so the counter visibly moves.
 */
export function LiveYield({ symbol }: { symbol: string }) {
  const wei = useLiveYield();
  const { demo } = useDemoMode();
  if (wei === undefined) return <span>—</span>;
  const scaled = demo ? wei * DEMO_MULTIPLIER : wei;
  const n = Number(formatUnits(scaled, TOKEN_DECIMALS));
  return (
    <span className="tabular-nums">
      {n.toLocaleString(undefined, {
        minimumFractionDigits: 4,
        maximumFractionDigits: 6,
      })}{" "}
      {symbol}
    </span>
  );
}
