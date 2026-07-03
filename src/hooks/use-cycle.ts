"use client";

import { useBlockNumber, useReadContract } from "wagmi";
import { cycleModuleAbi } from "@/lib/abis";
import { useActiveChainId, useInstance } from "@/components/instance-provider";

const LIVE = { refetchInterval: 12_000 } as const;

/** Current cycle status: number, length, progress, blocks remaining. */
export function useCycle() {
  const a = useInstance();
  const chainId = useActiveChainId();
  const { data: blockNumber } = useBlockNumber({
    chainId,
    watch: true,
  });

  const cycle = useReadContract({
    address: a.cycleModule,
    abi: cycleModuleAbi,
    functionName: "getCurrentCycle",
    chainId,
    query: LIVE,
  });
  const length = useReadContract({
    address: a.cycleModule,
    abi: cycleModuleAbi,
    functionName: "cycleLength",
    chainId,
  });
  const lastStart = useReadContract({
    address: a.cycleModule,
    abi: cycleModuleAbi,
    functionName: "lastCycleStartBlock",
    chainId,
    query: LIVE,
  });
  const complete = useReadContract({
    address: a.cycleModule,
    abi: cycleModuleAbi,
    functionName: "isCycleComplete",
    chainId,
    query: LIVE,
  });
  const blocksLeft = useReadContract({
    address: a.cycleModule,
    abi: cycleModuleAbi,
    functionName: "getBlocksUntilNextCycle",
    chainId,
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
