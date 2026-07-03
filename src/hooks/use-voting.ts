"use client";

import { useAccount, useReadContract } from "wagmi";
import { votingModuleAbi, votingPowerAbi } from "@/lib/abis";
import { useActiveChainId, useInstance } from "@/components/instance-provider";
import { useTx } from "@/hooks/use-tx";

const LIVE = { refetchInterval: 12_000 } as const;

/**
 * Everything the vote page needs: current per-recipient vote distribution,
 * expected points length, max points, the connected user's voting power, and
 * whether they've voted this cycle.
 */
export function useVotingState() {
  const a = useInstance();
  const chainId = useActiveChainId();
  const { address } = useAccount();

  const distribution = useReadContract({
    address: a.votingModule,
    abi: votingModuleAbi,
    functionName: "getCurrentVotingDistribution",
    chainId,
    query: LIVE,
  });
  const expectedPointsLength = useReadContract({
    address: a.votingModule,
    abi: votingModuleAbi,
    functionName: "getExpectedPointsLength",
    chainId,
    query: LIVE,
  });
  const maxPoints = useReadContract({
    address: a.votingModule,
    abi: votingModuleAbi,
    functionName: "maxPoints",
    chainId,
  });
  const hasVoted = useReadContract({
    address: a.votingModule,
    abi: votingModuleAbi,
    functionName: "hasVotedInCurrentCycle",
    args: address ? [address] : undefined,
    chainId,
    query: { enabled: Boolean(address), ...LIVE },
  });
  const power = useReadContract({
    address: a.votingPowerStrategy,
    abi: votingPowerAbi,
    functionName: "getCurrentVotingPower",
    args: address ? [address] : undefined,
    chainId,
    query: { enabled: Boolean(address), ...LIVE },
  });

  return {
    distribution: (distribution.data ?? []) as readonly bigint[],
    expectedPointsLength: expectedPointsLength.data,
    maxPoints: maxPoints.data ?? 10_000n,
    hasVoted: hasVoted.data ?? false,
    votingPower: power.data,
    isLoading: distribution.isLoading,
    refetch: () => {
      void distribution.refetch();
      void hasVoted.refetch();
      void power.refetch();
    },
  };
}

/** Cast a direct vote: `points[]` (one per recipient, basis points). */
export function useVote() {
  const a = useInstance();
  const tx = useTx();
  const vote = (points: bigint[]) =>
    tx.run({
      address: a.votingModule,
      abi: votingModuleAbi,
      functionName: "voteWithData",
      args: [points, "0x"],
    });
  return { vote, ...tx };
}
