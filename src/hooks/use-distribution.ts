"use client";

import { useReadContract } from "wagmi";
import { distributionManagerAbi } from "@/lib/abis";
import { ADDRESSES, CHAIN_ID } from "@/lib/constants";
import { useTx } from "@/hooks/use-tx";

/** Whether the protocol can run a distribution right now (all gates satisfied). */
export function useDistributionReady() {
  const ready = useReadContract({
    address: ADDRESSES.distributionManager,
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
  const tx = useTx();
  const distribute = () =>
    tx.run({
      address: ADDRESSES.distributionManager,
      abi: distributionManagerAbi,
      functionName: "claimAndDistribute",
      args: [],
    });
  return { distribute, ...tx };
}
