"use client";

import { useEffect, useState } from "react";
import type { AbiEvent, Address } from "viem";
import { useAccount } from "wagmi";
import { votingModuleAbi } from "@/lib/abis";
import { publicClientFor } from "@/lib/instance";
import { useActiveChainId, useInstance } from "@/components/instance-provider";
import type { FamilyState } from "@/hooks/use-family";

/**
 * Lifetime votes cast by the connected wallet — crowdstaking-v2's "Votes
 * casted" stat, rebuilt serverless (v2 asks a subgraph). Counts distinct
 * voting transactions from `VoteCast` + `CrossChainVoteCast` logs (both index
 * the voter, so every scan is topic-filtered and cheap), across all family
 * chains for families. Cached incrementally in localStorage; tx-hash sets
 * merge idempotently, so re-scanned ranges are harmless (unlike balance
 * deltas in holder-count).
 */

// Pull the event defs from the real ABI so the topic hashes can't drift from
// the deployed contracts. Coverage matters: the classic in-app vote path emits
// ONLY VoteWithData; signature paths emit VoteCast/VoteCastWithParams; family
// deliveries emit CrossChainVoteCast (+VoteCast in the same tx).
const VOTE_EVENT_NAMES = [
  "VoteCast",
  "CrossChainVoteCast",
  "VoteCastWithParams",
  "VoteWithData",
] as const;
const VOTE_EVENTS = votingModuleAbi.filter(
  (e): e is Extract<typeof e, { type: "event" }> =>
    e.type === "event" &&
    (VOTE_EVENT_NAMES as readonly string[]).includes(e.name),
) as unknown as AbiEvent[];

const INITIAL_LOOKBACK = 400_000n;
const MAX_RANGE = 9_000n;

interface VoteCache {
  fromBlock: string;
  toBlock: string;
  txHashes: string[];
  /** Ballot nonces (events that carry one) — the family dedupe key: one
   * signed ballot lands as a separate tx on EVERY chain, so tx hashes
   * overcount families ×chains while its nonce is identical everywhere. */
  nonces: string[];
}

// v2: v1 lacked VoteWithData coverage + nonces, and its cursors have already
// advanced past historical blocks — a key bump re-scans cleanly.
const cacheKey = (chainId: number, module: Address, voter: string) =>
  `crowdstake.votecount.v2:${chainId}:${module.toLowerCase()}:${voter}`;

function readCache(key: string): VoteCache | null {
  try {
    const raw = window.localStorage.getItem(key);
    return raw ? (JSON.parse(raw) as VoteCache) : null;
  } catch {
    return null;
  }
}

const bigMax = (a: bigint, b: bigint) => (a > b ? a : b);

