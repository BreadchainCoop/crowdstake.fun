"use client";

import { useCallback, useMemo, useState } from "react";
import { decodeEventLog, type Address, type Hex, type Log } from "viem";
import { useChainId, useWaitForTransactionReceipt } from "wagmi";
import { deployerAbi } from "@/lib/abis";
import { CHAINS } from "@/lib/chains";
import { parseTxError } from "@/hooks/use-tx";
import { useWalletActions } from "@/components/wallet/wallet-actions";
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
  // Multi-chain family instance (see lib/families.ts). Default false = classic.
  crossChain?: boolean;
  // Issue a transferable ERC-20? Default FALSE = pool mode (a StakePool sits
  // at the instance's token slot — deposits tracked, no token minted).
  issueToken?: boolean;
}

/** Decode the deployed instance out of a receipt's SystemDeployed event. */
export function decodeInstanceFromLogs(
  logs: readonly Log[],
): InstanceAddresses | null {
  for (const log of logs) {
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
  // Deploys go through the wallet-actions layer like every other write: gas-
  // sponsored (gasless) on a Privy embedded wallet — which holds no native
  // token, so a raw self-paid write could never even estimate — else a normal
  // self-paid wallet tx.
  const { sendSponsored } = useWalletActions();
  const [hash, setHash] = useState<Hex | undefined>(undefined);
  const [isSigning, setIsSigning] = useState(false);
  const [submitError, setSubmitError] = useState<string | null>(null);
  const {
    data: receipt,
    isLoading: isConfirming,
    isSuccess,
    error: receiptError,
  } = useWaitForTransactionReceipt({ hash, chainId });

  const reset = useCallback(() => {
    setHash(undefined);
    setIsSigning(false);
    setSubmitError(null);
  }, []);

  const instance = useMemo<InstanceAddresses | null>(
    () => (receipt ? decodeInstanceFromLogs(receipt.logs) : null),
    [receipt],
  );

  const deploy = async (p: DeployParams) => {
    if (!deployer) {
      throw new Error(
        `${cfg?.chain.name ?? `chain ${chainId}`} isn't supported for deploys yet — switch to a supported chain.`,
      );
    }
    setSubmitError(null);
    setHash(undefined);
    setIsSigning(true);
    try {
      const h = await sendSponsored({
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
            crossChain: p.crossChain ?? false,
            // Default FALSE = pool mode (no token issued) — the struct's
            // zero value, matching the contract's own default.
            issueToken: p.issueToken ?? false,
          },
        ],
      });
      setHash(h);
      return h;
    } catch (e) {
      const message = parseTxError(e);
      setSubmitError(message);
      throw new Error(message);
    } finally {
      setIsSigning(false);
    }
  };

  const status: "idle" | "signing" | "confirming" | "success" | "error" =
    submitError || receiptError
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
    error: submitError ?? (receiptError ? parseTxError(receiptError) : null),
    reset,
  };
}
