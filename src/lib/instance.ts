import {
  AbiDecodingZeroDataError,
  BaseError,
  ContractFunctionRevertedError,
  ContractFunctionZeroDataError,
  createPublicClient,
  getAddress,
  http,
  isAddress,
  type Address,
  type Hex,
  type PublicClient,
} from "viem";
import {
  CHAINS,
  DEFAULT_CHAIN_ID,
  chainConfig,
  type InstanceAddresses,
} from "@/lib/chains";
import { TOKEN_SYMBOL } from "@/lib/constants";
import { distributionManagerAbi, tokenAbi, votingModuleAbi } from "@/lib/abis";

export type { InstanceAddresses } from "@/lib/chains";

/** A known instance: its addresses plus the chain it lives on. */
export interface KnownInstance {
  label: string;
  chainId: number;
  addresses: InstanceAddresses;
  /** Family membership (multi-chain instances) — absent on classic instances. */
  familyId?: Hex;
  /** The family's canonical share-link chain (defaults to this instance's). */
  primaryChainId?: number;
}

/** The instance deployed with the protocol (always available, can't be removed). */
export const DEFAULT_INSTANCE: KnownInstance = {
  label: `${TOKEN_SYMBOL} (default)`,
  chainId: DEFAULT_CHAIN_ID,
  addresses: chainConfig(DEFAULT_CHAIN_ID).defaultInstance as InstanceAddresses,
};

const STORAGE_KEY = "crowdstake.instances.v1";
const ACTIVE_KEY = "crowdstake.activeInstance.v1";

/**
 * URL query keys that pin the active instance, e.g. `/app/?i=0x…&c=100`. This
 * makes every deployed instance a standalone, shareable link: open it and the
 * app resolves + activates that instance (on chain `c`), even if unseen before.
 */
export const INSTANCE_PARAM = "i";
export const CHAIN_PARAM = "c";

/** Read a valid distribution-manager address out of a URL query string. */
export function instanceParam(search: string): Address | null {
  try {
    const raw = new URLSearchParams(search).get(INSTANCE_PARAM);
    return raw && isAddress(raw) ? (getAddress(raw) as Address) : null;
  } catch {
    return null;
  }
}

/** Read a supported chain id out of a URL query string, if present. */
export function chainParam(search: string): number | null {
  try {
    const raw = new URLSearchParams(search).get(CHAIN_PARAM);
    const id = raw ? Number(raw) : NaN;
    return Number.isInteger(id) && id in CHAINS ? id : null;
  } catch {
    return null;
  }
}

/**
 * Absolute, shareable link that opens the app pointed at a specific instance.
 * Includes the deploy-time base path and the chain id (omitted for the default
 * chain, keeping Gnosis links clean).
 */
export function instanceShareUrl(
  distributionManager: Address,
  chainId: number = DEFAULT_CHAIN_ID,
): string {
  const base = process.env.NEXT_PUBLIC_BASE_PATH || "";
  const origin = typeof window !== "undefined" ? window.location.origin : "";
  const chain =
    chainId === DEFAULT_CHAIN_ID ? "" : `&${CHAIN_PARAM}=${chainId}`;
  return `${origin}${base}/app/?${INSTANCE_PARAM}=${distributionManager}${chain}`;
}

// One read-only public client per chain, created lazily.
const clients = new Map<number, PublicClient>();

/** Read-only viem client pinned to a chain — shared by every cross-chain read. */
export function publicClientFor(chainId: number): PublicClient {
  let c = clients.get(chainId);
  if (!c) {
    const cfg = chainConfig(chainId);
    c = createPublicClient({ chain: cfg.chain, transport: http(cfg.rpcUrl) });
    clients.set(chainId, c);
  }
  return c;
}

/**
 * Resolve a full instance from just its distribution-manager address by reading
 * the wired references on-chain. Lets the dapp point at *any* deployed instance
 * on any supported chain.
 */
export async function resolveInstance(
  distributionManager: Address,
  chainId: number = DEFAULT_CHAIN_ID,
): Promise<InstanceAddresses> {
  const client = publicClientFor(chainId);
  const base = {
    address: distributionManager,
    abi: distributionManagerAbi,
  } as const;
  const [
    cycleModule,
    votingModule,
    recipientRegistry,
    baseToken,
    strategy,
    yieldModule,
  ] = await Promise.all([
    client.readContract({ ...base, functionName: "cycleManager" }),
    client.readContract({ ...base, functionName: "votingModule" }),
    client.readContract({ ...base, functionName: "recipientRegistry" }),
    client.readContract({ ...base, functionName: "baseToken" }),
    client.readContract({ ...base, functionName: "distributionStrategy" }),
    // The instance's token slot is the DM's YIELD MODULE, not its baseToken:
    // on a pool instance baseToken is the UNDERLYING asset the DM pays out
    // (WXDAI/USDC) while yieldModule is the StakePool — resolving baseToken
    // here would hand ?i= visitors WXDAI as the "community token". On token
    // instances yieldModule defaults to the token itself (verified against the
    // live v1 DM), so it's correct universally. Fall back to baseToken ONLY
    // when the getter is genuinely absent (a pre-yield-module DM: revert or
    // empty return data) — a TRANSIENT failure must rethrow and abort the
    // whole resolution instead: callers don't persist on a throw, whereas a
    // silent baseToken fallback would save a pool instance as its underlying
    // (WXDAI) in localStorage, where it is never re-resolved.
    client
      .readContract({ ...base, functionName: "yieldModule" })
      .catch((error) => {
        if (
          error instanceof BaseError &&
          error.walk(
            (e) =>
              e instanceof ContractFunctionRevertedError ||
              e instanceof ContractFunctionZeroDataError ||
              e instanceof AbiDecodingZeroDataError,
          ) !== null
        ) {
          return null; // getter missing — legacy DM, baseToken IS the token
        }
        throw error; // transport/RPC failure — fail the resolution wholesale
      }),
  ]);
  const zero = "0x0000000000000000000000000000000000000000";
  const token = (
    yieldModule && (yieldModule as Address).toLowerCase() !== zero
      ? yieldModule
      : baseToken
  ) as Address;
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

/**
 * Human label for a resolved instance: its token's on-chain name. Null when
 * the token has no usable name (fail-soft — callers fall back to a shortened
 * address).
 */
export async function resolveInstanceLabel(
  token: Address,
  chainId: number,
): Promise<string | null> {
  try {
    const name = (await publicClientFor(chainId).readContract({
      address: token,
      abi: tokenAbi,
      functionName: "name",
    })) as string;
    return name.trim() || null;
  } catch {
    return null;
  }
}

/* --------------------------- localStorage helpers -------------------------- */

const defaultDm = () =>
  DEFAULT_INSTANCE.addresses.distributionManager.toLowerCase();

export function loadKnownInstances(): KnownInstance[] {
  if (typeof window === "undefined") return [DEFAULT_INSTANCE];
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    const saved: KnownInstance[] = raw ? JSON.parse(raw) : [];
    const seen = new Set([defaultDm()]);
    const merged = [DEFAULT_INSTANCE];
    for (const inst of saved) {
      const key = inst.addresses?.distributionManager?.toLowerCase();
      // Older saves may lack chainId — default them to the home chain.
      if (key && !seen.has(key)) {
        seen.add(key);
        merged.push({ ...inst, chainId: inst.chainId ?? DEFAULT_CHAIN_ID });
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
    (i) => i.addresses.distributionManager.toLowerCase() !== defaultDm(),
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
