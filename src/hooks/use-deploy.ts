"use client";

import { useMemo } from "react";
import { decodeEventLog, type Address, type Hex } from "viem";
import { useWaitForTransactionReceipt, useWriteContract } from "wagmi";
import { deployerAbi } from "@/lib/abis";
import { DEPLOYER } from "@/lib/constants";
import { parseTxError } from "@/hooks/use-tx";
import type { InstanceAddresses } from "@/lib/instance";

export interface DeployParams {
  owner: Address;
  cycleLength: bigint;
  tokenName: string;
  tokenSymbol: string;
  maxVotingPoints: bigint;
  salt: Hex;
}

/**
 * Deploy a full CrowdStake instance in one transaction via CrowdStakeDeployer,
 * then surface the resulting seven addresses (decoded from SystemDeployed).
 */
export function useDeployInstance() {
  const {
    writeContractAsync,
    data: hash,
    isPending: isSigning,
    reset,
    error: writeError,
  } = useWriteContract();
  const {
    data: receipt,
    isLoading: isConfirming,
    isSuccess,
    error: receiptError,
  } = useWaitForTransactionReceipt({ hash });

  const instance = useMemo<InstanceAddresses | null>(() => {
    if (!receipt) return null;
    for (const log of receipt.logs) {
      try {
        const ev = decodeEventLog({
          abi: deployerAbi,
          data: log.data,
          topics: log.topics,
        });
        if (ev.eventName === "SystemDeployed" && "instance" in ev.args) {
          // The event tuple names + order differ from InstanceAddresses
          // (notably `registry` -> `recipientRegistry`), so map explicitly.
          const i = ev.args.instance as {
            cycleModule: Address;
            registry: Address;
            token: Address;
            votingPowerStrategy: Address;
            distributionManager: Address;
            distributionStrategy: Address;
            votingModule: Address;
          };
          return {
            token: i.token,
            distributionManager: i.distributionManager,
            cycleModule: i.cycleModule,
            votingModule: i.votingModule,
            recipientRegistry: i.registry,
            distributionStrategy: i.distributionStrategy,
            votingPowerStrategy: i.votingPowerStrategy,
          };
        }
      } catch {
        // not our event — keep scanning
      }
    }
    return null;
  }, [receipt]);

  const deploy = async (p: DeployParams) => {
    try {
      return await writeContractAsync({
        address: DEPLOYER,
        abi: deployerAbi,
        functionName: "deploy",
        args: [
          {
            owner: p.owner,
            cycleLength: p.cycleLength,
            tokenName: p.tokenName,
            tokenSymbol: p.tokenSymbol,
            maxVotingPoints: p.maxVotingPoints,
            salt: p.salt,
          },
        ],
      });
    } catch (e) {
      throw new Error(parseTxError(e));
    }
  };

  const status: "idle" | "signing" | "confirming" | "success" | "error" =
    writeError || receiptError
      ? "error"
      : isSuccess
        ? "success"
        : isConfirming
          ? "confirming"
          : isSigning
            ? "signing"
            : "idle";

  return {
    deploy,
    hash,
    instance,
    status,
    isBusy: isSigning || isConfirming,
    isSuccess,
    error: writeError
      ? parseTxError(writeError)
      : receiptError
        ? parseTxError(receiptError)
        : null,
    reset,
  };
}