/** Scan one chain's voting module for the voter's vote txs (topic-filtered). */
async function loadChainVotes(
  chainId: number,
  module: Address,
  voter: Address,
): Promise<{ txHashes: Set<string>; nonces: Set<string>; complete: boolean }> {
  const client = publicClientFor(chainId);
  const latest = await client.getBlockNumber();
  const key = cacheKey(chainId, module, voter.toLowerCase());
  const cached = typeof window !== "undefined" ? readCache(key) : null;

  const txHashes = new Set<string>(cached?.txHashes ?? []);
  const nonces = new Set<string>(cached?.nonces ?? []);
  const scanFrom = cached
    ? BigInt(cached.toBlock) + 1n
    : latest < INITIAL_LOOKBACK
      ? 0n
      : latest - INITIAL_LOOKBACK + 1n;
  const coveredFrom = cached ? BigInt(cached.fromBlock) : scanFrom;

  let complete = true;
  // Chunked scan with bisection on range-limit errors (distribution-history's
  // approach); a window that still fails at one block marks the scan partial
  // so the cursor doesn't advance past it.
  const stack: [bigint, bigint][] = [];
  for (let lo = scanFrom; lo <= latest; lo += MAX_RANGE) {
    const hi = lo + MAX_RANGE - 1n;
    stack.push([lo, hi > latest ? latest : hi]);
  }
  stack.reverse();
  while (stack.length > 0) {
    const [lo, hi] = stack.pop()!;
    if (lo > hi) continue;
    try {
      const got = await Promise.all(
        VOTE_EVENTS.map((event) =>
          client.getLogs({
            address: module,
            event,
            args: { voter },
            fromBlock: lo,
            toBlock: hi,
          }),
        ),
      );
      for (const logs of got)
        for (const log of logs) {
          txHashes.add(log.transactionHash);
          const nonce = (log.args as { nonce?: bigint }).nonce;
          if (nonce !== undefined) nonces.add(nonce.toString());
        }
    } catch {
      if (hi > lo) {
        const mid = lo + (hi - lo) / 2n;
        stack.push([mid + 1n, hi], [lo, mid]);
      } else {
        complete = false;
      }
    }
  }

  // Tx-hash sets union idempotently, so persisting found hashes is always
  // safe; the cursor only ADVANCES when complete, and never regresses on a
  // lagging RPC (bigMax — same guard as the other scanners).
  if (typeof window !== "undefined") {
    const newTo = complete
      ? cached
        ? bigMax(BigInt(cached.toBlock), latest)
        : latest
      : (cached?.toBlock ?? null);
    if (newTo !== null) {
      try {
        window.localStorage.setItem(
          key,
          JSON.stringify({
            fromBlock: coveredFrom.toString(),
            toBlock: newTo.toString(),
            txHashes: [...txHashes],
            nonces: [...nonces],
          } satisfies VoteCache),
        );
      } catch {
        /* quota — skip caching */
      }
    }
  }
  return { txHashes, nonces, complete };
}

export interface VoteCount {
  /** Distinct vote transactions, all time (within the scanned window). */
  count?: number;
  isLoading: boolean;
  /** Some chain failed or a range was dropped — the count is a floor. */
  partial: boolean;
}

/** Lifetime vote count for the connected wallet (all family chains). */
export function useVoteCount(family: FamilyState): VoteCount {
  const { address } = useAccount();
  const a = useInstance();
  const chainId = useActiveChainId();
  const [state, setState] = useState<VoteCount>({
    isLoading: false,
    partial: false,
  });

  // One scan target per chain the instance lives on.
  const targetKey = family.isFamily
    ? family.perChain
        .filter((c) => c.instance)
        .map((c) => `${c.chainId}:${c.instance!.votingModule.toLowerCase()}`)
        .sort()
        .join(",")
    : family.isLoading
      ? "" // wait for family resolution — avoids a throwaway classic scan
      : `${chainId}:${a.votingModule.toLowerCase()}`;
  const voter = address?.toLowerCase() ?? "";

  useEffect(() => {
    if (!targetKey || !voter) {
      setState({ isLoading: false, partial: false });
      return;
    }
    const targets = targetKey.split(",").map((t) => {
      const [cid, module] = t.split(":");
      return { chainId: Number(cid), module: module as Address };
    });

    let cancelled = false;
    setState({ isLoading: true, partial: false });
    void (async () => {
      const results = await Promise.allSettled(
        targets.map((t) =>
          loadChainVotes(t.chainId, t.module, voter as Address),
        ),
      );
      if (cancelled) return;
      let partial = false;
      let any = false;
      // Families: one signed ballot is DELIVERED on every chain (distinct tx
      // per chain, identical nonce family-wide) — count distinct nonces, not
      // txs. Classic: the in-app path (VoteWithData) has no nonce — count
      // distinct txs on the single chain.
      const nonceUnion = new Set<string>();
      let classicTxCount = 0;
      for (const r of results) {
        if (r.status === "fulfilled") {
          any = true;
          for (const n of r.value.nonces) nonceUnion.add(n);
          classicTxCount += r.value.txHashes.size;
          partial ||= !r.value.complete;
        } else {
          partial = true;
        }
      }
      const count = targets.length > 1 ? nonceUnion.size : classicTxCount;
      setState({
        count: any ? count : undefined,
        isLoading: false,
        partial,
      });
    })();
    return () => {
      cancelled = true;
    };
  }, [targetKey, voter]);

  return state;
}
