"use client";

import { BaseError, ContractFunctionRevertedError } from "viem";
import { useReadContract } from "wagmi";
import { poolAbi } from "@/lib/abis";
import { useActiveChainId, useInstance } from "@/components/instance-provider";

/** True when a read failed because the contract REVERTED (vs a flaky RPC). */
function isRevert(error: unknown): boolean {
  return (
    error instanceof BaseError &&
    error.walk((e) => e instanceof ContractFunctionRevertedError) !== null
  );
}

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
 * pools return true, classic tokens REVERT (the same probe-and-revert pattern
 * as useYieldSplit's `supported`).
 *
 * A revert IS the answer ("token" — don't retry it), but a transient RPC
 * failure is NOT: mapping any error → "token" would flash token-asserting UI
 * (the $TICKER row, "You receive X", the Backers chip) on a POOL whenever its
 * first read hit a flaky RPC. So classify with BaseError.walk like the recast
 * probe: revert → "token"; a non-revert error leaves `kind` undefined and
 * retries up to twice, keeping pool-neutral UI until a real answer lands.
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
    query: {
      retry: (failureCount, error) => !isRevert(error) && failureCount < 2,
    },
  });
  // Only a REVERT asserts "token"; a non-revert error keeps kind undefined
  // (the query is still retrying) so the UI stays pool-neutral.
  const kind: InstanceKind | undefined =
    read.isError && isRevert(read.error)
      ? "token"
      : read.data !== undefined
        ? read.data
          ? "pool"
          : "token"
        : undefined;
  return { kind, isPool: kind === "pool" };
}
