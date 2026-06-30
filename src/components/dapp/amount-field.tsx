"use client";

import { formatUnits } from "viem";
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
            onClick={() => onChange(formatUnits(balance, decimals))}
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
