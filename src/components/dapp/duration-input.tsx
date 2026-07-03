"use client";

import { useState } from "react";

const UNITS = [
  { key: "minutes", seconds: 60 },
  { key: "hours", seconds: 3600 },
  { key: "days", seconds: 86400 },
] as const;

type UnitKey = (typeof UNITS)[number]["key"];

const secondsFor = (unit: UnitKey) =>
  UNITS.find((u) => u.key === unit)!.seconds;

/**
 * A time-duration input (number + unit) that reports a total in seconds. Cycle
 * lengths are entered as time here and converted to blocks per chain, so the
 * user never has to think in blocks.
 */
export function DurationInput({
  defaultAmount = "",
  defaultUnit = "hours",
  onChange,
  disabled,
}: {
  defaultAmount?: string;
  defaultUnit?: UnitKey;
  onChange: (seconds: number) => void;
  disabled?: boolean;
}) {
  const [amount, setAmount] = useState(defaultAmount);
  const [unit, setUnit] = useState<UnitKey>(defaultUnit);

  const emit = (a: string, u: UnitKey) => {
    const n = Number(a);
    onChange(Number.isFinite(n) && n > 0 ? n * secondsFor(u) : 0);
  };

  const input =
    "border-paper-2 bg-paper-main text-text-standard focus:border-core-orange rounded-xl border px-4 py-2.5 outline-none disabled:opacity-60";

  return (
    <div className="flex gap-2">
      <input
        type="number"
        min="0"
        inputMode="decimal"
        value={amount}
        disabled={disabled}
        onChange={(e) => {
          setAmount(e.target.value);
          emit(e.target.value, unit);
        }}
        placeholder="e.g. 24"
        className={`${input} w-full`}
      />
      <select
        value={unit}
        disabled={disabled}
        onChange={(e) => {
          const u = e.target.value as UnitKey;
          setUnit(u);
          emit(amount, u);
        }}
        className={input}
      >
        {UNITS.map((u) => (
          <option key={u.key} value={u.key}>
            {u.key}
          </option>
        ))}
      </select>
    </div>
  );
}
