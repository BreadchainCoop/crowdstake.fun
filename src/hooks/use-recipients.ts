"use client";

import type { Address } from "viem";
import { useAccount, useReadContract } from "wagmi";
import { recipientRegistryAbi } from "@/lib/abis";
import { ADDRESSES, CHAIN_ID } from "@/lib/constants";
import { useTx } from "@/hooks/use-tx";

const LIVE = { refetchInterval: 15_000 } as const;

/** Active recipients + pending queue (additions/removals). */
export function useRecipients() {
  const recipients = useReadContract({
    address: ADDRESSES.recipientRegistry,
    abi: recipientRegistryAbi,
    functionName: "getRecipients",
    chainId: CHAIN_ID,
    query: LIVE,
  });
  const queuedAdditions = useReadContract({
    address: ADDRESSES.recipientRegistry,
    abi: recipientRegistryAbi,
    functionName: "getQueuedAdditions",
    chainId: CHAIN_ID,
    query: LIVE,
  });
  const queuedRemovals = useReadContract({
    address: ADDRESSES.recipientRegistry,
    abi: recipientRegistryAbi,
    functionName: "getQueuedRemovals",
    chainId: CHAIN_ID,
    query: LIVE,
  });
  return {
    recipients: (recipients.data ?? []) as readonly Address[],
    queuedAdditions: (queuedAdditions.data ?? []) as readonly Address[],
    queuedRemovals: (queuedRemovals.data ?? []) as readonly Address[],
    isLoading: recipients.isLoading,
    refetch: () => {
      void recipients.refetch();
      void queuedAdditions.refetch();
      void queuedRemovals.refetch();
    },
  };
}

export function useIsRecipient(account?: Address) {
  const { address } = useAccount();
  const who = account ?? address;
  return useReadContract({
    address: ADDRESSES.recipientRegistry,
    abi: recipientRegistryAbi,
    functionName: "isRecipient",
    args: who ? [who] : undefined,
    chainId: CHAIN_ID,
    query: { enabled: Boolean(who) },
  });
}

/** Registry admin (owner) — used to gate the admin UI. */
export function useRegistryOwner() {
  const { address } = useAccount();
  const owner = useReadContract({
    address: ADDRESSES.recipientRegistry,
    abi: recipientRegistryAbi,
    functionName: "owner",
    chainId: CHAIN_ID,
  });
  return {
    owner: owner.data as Address | undefined,
    isAdmin:
      Boolean(address) &&
      Boolean(owner.data) &&
      address?.toLowerCase() === (owner.data as Address)?.toLowerCase(),
  };
}

/* ----------------------------- Admin actions ----------------------------- */

export function useQueueRecipientAddition() {
  const tx = useTx();
  const queue = (recipient: Address) =>
    tx.run({
      address: ADDRESSES.recipientRegistry,
      abi: recipientRegistryAbi,
      functionName: "queueRecipientAddition",
      args: [recipient],
    });
  return { queue, ...tx };
}

export function useQueueRecipientRemoval() {
  const tx = useTx();
  const queue = (recipient: Address) =>
    tx.run({
      address: ADDRESSES.recipientRegistry,
      abi: recipientRegistryAbi,
      functionName: "queueRecipientRemoval",
      args: [recipient],
    });
  return { queue, ...tx };
}

export function useProcessQueue() {
  const tx = useTx();
  const process = () =>
    tx.run({
      address: ADDRESSES.recipientRegistry,
      abi: recipientRegistryAbi,
      functionName: "processQueue",
      args: [],
    });
  return { process, ...tx };
}
