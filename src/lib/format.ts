import { formatUnits, parseUnits, type Address } from "viem";
import { TOKEN_DECIMALS } from "@/lib/constants";

/** Format a bigint token amount (18 decimals) to a human string with `maxFrac` decimals. */
export function formatAmount(
  value: bigint | undefined,
  maxFrac = 4,
  decimals = TOKEN_DECIMALS,
): string {
  if (value === undefined) return "—";
  const s = formatUnits(value, decimals);
  const n = Number(s);
  if (Number.isNaN(n)) return s;
  return n.toLocaleString("en-US", {
    minimumFractionDigits: 0,
    maximumFractionDigits: maxFrac,
  });
}

/** Parse a user-entered decimal string into a bigint base unit. Returns null on bad input. */
export function parseAmount(
  input: string,
  decimals = TOKEN_DECIMALS,
): bigint | null {
  const trimmed = input.trim();
  if (!trimmed || Number.isNaN(Number(trimmed)) || Number(trimmed) < 0)
    return null;
  try {
    return parseUnits(trimmed, decimals);
  } catch {
    return null;
  }
}

/** 0x1234…abcd */
export function shortenAddress(address?: Address | string, chars = 4): string {
  if (!address) return "";
  return `${address.slice(0, 2 + chars)}…${address.slice(-chars)}`;
}

/** Format a percentage from a 0..1 fraction. */
export function formatPercent(fraction: number, frac = 1): string {
  return `${(fraction * 100).toLocaleString("en-US", {
    maximumFractionDigits: frac,
  })}%`;
}

/** ~human duration for a number of Gnosis blocks (≈5s each). */
export function blocksToDuration(blocks: bigint | number): string {
  const b = Number(blocks);
  if (b <= 0) return "ready";
  const seconds = b * 5;
  if (seconds < 60) return `~${seconds}s`;
  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return `~${minutes} min`;
  const hours = Math.round(minutes / 60);
  if (hours < 48) return `~${hours}h`;
  return `~${Math.round(hours / 24)}d`;
}
