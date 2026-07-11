import { parseAbiItem, type Address, type Log } from "viem";
import { publicClientFor } from "@/lib/instance";

/**
 * Client-side, serverless holder counter ("backers").
 *
 * There is no on-chain holder count, so we reconstruct one from the token's
 * ERC-20 `Transfer` logs: net balance deltas per address over a bounded block
 * window (mint = from 0x0, burn = to 0x0); a holder is any address whose net
 * balance is positive. Same architecture as distribution-history.ts: chunked
 * `getLogs` with bisection on range-limit errors, incremental localStorage
 * cache, fail-soft per chain.
 *
 * CAVEAT: the count reflects the scanned window only. A token older than the
 * initial lookback undercounts — holders whose last transfer predates the
 * window are invisible, and an address that only *sold* inside the window nets
 * negative (treated as not holding). A "load older"-style backfill would fix
 * this; deliberately not built yet.
 */

export const TRANSFER_EVENT = parseAbiItem(
  "event Transfer(address indexed from, address indexed to, uint256 value)",
);

/** Above this many tracked addresses we stop keeping the balance map and only
 *  persist the count — a localStorage/memory safety valve for huge tokens. */
export const HOLDER_MAP_CAP = 20_000;

/** A chain + the ERC-20 token whose `Transfer` events we index. */
export interface HolderTarget {
  chainId: number;
  token: Address;
}

export interface HolderScanResult {
  /** Lowercase addresses with a positive net balance — null once capped. */
  holders: Set<string> | null;
  count: number;
  capped: boolean;
  /** False when part of the window couldn't be scanned (count is a floor). */
  complete: boolean;
}

type TransferLog = Log<bigint, number, false, typeof TRANSFER_EVENT, true>;

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

/** Split [from, to] into ≤maxRange windows. */
function windows(
  from: bigint,
  to: bigint,
  maxRange: bigint,
): [bigint, bigint][] {
  const out: [bigint, bigint][] = [];
  for (let lo = from; lo <= to; lo += maxRange) {
    const hi = lo + maxRange - 1n;
    out.push([lo, hi > to ? to : hi]);
  }
  return out;
}

/**
 * Fetch `Transfer` logs for one token over [fromBlock, toBlock], chunked by
 * `maxRange` and bisecting any window the RPC rejects (range too large).
 * `complete` is false if a single-block window still failed after bisection —
 * the caller must then NOT advance its cache cursor past this range, so the
 * dropped block is re-scanned next time instead of becoming a permanent gap.
 */
async function fetchTransferLogs(
  chainId: number,
  token: Address,
  fromBlock: bigint,
  toBlock: bigint,
  maxRange: bigint,
): Promise<{ logs: TransferLog[]; complete: boolean }> {
  const client = publicClientFor(chainId);
  const stack = windows(fromBlock, toBlock, maxRange).reverse();
  const logs: TransferLog[] = [];
  let complete = true;
  while (stack.length > 0) {
    const [lo, hi] = stack.pop()!;
    if (lo > hi) continue;
    try {
      const got = await client.getLogs({
        address: token,
        event: TRANSFER_EVENT,
        fromBlock: lo,
        toBlock: hi,
      });
      logs.push(...(got as TransferLog[]));
    } catch {
      // Range too large / rate limited → split and retry, unless single block.
      if (hi > lo) {
        const mid = lo + (hi - lo) / 2n;
        stack.push([mid + 1n, hi], [lo, mid]);
      } else {
        // A single block still failed — the scan is incomplete for this range.
        complete = false;
      }
    }
  }
  return { logs, complete };
}

function applyDelta(
  balances: Map<string, bigint>,
  address: string,
  delta: bigint,
): void {
  const next = (balances.get(address) ?? 0n) + delta;
  // Zero entries carry no information — drop them so the cap counts real ones.
  if (next === 0n) balances.delete(address);
  else balances.set(address, next);
}

/** Fold transfer logs into per-address net deltas (0x0 = mint/burn, untracked). */
function applyDeltas(balances: Map<string, bigint>, logs: TransferLog[]): void {
  for (const log of logs) {
    const from = (log.args.from as Address).toLowerCase();
    const to = (log.args.to as Address).toLowerCase();
    const value = log.args.value as bigint;
    if (value === 0n || from === to) continue;
    if (from !== ZERO_ADDRESS) applyDelta(balances, from, -value);
    if (to !== ZERO_ADDRESS) applyDelta(balances, to, value);
  }
}

