"use client";

import { useEffect, useMemo, useState } from "react";
import { useActiveChainId, useInstance } from "@/components/instance-provider";
import { loadChainHolders, type HolderTarget } from "@/lib/holder-count";
import type { FamilyState } from "@/hooks/use-family";

export interface BackersState {
  /** Unique holders across all scanned chains (undefined until a scan lands). */
  count?: number;
  isLoading: boolean;
  /** A chain failed or was only partially scanned — the count is a floor. */
  partial: boolean;
  /** A chain exceeded the tracked-address cap, so its holders couldn't be
   *  deduped against the other chains (that chain's count is added as-is). */
  capped: boolean;
}

/**
 * "Backers" = unique token holders, reconstructed from Transfer logs (see
 * holder-count.ts). Classic instances scan the active token; families scan
 * every sibling token and count the UNION of holder addresses across chains —
 * one person holding on two chains is one backer.
 *
 * Takes the caller's already-loaded family (the header calls useFamily for its
 * other stats — don't fan the family resolution out twice).
 *
 * CAVEAT: counts reflect the scanned block window; tokens older than the
 * lookback undercount until a "load older"-style extension exists.
 */
export function useBackers(family: FamilyState): BackersState {
  const instance = useInstance();
  const activeChainId = useActiveChainId();
  const [state, setState] = useState<BackersState>({
    isLoading: true,
    partial: false,
    capped: false,
  });

  // The chains + tokens to scan: family siblings, or the active instance.
  const targets: HolderTarget[] = useMemo(() => {
    if (family.isFamily) {
      return family.perChain
        .filter((c) => c.status === "found" && c.instance)
        .map((c) => ({ chainId: c.chainId, token: c.instance!.token }));
    }
    return [{ chainId: activeChainId, token: instance.token }];
  }, [family.isFamily, family.perChain, activeChainId, instance.token]);

  // Key the effect on serialized content, not array identity — perChain is a
  // fresh array on every family reload.
  const targetKey = targets
    .map((t) => `${t.chainId}:${t.token.toLowerCase()}`)
    .join("|");

  useEffect(() => {
    if (family.isLoading || targets.length === 0) return;
    let cancelled = false;
    setState((s) => ({ ...s, isLoading: true }));
    void (async () => {
      // Per-chain allSettled: one dead RPC surfaces as a partial count, not a
      // failure of the whole stat.
      const settled = await Promise.allSettled(
        targets.map((t) => loadChainHolders(t)),
      );
      if (cancelled) return;
      const union = new Set<string>();
      let cappedCount = 0;
      let capped = false;
      let failed = 0;
      let incomplete = false;
      for (const res of settled) {
        if (res.status !== "fulfilled") {
          failed += 1;
          continue;
        }
        if (!res.value.complete) incomplete = true;
        if (res.value.holders) {
          for (const addr of res.value.holders) union.add(addr);
        } else {
          cappedCount += res.value.count;
          capped = true;
        }
      }
      if (failed === targets.length) {
        // Nothing scanned — keep count undefined so the UI shows "—".
        setState({ isLoading: false, partial: true, capped: false });
        return;
      }
      setState({
        count: union.size + cappedCount,
        isLoading: false,
        partial: failed > 0 || incomplete,
        capped,
      });
    })();
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [targetKey, family.isLoading]);

  return state;
}
