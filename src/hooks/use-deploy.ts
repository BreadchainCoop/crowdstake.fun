"use client";

import { useMemo } from "react";
import { decodeEventLog, type Address, type Hex } from "viem";
import {
  useChainId,
  useWaitForTransactionReceipt,
  useWriteContract,
} from "wagmi";
import { deployerAbi } from "@/lib/abis";
import { CHAINS } from "@/lib/chains";
import { parseTxError } from "@/hooks/use-tx";
import type { InstanceAddresses } from "@/lib/instance";

export interface DeployParams {
  owner: Address;
  cycleLength: bigint;
  tokenName: string;
  tokenSymbol: string;
  maxVotingPoints: bigint;
  salt: Hex;
  // 0 = admin registry, 1 = democratic (recipient-voted).
  registryKind?: number;
  initialRecipients?: Address[];
  proposalExpiry?: bigint;
  // 0 = proportional (votes), 1 = equal, 2 = split (half votes / half equal).
  distributionKind?: number;
  // Instance artwork (off-chain URIs). Empty string = none.
  tokenImageURI?: string;
  bannerImageURI?: string;
}

/**
 * Deploy a full CrowdStake instance in one transaction via CrowdStakeDeployer,
 * then surface the resulting instance addresses (decoded from SystemDeployed).
 */
export function useDeployInstance() {
  // Deploying is a write on the wallet's CURRENT chain — use ITS deployer.
  // Look the chain up directly (NOT chainConfig, which falls back to the
  // default chain): on an unsupported chain we must have no deployer so the
  // tx isn't sent to the default-chain deployer address, and canDeploy is false.
  const chainId = useChainId();
  const cfg = CHAINS[chainId];
  const deployer = cfg?.deployer ?? null;
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
  } = useWaitForTransactionReceipt({ hash, chainId });

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
            secondaryDistributionStrategy: Address;
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
    if (!deployer) {
      throw new Error(
        `${cfg?.chain.name ?? `chain ${chainId}`} isn't supported for deploys yet — switch to a supported chain.`,
      );
    }
    try {
      return await writeContractAsync({
        chainId,
        address: deployer,
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
            registryKind: p.registryKind ?? 0,
            initialRecipients: p.initialRecipients ?? [],
            proposalExpiry: p.proposalExpiry ?? 0n,
            distributionKind: p.distributionKind ?? 0,
            tokenImageURI: p.tokenImageURI ?? "",
            bannerImageURI: p.bannerImageURI ?? "",
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
    /** The chain the instance is being deployed on (the wallet's chain). */
    chainId,
    /** Whether this chain has a deployer (else deploys are unavailable). */
    canDeploy: Boolean(deployer),
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
