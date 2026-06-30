import { createPublicClient, http, type Address } from "viem";
import { gnosis } from "viem/chains";
import { ADDRESSES, RPC_URL, TOKEN_SYMBOL } from "@/lib/constants";
import { distributionManagerAbi, votingModuleAbi } from "@/lib/abis";

/** The full set of contract addresses that make up one CrowdStake instance. */
export interface InstanceAddresses {
  token: Address;
  distributionManager: Address;
  cycleModule: Address;
  votingModule: Address;
  recipientRegistry: Address;
  distributionStrategy: Address;
  votingPowerStrategy: Address;
}

export interface KnownInstance {
  label: string;
  addresses: InstanceAddresses;
}

/** The instance deployed with the protocol (always available, can't be removed). */
export const DEFAULT_INSTANCE: KnownInstance = {
  label: `${TOKEN_SYMBOL} (default)`,
  addresses: ADDRESSES,
};

const STORAGE_KEY = "crowdstake.instances.v1";
const ACTIVE_KEY = "crowdstake.activeInstance.v1";

const client = createPublicClient({ chain: gnosis, transport: http(RPC_URL) });

/**
 * Resolve a full instance from just its distribution-manager address by reading
 * the wired references on-chain. Lets the dapp point at *any* deployed instance.
 */
export async function resolveInstance(
  distributionManager: Address,
): Promise<InstanceAddresses> {
  const base = {
    address: distributionManager,
    abi: distributionManagerAbi,
  } as const;
  const [cycleModule, votingModule, recipientRegistry, token, strategy] =
    await Promise.all([
      client.readContract({ ...base, functionName: "cycleManager" }),
      client.readContract({ ...base, functionName: "votingModule" }),
      client.readContract({ ...base, functionName: "recipientRegistry" }),
      client.readContract({ ...base, functionName: "baseToken" }),
      client.readContract({ ...base, functionName: "distributionStrategy" }),
    ]);
  const vpStrategies = await client.readContract({
    address: votingModule as Address,
    abi: votingModuleAbi,
    functionName: "getVotingPowerStrategies",
  });
  return {
    distributionManager,
    cycleModule: cycleModule as Address,
    votingModule: votingModule as Address,
    recipientRegistry: recipientRegistry as Address,
    token: token as Address,
    distributionStrategy: strategy as Address,
    votingPowerStrategy: (vpStrategies as readonly Address[])[0],
  };
}

/* --------------------------- localStorage helpers -------------------------- */

export function loadKnownInstances(): KnownInstance[] {
  if (typeof window === "undefined") return [DEFAULT_INSTANCE];
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    const saved: KnownInstance[] = raw ? JSON.parse(raw) : [];
    // Default first, then saved (deduped by distributionManager).
    const seen = new Set([
      DEFAULT_INSTANCE.addresses.distributionManager.toLowerCase(),
    ]);
    const merged = [DEFAULT_INSTANCE];
    for (const inst of saved) {
      const key = inst.addresses?.distributionManager?.toLowerCase();
      if (key && !seen.has(key)) {
        seen.add(key);
        merged.push(inst);
      }
    }
    return merged;
  } catch {
    return [DEFAULT_INSTANCE];
  }
}

export function saveKnownInstances(instances: KnownInstance[]): void {
  if (typeof window === "undefined") return;
  // Persist everything except the built-in default.
  const custom = instances.filter(
    (i) =>
      i.addresses.distributionManager.toLowerCase() !==
      DEFAULT_INSTANCE.addresses.distributionManager.toLowerCase(),
  );
  window.localStorage.setItem(STORAGE_KEY, JSON.stringify(custom));
}

export function loadActiveManager(): Address | null {
  if (typeof window === "undefined") return null;
  return window.localStorage.getItem(ACTIVE_KEY) as Address | null;
}

export function saveActiveManager(distributionManager: Address): void {
  if (typeof window === "undefined") return;
  window.localStorage.setItem(ACTIVE_KEY, distributionManager);
}
