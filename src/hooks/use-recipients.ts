"use client";

import type { Address } from "viem";
import { useAccount, useReadContract } from "wagmi";
import { recipientRegistryAbi } from "@/lib/abis";
import { CHAIN_ID } from "@/lib/constants";
import { useInstance } from "@/components/instance-provider";
import { useTx } from "@/hooks/use-tx";

const LIVE = { refetchInterval: 15_000 } as const;

/** Active recipients + pending queue (additions/removals). */
export function useRecipients() {
  const a = useInstance();
  const recipients = useReadContract({
    address: a.recipientRegistry,
    abi: recipientRegistryAbi,
    functionName: "getRecipients",
    chainId: CHAIN_ID,
    query: LIVE,
  });
  const queuedAdditions = useReadContract({
    address: a.recipientRegistry,
    abi: recipientRegistryAbi,
    functionName: "getQueuedAdditions",
    chainId: CHAIN_ID,
    query: LIVE,
  });
  const queuedRemovals = useReadContract({
    address: a.recipientRegistry,
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
  const a = useInstance();
  const { address } = useAccount();
  const who = account ?? address;
  return useReadContract({
    address: a.recipientRegistry,
    abi: recipientRegistryAbi,
    functionName: "isRecipient",
    args: who ? [who] : undefined,
    chainId: CHAIN_ID,
    query: { enabled: Boolean(who) },
  });
}

/** Registry admin (owner) — used to gate the admin UI. */
export function useRegistryOwner() {
  const a = useInstance();
  const { address } = useAccount();
  const owner = useReadContract({
    address: a.recipientRegistry,
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
  const a = useInstance();
  const tx = useTx();
  const queue = (recipient: Address) =>
    tx.run({
      address: a.recipientRegistry,
      abi: recipientRegistryAbi,
      functionName: "queueRecipientAddition",
      args: [recipient],
    });
  const queueMany = (recipients: Address[]) =>
    tx.run({
      address: a.recipientRegistry,
      abi: recipientRegistryAbi,
      functionName: "queueRecipientsAddition",
      args: [recipients],
    });
  return { queue, queueMany, ...tx };
}

export function useQueueRecipientRemoval() {
  const a = useInstance();
  const tx = useTx();
  const queue = (recipient: Address) =>
    tx.run({
      address: a.recipientRegistry,
      abi: recipientRegistryAbi,
      functionName: "queueRecipientRemoval",
      args: [recipient],
    });
  const queueMany = (recipients: Address[]) =>
    tx.run({
      address: a.recipientRegistry,
      abi: recipientRegistryAbi,
      functionName: "queueRecipientsRemoval",
      args: [recipients],
    });
  return { queue, queueMany, ...tx };
}

export function useProcessQueue() {
  const a = useInstance();
  const tx = useTx();
  const process = () =>
    tx.run({
      address: a.recipientRegistry,
      abi: recipientRegistryAbi,
      functionName: "processQueue",
      args: [],
    });
  return { process, ...tx };
}

/** Clear pending additions or removals without processing them. */
export function useClearQueue() {
  const a = useInstance();
  const tx = useTx();
  const clearAdditions = () =>
    tx.run({
      address: a.recipientRegistry,
      abi: recipientRegistryAbi,
      functionName: "clearAdditionQueue",
      args: [],
    });
  const clearRemovals = () =>
    tx.run({
      address: a.recipientRegistry,
      abi: recipientRegistryAbi,
      functionName: "clearRemovalQueue",
      args: [],
    });
  return { clearAdditions, clearRemovals, ...tx };
}

/** Transfer registry admin to a new address. */
export function useTransferAdmin() {
  const a = useInstance();
  const tx = useTx();
  const transferAdmin = (newAdmin: Address) =>
    tx.run({
      address: a.recipientRegistry,
      abi: recipientRegistryAbi,
      functionName: "transferAdmin",
      args: [newAdmin],
    });
  return { transferAdmin, ...tx };
}
