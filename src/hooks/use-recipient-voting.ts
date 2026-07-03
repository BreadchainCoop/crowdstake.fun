"use client";

import { useMemo } from "react";
import { type Address } from "viem";
import { useReadContract, useReadContracts } from "wagmi";
import { votingRecipientRegistryAbi } from "@/lib/abis";
import { useActiveChainId, useInstance } from "@/components/instance-provider";
import { useTx } from "@/hooks/use-tx";

const LIVE = { refetchInterval: 12_000 } as const;

export interface Proposal {
  id: number;
  candidate: Address;
  isAddition: boolean;
  voteCount: bigint;
  requiredVotes: bigint;
  executed: boolean;
  createdAt: bigint;
}

export type RegistryKind = "admin" | "voting" | "unknown";

// Cache the resolved kind per registry address so a transient RPC error can
// never flip a voting registry into the admin UI (which would call a function
// that reverts on it). Only a clean execution-revert downgrades to admin.
const kindCache = new Map<string, "admin" | "voting">();

/**
 * Detect whether the active instance's recipient registry is admin-controlled
 * or democratic (vote-controlled). Probes proposalExpiry(), which only exists
 * on the voting registry.
 */
export function useRegistryKind(): { kind: RegistryKind; isLoading: boolean } {
  const a = useInstance();
  const chainId = useActiveChainId();
  const key = a.recipientRegistry.toLowerCase();
  const probe = useReadContract({
    address: a.recipientRegistry,
    abi: votingRecipientRegistryAbi,
    functionName: "proposalExpiry",
    chainId,
    query: { retry: 1, staleTime: Infinity },
  });

  if (!kindCache.has(key)) {
    if (probe.data !== undefined) {
      kindCache.set(key, "voting");
    } else if (probe.isError) {
      // A missing selector returns no data / reverts; a network error doesn't.
      const msg = probe.error?.message ?? "";
      if (
        /returned no data|reverted|execution reverted|is not a function/i.test(
          msg,
        )
      ) {
        kindCache.set(key, "admin");
      }
    }
  }

  const cached = kindCache.get(key);
  if (cached) return { kind: cached, isLoading: false };
  return { kind: "unknown", isLoading: probe.isLoading };
}

/** The democratic registry's proposal-expiry window (seconds). */
export function useProposalExpiry() {
  const a = useInstance();
  const chainId = useActiveChainId();
  const r = useReadContract({
    address: a.recipientRegistry,
    abi: votingRecipientRegistryAbi,
    functionName: "proposalExpiry",
    chainId,
  });
  return r.data as bigint | undefined;
}

/** All proposals (newest first), read via proposalCount + batched getProposal. */
export function useProposals() {
  const a = useInstance();
  const chainId = useActiveChainId();
  const count = useReadContract({
    address: a.recipientRegistry,
    abi: votingRecipientRegistryAbi,
    functionName: "proposalCount",
    chainId,
    query: LIVE,
  });
  const n = count.data ? Number(count.data) : 0;

  const contracts = useMemo(
    () =>
      Array.from({ length: n }, (_, i) => ({
        address: a.recipientRegistry,
        abi: votingRecipientRegistryAbi,
        functionName: "getProposal" as const,
        args: [BigInt(i)] as const,
        chainId,
      })),
    [a.recipientRegistry, chainId, n],
  );
  const reads = useReadContracts({
    contracts,
    query: { enabled: n > 0, ...LIVE },
  });

  const proposals = useMemo<Proposal[]>(() => {
    if (!reads.data) return [];
    const out: Proposal[] = [];
    reads.data.forEach((r, i) => {
      if (r.status !== "success" || !r.result) return;
      const [
        candidate,
        isAddition,
        voteCount,
        requiredVotes,
        executed,
        createdAt,
      ] = r.result as readonly [
        Address,
        boolean,
        bigint,
        bigint,
        boolean,
        bigint,
      ];
      out.push({
        id: i,
        candidate,
        isAddition,
        voteCount,
        requiredVotes,
        executed,
        createdAt,
      });
    });
    return out.reverse(); // newest first
  }, [reads.data]);

  return {
    proposals,
    isLoading: count.isLoading || reads.isLoading,
    refetch: () => {
      void count.refetch();
      void reads.refetch();
    },
  };
}

/** Per-proposal voter state for the connected account (batched). */
export function useProposalsMeta(proposals: Proposal[], voter?: Address) {
  const a = useInstance();
  const chainId = useActiveChainId();
  const contracts = useMemo(() => {
    if (!voter) return [];
    return proposals.flatMap((p) => [
      {
        address: a.recipientRegistry,
        abi: votingRecipientRegistryAbi,
        functionName: "hasVoted" as const,
        args: [BigInt(p.id), voter] as const,
        chainId,
      },
      {
        address: a.recipientRegistry,
        abi: votingRecipientRegistryAbi,
        functionName: "isEligibleVoter" as const,
        args: [BigInt(p.id), voter] as const,
        chainId,
      },
    ]);
  }, [a.recipientRegistry, chainId, proposals, voter]);

  const reads = useReadContracts({
    contracts,
    query: { enabled: contracts.length > 0, ...LIVE },
  });

  return useMemo(() => {
    const map = new Map<number, { hasVoted: boolean; eligible: boolean }>();
    if (!voter || !reads.data) return map;
    proposals.forEach((p, i) => {
      const hv = reads.data[i * 2];
      const el = reads.data[i * 2 + 1];
      map.set(p.id, {
        hasVoted: hv?.status === "success" ? Boolean(hv.result) : false,
        eligible: el?.status === "success" ? Boolean(el.result) : false,
      });
    });
    return map;
  }, [proposals, reads.data, voter]);
}

/* ----------------------------- Write actions ----------------------------- */

export function useProposeRecipient() {
  const a = useInstance();
  const tx = useTx();
  const proposeAdd = (candidate: Address) =>
    tx.run({
      address: a.recipientRegistry,
      abi: votingRecipientRegistryAbi,
      functionName: "proposeAddition",
      args: [candidate],
    });
  const proposeRemove = (candidate: Address) =>
    tx.run({
      address: a.recipientRegistry,
      abi: votingRecipientRegistryAbi,
      functionName: "proposeRemoval",
      args: [candidate],
    });
  return { proposeAdd, proposeRemove, ...tx };
}

export function useVoteOnProposal() {
  const a = useInstance();
  const tx = useTx();
  const vote = (id: number) =>
    tx.run({
      address: a.recipientRegistry,
      abi: votingRecipientRegistryAbi,
      functionName: "vote",
      args: [BigInt(id)],
    });
  return { vote, ...tx };
}

export function useExecuteProposal() {
  const a = useInstance();
  const tx = useTx();
  const execute = (id: number) =>
    tx.run({
      address: a.recipientRegistry,
      abi: votingRecipientRegistryAbi,
      functionName: "executeProposal",
      args: [BigInt(id)],
    });
  return { execute, ...tx };
}

export function useSetProposalExpiry() {
  const a = useInstance();
  const tx = useTx();
  const setExpiry = (seconds: bigint) =>
    tx.run({
      address: a.recipientRegistry,
      abi: votingRecipientRegistryAbi,
      functionName: "setProposalExpiry",
      args: [seconds],
    });
  return { setExpiry, ...tx };
}
