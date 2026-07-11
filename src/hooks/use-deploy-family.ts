"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { zeroAddress, type Address, type Hex } from "viem";
import { useAccount } from "wagmi";
import { deployerAbi } from "@/lib/abis";
import { CHAINS } from "@/lib/chains";
import { publicClientFor, type InstanceAddresses } from "@/lib/instance";
import { parseTxError } from "@/hooks/use-tx";
import { useWalletActions } from "@/components/wallet/wallet-actions";
import {
  familyIdForConfig,
  loadPendingFamily,
  savePendingFamily,
  clearPendingFamily,
  type PendingFamilyParams,
  type PendingFamilyRecord,
} from "@/lib/families";

/** Per-chain execution state in the deploy checklist. */
export type FamilyDeployState =
  | "idle"
  | "checking"
  | "signing"
  | "confirming"
  | "deployed"
  | "skipped"
  | "failed";

export interface FamilyDeployRow {
  chainId: number;
  state: FamilyDeployState;
  txHash?: Hex;
  instance?: InstanceAddresses;
  error?: string;
  /** Native balance for the deploy gas preflight (undefined until read). */
  balanceWei?: bigint;
}

/** Everything a chain's deploy() call needs, shared across the family run. */
export interface FamilyDeployConfig {
  creator: Address;
  owner: Address;
  tokenName: string;
  tokenSymbol: string;
  maxVotingPoints: bigint;
  registryKind: number;
  distributionKind: number;
  /** Democratic families only: the founding cohort (committed to the familyId). */
  initialRecipients: Address[];
  /** Democratic families only: seconds a proposal stays open. 0n for admin. */
  proposalExpiry: bigint;
  tokenImageURI: string;
  bannerImageURI: string;
  /** ONE duration; each chain's cycleLength derives from its block time. */
  cycleSeconds: number;
  /** Shared salt for the whole run (drives the familyId). */
  salt: Hex;
  /** The chains to deploy on (>= 1). */
  chainIds: number[];
  /** The family's canonical share-link chain. */
  primaryChainId: number;
}

