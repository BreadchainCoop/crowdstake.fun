"use client";

import type { Address } from "viem";
import { useReadContract } from "wagmi";
import { cycleModuleAbi, tokenAbi } from "@/lib/abis";
import { useActiveChainId, useInstance } from "@/components/instance-provider";
import { useTx } from "@/hooks/use-tx";

/** Update the cycle length (blocks) for future cycles — registry/cycle owner only. */
export function useUpdateCycleLength() {
  const a = useInstance();
  const tx = useTx();
  const update = (blocks: bigint) =>
    tx.run({
      address: a.cycleModule,
      abi: cycleModuleAbi,
      functionName: "updateCycleLength",
      args: [blocks],
    });
  return { update, ...tx };
}

/** Read the token's yield-claimer state (current + pending two-phase transfer). */
export function useYieldClaimer() {
  const a = useInstance();
  const chainId = useActiveChainId();
  const current = useReadContract({
    address: a.token,
    abi: tokenAbi,
    functionName: "yieldClaimer",
    chainId,
  });
  const pending = useReadContract({
    address: a.token,
    abi: tokenAbi,
    functionName: "pendingYieldClaimer",
    chainId,
  });
  const finishedAt = useReadContract({
    address: a.token,
    abi: tokenAbi,
    functionName: "pendingFinishedAt",
    chainId,
  });
  return {
    current: current.data as Address | undefined,
    pending: pending.data as Address | undefined,
    pendingFinishedAt: finishedAt.data as bigint | undefined,
    refetch: () => {
      void current.refetch();
      void pending.refetch();
      void finishedAt.refetch();
    },
  };
}

/** Two-phase (14-day timelock) yield-claimer rotation — token owner only. */
export function useYieldClaimerAdmin() {
  const a = useInstance();
  const tx = useTx();
  const prepare = (newClaimer: Address) =>
    tx.run({
      address: a.token,
      abi: tokenAbi,
      functionName: "prepareNewYieldClaimer",
      args: [newClaimer],
    });
  const finalize = () =>
    tx.run({
      address: a.token,
      abi: tokenAbi,
      functionName: "finalizeNewYieldClaimer",
      args: [],
    });
  return { prepare, finalize, ...tx };
}
