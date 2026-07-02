import {
  createPublicClient,
  getAddress,
  http,
  isAddress,
  type Address,
} from "viem";
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

/**
 * URL query key that pins the active instance, e.g. `/app/?i=0x…`. It makes
 * every deployed instance a standalone, shareable link: open it and the app
 * resolves + activates that instance, even if you've never seen it before.
 */
export const INSTANCE_PARAM = "i";

/** Read a valid distribution-manager address out of a URL query string. */
export function instanceParam(search: string): Address | null {
  try {
    const raw = new URLSearchParams(search).get(INSTANCE_PARAM);
    return raw && isAddress(raw) ? (getAddress(raw) as Address) : null;
  } catch {
    return null;
  }
}

/**
 * Absolute, shareable link that opens the app pointed at a specific instance.
 * Includes the deploy-time base path (e.g. `/crowdstake.fun` on GitHub Pages),
 * so the link works verbatim on whatever host the app is served from.
 */
export function instanceShareUrl(distributionManager: Address): string {
  const base = process.env.NEXT_PUBLIC_BASE_PATH || "";
  const origin = typeof window !== "undefined" ? window.location.origin : "";
  return `${origin}${base}/app/?${INSTANCE_PARAM}=${distributionManager}`;
}

/**
 * Censorship-resistant eth.limo link for an instance — the app served from IPFS
 * via an ENS `contenthash`, addressed by the instance's distribution manager.
 * Returns null unless a NEXT_PUBLIC_ENS_HOST (e.g. "crowdstake.eth") is set at
 * build time, so the GitHub Pages build simply omits it.
 */
export function instanceEthLimoUrl(
  distributionManager: Address,
): string | null {
  const host = process.env.NEXT_PUBLIC_ENS_HOST;
  if (!host) return null;
  return `https://${host}.limo/app/?${INSTANCE_PARAM}=${distributionManager}`;
}

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
  const vpStrategies = (await client.readContract({
    address: votingModule as Address,
    abi: votingModuleAbi,
    functionName: "getVotingPowerStrategies",
  })) as readonly Address[];
  if (vpStrategies.length === 0) {
    // No voting-power strategy means a half-wired/incompatible instance —
    // refuse rather than persist one whose vote page would silently break.
    throw new Error("Instance has no voting-power strategy");
  }
  return {
    distributionManager: getAddress(distributionManager),
    cycleModule: getAddress(cycleModule as Address),
    votingModule: getAddress(votingModule as Address),
    recipientRegistry: getAddress(recipientRegistry as Address),
    token: getAddress(token as Address),
    distributionStrategy: getAddress(strategy as Address),
    votingPowerStrategy: getAddress(vpStrategies[0]),
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
