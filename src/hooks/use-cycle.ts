"use client";

import { useBlockNumber, useReadContract } from "wagmi";
import { cycleModuleAbi } from "@/lib/abis";
import { CHAIN_ID } from "@/lib/constants";
import { useInstance } from "@/components/instance-provider";

const LIVE = { refetchInterval: 12_000 } as const;

/** Current cycle status: number, length, progress, blocks remaining. */
export function useCycle() {
  const a = useInstance();
  const { data: blockNumber } = useBlockNumber({
    chainId: CHAIN_ID,
    watch: true,
  });

  const cycle = useReadContract({
    address: a.cycleModule,
    abi: cycleModuleAbi,
    functionName: "getCurrentCycle",
    chainId: CHAIN_ID,
    query: LIVE,
  });
  const length = useReadContract({
    address: a.cycleModule,
    abi: cycleModuleAbi,
    functionName: "cycleLength",
    chainId: CHAIN_ID,
  });
  const lastStart = useReadContract({
    address: a.cycleModule,
    abi: cycleModuleAbi,
    functionName: "lastCycleStartBlock",
    chainId: CHAIN_ID,
    query: LIVE,
  });
  const complete = useReadContract({
    address: a.cycleModule,
    abi: cycleModuleAbi,
    functionName: "isCycleComplete",
    chainId: CHAIN_ID,
    query: LIVE,
  });
  const blocksLeft = useReadContract({
    address: a.cycleModule,
    abi: cycleModuleAbi,
    functionName: "getBlocksUntilNextCycle",
    chainId: CHAIN_ID,
    query: LIVE,
  });

  const cycleLength = length.data;
  const lastStartBlock = lastStart.data;
  let progress = 0;
  if (
    cycleLength &&
    lastStartBlock !== undefined &&
    blockNumber !== undefined
  ) {
    const elapsed = Number(blockNumber - lastStartBlock);
    progress = Math.min(1, Math.max(0, elapsed / Number(cycleLength)));
  }

  return {
    cycleNumber: cycle.data,
    cycleLength,
    lastStartBlock,
    blockNumber,
    isComplete: complete.data ?? false,
    blocksUntilNext: blocksLeft.data ?? 0n,
    progress,
    isLoading: cycle.isLoading || length.isLoading,
    refetch: () => {
      void cycle.refetch();
      void complete.refetch();
      void lastStart.refetch();
      void blocksLeft.refetch();
    },
  };
}
