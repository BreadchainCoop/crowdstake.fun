"use client";

import { Caption } from "@breadcoop/ui";
import { formatAmount } from "@/lib/format";

/** Token amount input with a label, balance readout, and MAX shortcut. */
export function AmountField({
  label,
  value,
  onChange,
  balance,
  symbol,
  decimals = 18,
}: {
  label: string;
  value: string;
  onChange: (v: string) => void;
  balance?: bigint;
  symbol: string;
  decimals?: number;
}) {
  return (
    <div>
      <div className="flex items-baseline justify-between">
        <Caption className="text-surface-grey-2">{label}</Caption>
        {balance !== undefined && (
          <button
            type="button"
            onClick={() => onChange(formatAmountForInput(balance, decimals))}
            className="text-core-orange text-xs font-medium hover:underline"
          >
            Balance: {formatAmount(balance, 4, decimals)} {symbol} · MAX
          </button>
        )}
      </div>
      <div className="border-paper-2 bg-paper-main focus-within:border-core-orange mt-2 flex items-center gap-2 rounded-xl border px-4 py-3">
        <input
          inputMode="decimal"
          placeholder="0.0"
          value={value}
          onChange={(e) => onChange(e.target.value)}
          className="font-breadDisplay text-text-standard placeholder:text-surface-grey w-full bg-transparent text-2xl font-bold outline-none"
        />
        <span className="font-breadDisplay text-surface-grey-2 font-bold">
          {symbol}
        </span>
      </div>
    </div>
  );
}

/** Full-precision string for the input (no thousands separators). */
function formatAmountForInput(value: bigint, decimals: number): string {
  const s = (Number(value) / 10 ** decimals).toString();
  // For large/precise values, fall back to a manual fixed conversion.
  if (s.includes("e")) {
    const whole = value / 10n ** BigInt(decimals);
    const frac = value % 10n ** BigInt(decimals);
    const fracStr = frac.toString().padStart(decimals, "0").replace(/0+$/, "");
    return fracStr ? `${whole}.${fracStr}` : `${whole}`;
  }
  return s;
}
