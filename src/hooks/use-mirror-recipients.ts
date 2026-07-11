"use client";

import { useCallback, useState } from "react";
import type { Address } from "viem";
import { recipientRegistryAbi } from "@/lib/abis";
import { publicClientFor } from "@/lib/instance";
import { parseTxError } from "@/hooks/use-tx";
import { useWalletActions } from "@/components/wallet/wallet-actions";

/**
 * The membership delta needed to bring a sibling chain's recipient set in line
 * with the reference (active) chain: recipients to add, recipients to remove.
 */
export interface RecipientDiff {
  toAdd: Address[];
  toRemove: Address[];
}

/** Set-diff of two recipient lists (case-insensitive, order-agnostic). */
export function diffRecipients(
  reference: readonly Address[],
  sibling: readonly Address[],
): RecipientDiff {
  const ref = new Set(reference.map((a) => a.toLowerCase()));
  const sib = new Set(sibling.map((a) => a.toLowerCase()));
  return {
    toAdd: reference.filter((a) => !sib.has(a.toLowerCase())),
    toRemove: sibling.filter((a) => !ref.has(a.toLowerCase())),
  };
}

export type MirrorState = "idle" | "signing" | "confirming" | "done" | "error";

/**
 * Mirror a sibling chain's admin recipient registry to match the reference set:
 * queue the additions/removals, then processQueue — all on that sibling's chain
 * (receipts awaited on the sibling's own viem client). Admin-registry only;
 * democratic families aren't offered multi-chain. Writes go through the
 * wallet-actions layer: gas-sponsored (gasless, chain targeted per call) on a
 * Privy embedded wallet, else a self-paid write that chain-switches itself.
 */
export function useMirrorRecipients() {
  const { sendSponsored } = useWalletActions();
  const [busyChain, setBusyChain] = useState<number | null>(null);
  const [state, setState] = useState<MirrorState>("idle");
  const [error, setError] = useState<string | null>(null);

  const mirror = useCallback(
    async (chainId: number, registry: Address, diff: RecipientDiff) => {
      if (diff.toAdd.length === 0 && diff.toRemove.length === 0) return;
      setBusyChain(chainId);
      setError(null);
      setState("signing");
      const client = publicClientFor(chainId);
      try {
        // Queue additions and removals (batched calls where there's > 0).
        if (diff.toAdd.length > 0) {
          const hash = await sendSponsored({
            chainId,
            address: registry,
            abi: recipientRegistryAbi,
            functionName: "queueRecipientsAddition",
            args: [diff.toAdd],
          });
          setState("confirming");
          await client.waitForTransactionReceipt({ hash });
        }
        if (diff.toRemove.length > 0) {
          setState("signing");
          const hash = await sendSponsored({
            chainId,
            address: registry,
            abi: recipientRegistryAbi,
            functionName: "queueRecipientsRemoval",
            args: [diff.toRemove],
          });
          setState("confirming");
          await client.waitForTransactionReceipt({ hash });
        }
        // Apply the queued changes.
        setState("signing");
        const processHash = await sendSponsored({
          chainId,
          address: registry,
          abi: recipientRegistryAbi,
          functionName: "processQueue",
          args: [],
        });
        setState("confirming");
        await client.waitForTransactionReceipt({ hash: processHash });
        setState("done");
      } catch (e) {
        setError(parseTxError(e));
        setState("error");
      } finally {
        setBusyChain(null);
      }
    },
    [sendSponsored],
  );

  return { mirror, busyChain, state, error };
}
