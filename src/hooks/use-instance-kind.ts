"use client";

import { useReadContract } from "wagmi";
import { poolAbi } from "@/lib/abis";
import { useActiveChainId, useInstance } from "@/components/instance-provider";

/**
 * What sits at `instance.token`: a classic transferable token, or a StakePool
 * (no token issued — deposits tracked in the underlying asset, no
 * transfer/approve, symbol() is the UNDERLYING's).
 */
export type InstanceKind = "pool" | "token";

export interface InstanceKindState {
  /** undefined while the probe is in flight (hydration-safe first render). */
  kind: InstanceKind | undefined;
  /** Convenience: kind === "pool". False while undetermined, so every pool-only
   *  copy branch renders the classic (token) copy until the probe resolves —
   *  token instances stay byte-identical to before pool mode existed. */
  isPool: boolean;
}

/**
 * Feature-detect the instance kind by probing `isPool()` on the token slot —
 * pools return true, classic tokens revert (the same probe-and-revert pattern
 * as useYieldSplit's `supported`). No retry: a revert IS the answer.
 *
 * Instance switches happen IN PLACE (no remount), but wagmi keys this query on
 * chainId + address + functionName, so switching instances re-probes the new
 * token address automatically — no stale kind can bleed across instances.
 */
export function useInstanceKind(): InstanceKindState {
  const a = useInstance();
  const chainId = useActiveChainId();
  const read = useReadContract({
    address: a.token,
    abi: poolAbi,
    functionName: "isPool",
    chainId,
    query: { retry: false },
  });
  const kind: InstanceKind | undefined = read.isError
    ? "token"
    : read.data !== undefined
      ? read.data
        ? "pool"
        : "token"
      : undefined;
  return { kind, isPool: kind === "pool" };
}
