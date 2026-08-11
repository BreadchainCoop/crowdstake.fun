"use client";

import { useCallback, useState } from "react";
import {
  type Address,
  BaseError,
  ContractFunctionRevertedError,
} from "viem";
import { useAccount, useReadContract, useSignTypedData } from "wagmi";
import { votingModuleAbi, votingPowerAbi } from "@/lib/abis";
import { useActiveChainId, useInstance } from "@/components/instance-provider";
import { publicClientFor } from "@/lib/instance";
import { parseTxError, useTx } from "@/hooks/use-tx";
import {
  CLASSIC_VOTE_TYPES,
  classicPointsHash,
  classicVoteDomain,
} from "@/lib/vote-signature";

const LIVE = { refetchInterval: 12_000 } as const;

/**
 * The connected account's actual voting power for the current cycle — the
 * value the Voting Power Strategy computes and the Voting Module uses to
 * weight votes (not raw token `getVotes`).
 */
export function useCurrentVotingPower(account?: Address) {
  const a = useInstance();
  const chainId = useActiveChainId();
  const { address } = useAccount();
  const owner = account ?? address;
  return useReadContract({
    address: a.votingPowerStrategy,
    abi: votingPowerAbi,
    functionName: "getCurrentVotingPower",
    args: owner ? [owner] : undefined,
    chainId,
    query: { enabled: Boolean(owner), ...LIVE },
  });
}

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

/**
 * Cast a direct vote (`vote`) or update an existing one (`recast`).
 *
 * First-time votes go through voteWithData; that path reverts
 * AlreadyVotedInCurrentCycle on a re-vote, so updating a ballot uses the
 * EIP-712 signature path instead: castVoteWithSignature only gates on nonce
 * uniqueness, and _processVote fully reverts the previous ballot's stored
 * allocations before applying the new one — recasting is designed in.
 */

/** True when a read failed because the contract REVERTED (vs a flaky RPC). */
function isRevert(error: unknown): boolean {
  return (
    error instanceof BaseError &&
    error.walk((e) => e instanceof ContractFunctionRevertedError) !== null
  );
}

export function useVote() {
  const a = useInstance();
  const chainId = useActiveChainId();
  const { address } = useAccount();
  const { signTypedDataAsync } = useSignTypedData();
  const tx = useTx();
  // Destructured so recast's useCallback can depend on the stable `run`
  // instead of the per-render `tx` object.
  const { run } = tx;

  // Feature-detect the signature path before enabling recast: a module that
  // doesn't expose VOTE_TYPEHASH won't have castVoteWithSignature either. A
  // reverting read IS the answer (no retry) — recast stays unavailable there
  // and the UI keeps the locked "already voted" behavior. The old live
  // default instance's v1 module passes this probe and verifiably recasts
  // (replaces, not double-counts) — see e2e/verify-classic-recast.ts.
  const typehash = useReadContract({
    address: a.votingModule,
    abi: votingModuleAbi,
    functionName: "VOTE_TYPEHASH",
    chainId,
    query: {
      // A REVERT is the answer (unsupported — don't retry it), but a transient
      // RPC failure isn't: without retry it would silently lock recast for the
      // whole mount on a capable chain.
      retry: (failureCount, error) => !isRevert(error) && failureCount < 2,
      staleTime: Infinity,
    },
  });
  const supportsRecast = typehash.isSuccess;
  const probePending = typehash.isPending;

  // The EIP-712 prompt (or the pre-sign nonce read) can fail before any tx
  // exists — surface that through the same status/error the page already
  // renders, since useTx only tracks errors from its own submission.
  const [signError, setSignError] = useState<string | null>(null);
  const [isSigningBallot, setIsSigningBallot] = useState(false);

  const vote = (points: bigint[]) => {
    setSignError(null);
    return run({
      address: a.votingModule,
      abi: votingModuleAbi,
      functionName: "voteWithData",
      args: [points, "0x"],
    });
  };

  const recast = useCallback(
    async (points: bigint[]) => {
      if (!address) return undefined;
      setSignError(null);
      setIsSigningBallot(true);
      let nonce: bigint;
      let signature: `0x${string}`;
      try {
        // Fresh nonce: wall-clock ms (same scheme as the cross-chain
        // chooseNonce). Classic nonces are per-voter set-membership, not
        // monotonic — only a same-millisecond reuse collides, so bump past
        // any already-used value.
        nonce = BigInt(Date.now());
        const client = publicClientFor(chainId);
        // The page's power guard polls at 12s — re-read at sign time so a
        // just-unstaked wallet can't record a 0-power ballot over its old one
        // (the classic entrypoint, unlike cross-chain, doesn't revert on it).
        const livePower = (await client.readContract({
          address: a.votingPowerStrategy,
          abi: votingPowerAbi,
          functionName: "getCurrentVotingPower",
          args: [address],
        })) as bigint;
        if (livePower === 0n) {
          setSignError("No voting power — deposit before updating your vote");
          return undefined;
        }
        while (
          await client.readContract({
            address: a.votingModule,
            abi: votingModuleAbi,
            functionName: "isNonceUsed",
            args: [address, nonce],
          })
        ) {
          nonce += 1n;
        }
        signature = await signTypedDataAsync({
          domain: classicVoteDomain(chainId, a.votingModule),
          types: CLASSIC_VOTE_TYPES,
          primaryType: "Vote",
          message: {
            voter: address,
            pointsHash: classicPointsHash(points),
            nonce,
          },
        });
      } catch (e) {
        setSignError(parseTxError(e));
        return undefined;
      } finally {
        setIsSigningBallot(false);
      }
      return run({
        address: a.votingModule,
        abi: votingModuleAbi,
        functionName: "castVoteWithSignature",
        args: [address, points, nonce, signature],
      });
    },
    [
      address,
      a.votingModule,
      a.votingPowerStrategy,
      chainId,
      signTypedDataAsync,
      run,
    ],
  );

  return {
    vote,
    recast,
    /** False on v1 modules (no castVoteWithSignature) — recast unavailable. */
    supportsRecast,
    /** VOTE_TYPEHASH probe still in flight — recast availability unknown. */
    recastProbePending: probePending,
    ...tx,
    isBusy: tx.isBusy || isSigningBallot,
    status: signError ? ("error" as const) : tx.status,
    error: signError ?? tx.error,
  };
}
