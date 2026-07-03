"use client";

import { useCallback, useState } from "react";
import { useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { BaseError, type Abi, type Address } from "viem";
import { useActiveChainId } from "@/components/instance-provider";

/** Pull the most useful human-readable message out of a viem/wagmi error. */
export function parseTxError(err: unknown): string {
  if (!err) return "Transaction failed";
  if (err instanceof BaseError) {
    const short = err.shortMessage || err.message;
    if (short?.toLowerCase().includes("user rejected"))
      return "Rejected in wallet";
    return short || "Transaction failed";
  }
  if (err instanceof Error) {
    if (err.message.toLowerCase().includes("user rejected"))
      return "Rejected in wallet";
    return err.message;
  }
  return "Transaction failed";
}

export type TxStatus = "idle" | "signing" | "confirming" | "success" | "error";

/** A contract write request (loosely typed; validated against the ABI at runtime by viem). */
export interface TxRequest {
  address: Address;
  abi: Abi | readonly unknown[];
  functionName: string;
  args?: readonly unknown[];
  value?: bigint;
}

/**
 * Standard write → wait-for-receipt flow used by every action in the dapp.
 * `run(request)` submits a contract write and resolves with the tx hash;
 * `status`, `hash`, and `error` drive the UI.
 */
export function useTx() {
  const chainId = useActiveChainId();
  const {
    writeContractAsync,
    data: hash,
    isPending: isSigning,
    reset: resetWrite,
  } = useWriteContract();
  const [submitError, setSubmitError] = useState<string | null>(null);

  const {
    isLoading: isConfirming,
    isSuccess,
    error: receiptError,
  } = useWaitForTransactionReceipt({ hash, chainId });

  const run = useCallback(
    async (request: TxRequest): Promise<`0x${string}` | undefined> => {
      setSubmitError(null);
      try {
        return await writeContractAsync(
          request as Parameters<typeof writeContractAsync>[0],
        );
      } catch (e) {
        setSubmitError(parseTxError(e));
        return undefined;
      }
    },
    [writeContractAsync],
  );

  const reset = useCallback(() => {
    setSubmitError(null);
    resetWrite();
  }, [resetWrite]);

  const status: TxStatus = submitError
    ? "error"
    : isSuccess
      ? "success"
      : isConfirming
        ? "confirming"
        : isSigning
          ? "signing"
          : "idle";

  return {
    run,
    reset,
    hash,
    status,
    isBusy: isSigning || isConfirming,
    isSuccess,
    error: submitError ?? (receiptError ? parseTxError(receiptError) : null),
  };
}
