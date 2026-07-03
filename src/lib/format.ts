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

/** ~human string for a duration in seconds (e.g. "~3h", "~2 days"). */
export function formatDuration(seconds: number): string {
  if (seconds <= 0) return "ready";
  if (seconds < 60) return `~${Math.round(seconds)}s`;
  const minutes = seconds / 60;
  if (minutes < 60) return `~${Math.round(minutes)} min`;
  const hours = minutes / 60;
  if (hours < 48) return `~${Math.round(hours)}h`;
  const days = hours / 24;
  return `~${Math.round(days)} day${Math.round(days) === 1 ? "" : "s"}`;
}

/** ~human duration for a number of blocks, given the chain's block time. */
export function blocksToDuration(
  blocks: bigint | number,
  blockTimeSeconds: number,
): string {
  const b = Number(blocks);
  if (b <= 0) return "ready";
  return formatDuration(b * blockTimeSeconds);
}

/** Convert a human duration (seconds) to a whole number of blocks. */
export function durationToBlocks(
  seconds: number,
  blockTimeSeconds: number,
): bigint {
  if (!(seconds > 0) || !(blockTimeSeconds > 0)) return 0n;
  // Ceil so the on-chain cycle never ends up *shorter* than the requested
  // duration (a 13s ask at 12s/block → 2 blocks, not 1); min 1 block.
  return BigInt(Math.max(1, Math.ceil(seconds / blockTimeSeconds)));
}