/** Map an Instance tuple (deployer ABI order) to InstanceAddresses. */
function toInstanceAddresses(i: {
  cycleModule: Address;
  registry: Address;
  token: Address;
  votingPowerStrategy: Address;
  distributionManager: Address;
  distributionStrategy: Address;
  votingModule: Address;
}): InstanceAddresses {
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

/** cycleLength (blocks) for a chain from ONE duration in seconds. */
function cycleBlocksFor(chainId: number, cycleSeconds: number): bigint {
  const cfg = CHAINS[chainId];
  const bt = cfg?.blockTimeSeconds ?? 5;
  return BigInt(Math.max(1, Math.ceil(cycleSeconds / bt)));
}

function serializeParams(cfg: FamilyDeployConfig): PendingFamilyParams {
  return {
    creator: cfg.creator,
    owner: cfg.owner,
    cycleSeconds: cfg.cycleSeconds,
    tokenName: cfg.tokenName,
    tokenSymbol: cfg.tokenSymbol,
    maxVotingPoints: cfg.maxVotingPoints.toString(),
    registryKind: cfg.registryKind,
    distributionKind: cfg.distributionKind,
    initialRecipients: cfg.initialRecipients,
    proposalExpiry: cfg.proposalExpiry.toString(),
    tokenImageURI: cfg.tokenImageURI,
    bannerImageURI: cfg.bannerImageURI,
  };
}

/**
 * Multi-chain family deploy — a checklist, not a rigid pipeline. Each chain is
 * independently Deploy/Retry/Skip-able. On-chain discovery is the source of
 * truth (familyInstances); the crowdstake.pendingFamily.v1 record is written
 * BEFORE the first tx so a closed tab can resume, and receipts are awaited on
 * each chain's OWN viem client (never the wallet-chain receipt wait, which would
 * watch the wrong chain).
 */
export function useDeployFamily(config: FamilyDeployConfig | null) {
  const { address } = useAccount();
  // Writes go through the wallet-actions layer: gas-sponsored (gasless, chain
  // targeted per call) on a Privy embedded wallet, else a self-paid write that
  // chain-switches itself — so no explicit switch here.
  const { sendSponsored } = useWalletActions();

  const familyId: Hex | null = config
    ? familyIdForConfig({
        creator: config.creator,
        salt: config.salt,
        tokenName: config.tokenName,
        tokenSymbol: config.tokenSymbol,
        maxVotingPoints: config.maxVotingPoints,
        registryKind: config.registryKind,
        distributionKind: config.distributionKind,
        initialRecipients: config.initialRecipients,
        proposalExpiry: config.proposalExpiry,
      })
    : null;

  const [rows, setRowsState] = useState<FamilyDeployRow[]>([]);
  const rowsRef = useRef<FamilyDeployRow[]>([]);
  const configRef = useRef<FamilyDeployConfig | null>(config);
  configRef.current = config;

  const setRows = useCallback(
    (updater: (prev: FamilyDeployRow[]) => FamilyDeployRow[]) => {
      rowsRef.current = updater(rowsRef.current);
      setRowsState(rowsRef.current);
    },
    [],
  );

  const patchRow = useCallback(
    (chainId: number, patch: Partial<FamilyDeployRow>) => {
      setRows((prev) =>
        prev.map((r) => (r.chainId === chainId ? { ...r, ...patch } : r)),
      );
    },
    [setRows],
  );

  // Seed one idle row per selected chain whenever the config's chain set changes.
  const chainKey = config?.chainIds.join(",") ?? "";
  useEffect(() => {
    if (!config) {
      setRows(() => []);
      return;
    }
    setRows((prev) =>
      config.chainIds.map(
        (chainId) =>
          prev.find((r) => r.chainId === chainId) ?? {
            chainId,
            state: "idle" as FamilyDeployState,
          },
      ),
    );
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [chainKey, setRows]);

  // Preflight: read each selected chain's native balance for a gas warning.
  // Keyed on the chain SET + wallet only (not the whole config), so typing the
  // token name doesn't re-hit every RPC on each keystroke.
  useEffect(() => {
    const cfg = configRef.current;
    if (!cfg || !address) return;
    let cancelled = false;
    void Promise.all(
      cfg.chainIds.map(async (chainId) => {
        try {
          const balanceWei = await publicClientFor(chainId).getBalance({
            address,
          });
          if (!cancelled) patchRow(chainId, { balanceWei });
        } catch {
          /* balance is advisory — leave it unread */
        }
      }),
    );
    return () => {
      cancelled = true;
    };
  }, [chainKey, address, patchRow]);

  const persist = useCallback(() => {
    const cfg = configRef.current;
    if (!cfg || !familyId) return;
    const chains: PendingFamilyRecord["chains"] = {};
    for (const r of rowsRef.current) {
      const status =
        r.state === "deployed"
          ? "deployed"
          : r.state === "skipped"
            ? "skipped"
            : "pending";
      chains[String(r.chainId)] = { status, txHash: r.txHash };
    }
    savePendingFamily({
      familyId,
      salt: cfg.salt,
      primaryChainId: cfg.primaryChainId,
      params: serializeParams(cfg),
      chains,
    });
  }, [familyId]);

  /** Resolve an already-deployed sibling from a chain's pinned deployer. */
  const readSibling = useCallback(
    async (chainId: number): Promise<InstanceAddresses | null> => {
      const deployer = CHAINS[chainId]?.deployer;
      if (!deployer || !familyId) return null;
      const inst = await publicClientFor(chainId).readContract({
        address: deployer,
        abi: deployerAbi,
        functionName: "familyInstances",
        args: [familyId],
      });
      if (inst.votingModule === zeroAddress) return null;
      return toInstanceAddresses(inst);
    },
    [familyId],
  );

  /** Deploy (or resume) one chain. Independent + retryable per row. */
  const deployChain = useCallback(
    async (chainId: number) => {
      const cfg = configRef.current;
      const deployer = CHAINS[chainId]?.deployer;
      if (!cfg || !familyId || !deployer) return;

      // Write the resume record BEFORE any tx so a closed tab can pick up here.
      persist();

      // Phantom-failure / resume safety: if the sibling already exists on-chain,
      // mark it deployed without re-submitting (a duplicate reverts anyway).
      patchRow(chainId, { state: "checking", error: undefined });
      try {
        const existing = await readSibling(chainId);
        if (existing) {
          patchRow(chainId, { state: "deployed", instance: existing });
          persist();
          return;
        }
      } catch {
        /* couldn't check — fall through and let the tx be the arbiter */
      }

      try {
        patchRow(chainId, { state: "signing" });
        const hash = await sendSponsored({
          chainId,
          address: deployer,
          abi: deployerAbi,
          functionName: "deploy",
          args: [
            {
              owner: cfg.owner,
              cycleLength: cycleBlocksFor(chainId, cfg.cycleSeconds),
              tokenName: cfg.tokenName,
              tokenSymbol: cfg.tokenSymbol,
              maxVotingPoints: cfg.maxVotingPoints,
              salt: cfg.salt,
              registryKind: cfg.registryKind,
              initialRecipients: cfg.initialRecipients,
              proposalExpiry: cfg.proposalExpiry,
              distributionKind: cfg.distributionKind,
              tokenImageURI: cfg.tokenImageURI,
              bannerImageURI: cfg.bannerImageURI,
              crossChain: true,
            },
          ],
        });
        patchRow(chainId, { state: "confirming", txHash: hash });
        persist();
        // Wait on THIS chain's client — the wallet may have moved on already.
        await publicClientFor(chainId).waitForTransactionReceipt({ hash });
        // Discovery is truth: read the wired sibling back rather than decode logs.
        const instance = (await readSibling(chainId)) ?? undefined;
        patchRow(chainId, { state: "deployed", instance });
        persist();
      } catch (e) {
        patchRow(chainId, { state: "failed", error: parseTxError(e) });
        persist();
      }
    },
    [familyId, persist, patchRow, readSibling, sendSponsored],
  );

  /** Skip a chain for now (leaves the family resumable from the Deploy page). */
  const skipChain = useCallback(
    (chainId: number) => {
      patchRow(chainId, { state: "skipped", error: undefined });
      persist();
    },
    [patchRow, persist],
  );

  /** Un-skip a skipped chain back to idle. */
  const unskipChain = useCallback(
    (chainId: number) => {
      patchRow(chainId, { state: "idle", error: undefined });
      persist();
    },
    [patchRow, persist],
  );

  /** Deploy every not-yet-deployed, not-skipped chain in sequence. */
  const deployAll = useCallback(async () => {
    const cfg = configRef.current;
    if (!cfg) return;
    for (const chainId of cfg.chainIds) {
      const row = rowsRef.current.find((r) => r.chainId === chainId);
      if (row && (row.state === "deployed" || row.state === "skipped"))
        continue;
      await deployChain(chainId);
    }
  }, [deployChain]);

  const deployedRows = rows.filter((r) => r.state === "deployed");
  const done =
    rows.length > 0 &&
    rows.every((r) => r.state === "deployed" || r.state === "skipped");
  const anyBusy = rows.some(
    (r) =>
      r.state === "checking" ||
      r.state === "signing" ||
      r.state === "confirming",
  );

  const finish = useCallback(() => {
    clearPendingFamily();
  }, []);

  return {
    familyId,
    rows,
    deployChain,
    deployAll,
    skipChain,
    unskipChain,
    /** Clear the resume record once the creator dismisses the finished run. */
    finish,
    /** Deployed siblings so far (for the family success card). */
    deployedRows,
    /** All chains are deployed or skipped. */
    done,
    /** A deploy is in flight on some chain. */
    anyBusy,
    /** Deployed on K of N selected chains. */
    deployedCount: deployedRows.length,
    chainCount: rows.length,
  };
}

/** Read the resume record (params + progress) for the Deploy page's resume card. */
export function usePendingFamily(): PendingFamilyRecord | null {
  const [record, setRecord] = useState<PendingFamilyRecord | null>(null);
  useEffect(() => {
    setRecord(loadPendingFamily());
  }, []);
  return record;
}