/* --------------------------- localStorage cache ---------------------------- */

interface HolderCacheEntry {
  /** Lowest block scanned so far (inclusive). */
  fromBlock: string;
  /** Highest block scanned so far (inclusive). */
  toBlock: string;
  capped: boolean;
  /** Net per-address balance deltas over [fromBlock, toBlock]; negative means
   *  the address also held tokens from before the window. Absent once capped. */
  balances?: Record<string, string>;
  /** Holder count frozen at cap time (the map itself is discarded). */
  count?: number;
}

const cacheKey = (chainId: number, token: Address) =>
  `crowdstake.holders.v1:${chainId}:${token.toLowerCase()}`;

function readCache(chainId: number, token: Address): HolderCacheEntry | null {
  if (typeof window === "undefined") return null;
  try {
    const raw = window.localStorage.getItem(cacheKey(chainId, token));
    return raw ? (JSON.parse(raw) as HolderCacheEntry) : null;
  } catch {
    return null;
  }
}

function writeCache(
  chainId: number,
  token: Address,
  entry: HolderCacheEntry,
): void {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(
      cacheKey(chainId, token),
      JSON.stringify(entry),
    );
  } catch {
    /* quota — skip caching */
  }
}

/* ------------------------------ public API -------------------------------- */

/**
 * Load one chain's holder set. Uses the localStorage cache and only scans the
 * gap up to the latest block (cheap on repeat visits). On the first scan it
 * looks back `initialLookback` blocks.
 */
export async function loadChainHolders(
  target: HolderTarget,
  opts: { initialLookback: bigint; maxRange: bigint } = {
    initialLookback: 400_000n,
    maxRange: 9_000n,
  },
): Promise<HolderScanResult> {
  const { chainId, token } = target;
  const cached = readCache(chainId, token);

  // Once capped the per-address map is gone, so the count can't be updated
  // incrementally — serve the frozen snapshot (a rescan affordance can reset
  // the cache later).
  if (cached?.capped) {
    return {
      holders: null,
      count: cached.count ?? 0,
      capped: true,
      complete: true,
    };
  }

  const client = publicClientFor(chainId);
  const latest = await client.getBlockNumber();

  const balances = new Map<string, bigint>();
  if (cached?.balances) {
    for (const [addr, v] of Object.entries(cached.balances))
      balances.set(addr, BigInt(v));
  }

  let scanFrom: bigint;
  let coveredFrom: bigint;
  if (cached) {
    // Top up forward to the latest block.
    scanFrom = BigInt(cached.toBlock) + 1n;
    coveredFrom = BigInt(cached.fromBlock);
  } else {
    scanFrom =
      latest < opts.initialLookback ? 0n : latest - opts.initialLookback + 1n;
    coveredFrom = scanFrom;
  }

  let complete = true;
  if (scanFrom <= latest) {
    const res = await fetchTransferLogs(
      chainId,
      token,
      scanFrom,
      latest,
      opts.maxRange,
    );
    complete = res.complete;
    applyDeltas(balances, res.logs);
  }

  const holders = new Set<string>();
  for (const [addr, v] of balances) if (v > 0n) holders.add(addr);
  const capped = balances.size > HOLDER_MAP_CAP;

  // Unlike distribution rounds (deduped by txHash), balance deltas are NOT
  // idempotent — persisting a partially-scanned range would double-apply this
  // pass's logs when the range is re-scanned. So on an incomplete scan the old
  // cache is left untouched and only the best-effort merge is RETURNED.
  if (complete) {
    if (capped) {
      writeCache(chainId, token, {
        fromBlock: coveredFrom.toString(),
        toBlock: latest.toString(),
        capped: true,
        count: holders.size,
      });
    } else {
      const record: Record<string, string> = {};
      for (const [addr, v] of balances) record[addr] = v.toString();
      writeCache(chainId, token, {
        fromBlock: coveredFrom.toString(),
        toBlock: latest.toString(),
        capped: false,
        balances: record,
      });
    }
  }

  return {
    holders: capped ? null : holders,
    count: holders.size,
    capped,
    complete,
  };
}
