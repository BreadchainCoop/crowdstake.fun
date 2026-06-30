"use client";

import { useReadContract } from "wagmi";
import { distributionManagerAbi } from "@/lib/abis";
import { CHAIN_ID } from "@/lib/constants";
import { useInstance } from "@/components/instance-provider";
import { useTx } from "@/hooks/use-tx";

/** Whether the protocol can run a distribution right now (all gates satisfied). */
export function useDistributionReady() {
  const a = useInstance();
  const ready = useReadContract({
    address: a.distributionManager,
    abi: distributionManagerAbi,
    functionName: "isDistributionReady",
    chainId: CHAIN_ID,
    query: { refetchInterval: 12_000 },
  });
  return {
    isReady: ready.data ?? false,
    isLoading: ready.isLoading,
    refetch: () => void ready.refetch(),
  };
}

/** Public keeper action: claim accrued yield, distribute to recipients, advance the cycle. */
export function useDistribute() {
  const a = useInstance();
  const tx = useTx();
  const distribute = () =>
    tx.run({
      address: a.distributionManager,
      abi: distributionManagerAbi,
      functionName: "claimAndDistribute",
      args: [],
    });
  return { distribute, ...tx };
}
