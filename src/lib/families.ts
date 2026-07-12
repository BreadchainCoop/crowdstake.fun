import {
  encodeAbiParameters,
  encodePacked,
  keccak256,
  toHex,
  zeroAddress,
  type Address,
  type Hex,
} from "viem";
import { CHAINS, type InstanceAddresses } from "@/lib/chains";
import { deployerAbi } from "@/lib/abis";
import { publicClientFor } from "@/lib/instance";

/**
 * Family identity + sibling resolution for multi-chain instances.
 *
 * A "family" is the same community deployed on several chains: one creator,
 * one salt, one config. Its id is derived exactly like the deployer's
 * `familyIdOf` (see contracts CrowdStakeDeployer v2) so the frontend can
 * compute it before any transaction and resolve siblings from each chain's
 * pinned deployer with a single `familyInstances(familyId)` eth_call.
 */

/** Protocol tag pinned in CrowdStakeDeployer.familyIdOf — never change. */
const FAMILY_TAG = keccak256(toHex("crowdstake.family.v2"));

/** Mirrors CrowdStakeDeployer.familyIdOf exactly (creator-scoped, config-committing). */
export function computeFamilyId(
  creator: Address,
  salt: Hex,
  tokenName: string,
  tokenSymbol: string,
  maxVotingPoints: bigint,
  registryKind: number,
  distributionKind: number,
): Hex {
  return keccak256(
    encodeAbiParameters(
      [
        { type: "bytes32" },
        { type: "address" },
        { type: "bytes32" },
        { type: "bytes32" },
        { type: "bytes32" },
        { type: "uint256" },
        { type: "uint8" },
        { type: "uint8" },
      ],
      [
        FAMILY_TAG,
        creator,
        salt,
        keccak256(toHex(tokenName)),
        keccak256(toHex(tokenSymbol)),
        maxVotingPoints,
        registryKind,
        distributionKind,
      ],
    ),
  );
}

/** The RegistryKind enum value for the democratic (Voting) registry. */
const REGISTRY_KIND_VOTING = 1;

/**
 * Mirrors CrowdStakeDeployer.votingFamilyIdOf exactly. A democratic (Voting)
 * cross-chain family MUST commit its founding cohort + expiry into the
 * familyId: same creator/salt with different founders on two chains would
 * otherwise mint one family with permanently drifted electorates and no heal
 * path. Folds the base familyIdOf (with registryKind=Voting) with
 * keccak256(abi.encodePacked(initialRecipients)) and proposalExpiry.
 */
export function computeVotingFamilyId(
  creator: Address,
  salt: Hex,
  tokenName: string,
  tokenSymbol: string,
  maxVotingPoints: bigint,
  distributionKind: number,
  initialRecipients: readonly Address[],
  proposalExpiry: bigint,
): Hex {
  const base = computeFamilyId(
    creator,
    salt,
    tokenName,
    tokenSymbol,
    maxVotingPoints,
    REGISTRY_KIND_VOTING,
    distributionKind,
  );
  return keccak256(
    encodeAbiParameters(
      [{ type: "bytes32" }, { type: "bytes32" }, { type: "uint256" }],
      [
        base,
        keccak256(encodePacked(["address[]"], [[...initialRecipients]])),
        proposalExpiry,
      ],
    ),
  );
}

/**
 * The familyId for a config, choosing the admin- or voting-kind derivation to
 * match CrowdStakeDeployer.deploy: Voting-kind cross-chain families commit
 * their founding cohort + expiry; admin-kind stays on the base familyIdOf.
 */
export function familyIdForConfig(cfg: {
  creator: Address;
  salt: Hex;
  tokenName: string;
  tokenSymbol: string;
  maxVotingPoints: bigint;
  registryKind: number;
  distributionKind: number;
  initialRecipients: readonly Address[];
  proposalExpiry: bigint;
}): Hex {
  if (cfg.registryKind === REGISTRY_KIND_VOTING) {
    return computeVotingFamilyId(
      cfg.creator,
      cfg.salt,
      cfg.tokenName,
      cfg.tokenSymbol,
      cfg.maxVotingPoints,
      cfg.distributionKind,
      cfg.initialRecipients,
      cfg.proposalExpiry,
    );
  }
  return computeFamilyId(
    cfg.creator,
    cfg.salt,
    cfg.tokenName,
    cfg.tokenSymbol,
    cfg.maxVotingPoints,
    cfg.registryKind,
    cfg.distributionKind,
  );
}

/** Chains a family can live on: every chain with a pinned deployer. */
export function familyChainIds(): number[] {
  return Object.keys(CHAINS)
    .map(Number)
    .filter((id) => CHAINS[id].deployable && CHAINS[id].deployer);
}

export type FamilySiblingStatus = "found" | "none" | "unreachable";

/** One chain's answer to "does this family live here?". */
export interface FamilySibling {
  chainId: number;
  status: FamilySiblingStatus;
  instance?: InstanceAddresses;
}

const RESOLVE_TIMEOUT_MS = 6_000;
const CACHE_TTL_MS = 10 * 60_000;
const cacheKey = (familyId: Hex) =>
  `crowdstake.family.v1.${familyId.toLowerCase()}`;

function withTimeout<T>(promise: Promise<T>, ms: number): Promise<T> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("timeout")), ms);
    promise.then(
      (v) => {
        clearTimeout(timer);
        resolve(v);
      },
      (e) => {
        clearTimeout(timer);
        reject(e);
      },
    );
  });
}

async function resolveSibling(
  familyId: Hex,
  chainId: number,
): Promise<FamilySibling> {
  const deployer = CHAINS[chainId].deployer;
  if (!deployer) return { chainId, status: "none" };
  try {
    const inst = await withTimeout(
      publicClientFor(chainId).readContract({
        address: deployer,
        abi: deployerAbi,
        functionName: "familyInstances",
        args: [familyId],
      }),
      RESOLVE_TIMEOUT_MS,
    );
    if (inst.votingModule === zeroAddress) return { chainId, status: "none" };
    return {
      chainId,
      status: "found",
      instance: {
        token: inst.token,
        distributionManager: inst.distributionManager,
        cycleModule: inst.cycleModule,
        votingModule: inst.votingModule,
        recipientRegistry: inst.registry,
        distributionStrategy: inst.distributionStrategy,
        votingPowerStrategy: inst.votingPowerStrategy,
      },
    };
  } catch {
    // NEVER silently drop a chain we couldn't ask — surface it for a Retry.
    return { chainId, status: "unreachable" };
  }
}

function loadCachedSiblings(familyId: Hex): FamilySibling[] | null {
  if (typeof window === "undefined") return null;
  try {
    const raw = window.localStorage.getItem(cacheKey(familyId));
    if (!raw) return null;
    const parsed = JSON.parse(raw) as { at: number; siblings: FamilySibling[] };
    if (Date.now() - parsed.at > CACHE_TTL_MS) return null;
    return parsed.siblings;
  } catch {
    return null;
  }
}

function cacheSiblings(familyId: Hex, siblings: FamilySibling[]): void {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(
      cacheKey(familyId),
      JSON.stringify({ at: Date.now(), siblings }),
    );
  } catch {
    /* quota/eviction — cache is only an optimization */
  }
}

async function fetchSiblings(familyId: Hex): Promise<FamilySibling[]> {
  const siblings = await Promise.all(
    familyChainIds().map((chainId) => resolveSibling(familyId, chainId)),
  );
  cacheSiblings(familyId, siblings);
  return siblings;
}

/**
 * Resolve the family's per-chain siblings (one deployer eth_call per chain,
 * 6s timeout each). Serves a fresh localStorage cache first (TTL ~10 min) and
 * revalidates in the background; `force` skips the cache (Retry buttons).
 */
export async function resolveFamily(
  familyId: Hex,
  opts?: { force?: boolean },
): Promise<FamilySibling[]> {
  if (!opts?.force) {
    const cached = loadCachedSiblings(familyId);
    if (cached) {
      void fetchSiblings(familyId).catch(() => {});
      return cached;
    }
  }
  return fetchSiblings(familyId);
}

/* ------------------------- pending family deploys ------------------------- */

export type PendingChainStatus = "pending" | "deployed" | "skipped";

/** Everything needed to re-issue `deploy()` with identical family params. */
export interface PendingFamilyParams {
  /** The wallet that ran (and must run) every deploy — familyId is creator-scoped. */
  creator: Address;
  owner: Address;
  /** ONE duration; per-chain cycleLength derives from each chain's block time. */
  cycleSeconds: number;
  tokenName: string;
  tokenSymbol: string;
  /** bigint as a decimal string (JSON-safe). */
  maxVotingPoints: string;
  registryKind: number;
  distributionKind: number;
  /** Democratic families only: the founding recipient cohort (committed to
   *  the familyId). Empty for admin families. */
  initialRecipients: Address[];
  /** Democratic families only: seconds a proposal stays open. "0" for admin. */
  proposalExpiry: string;
  tokenImageURI: string;
  bannerImageURI: string;
  /**
   * Issue a transferable ERC-20 (true) or pool mode (false). Optional because
   * records saved BEFORE pool mode existed all deployed tokens — readers must
   * treat a missing value as TRUE so resuming/extending an old family keeps
   * its mode (new deploys default to false = pool). Not part of the familyId:
   * cross-chain mode consistency is enforced by the deploy wizard's shared
   * config, not the id derivation.
   */
  issueToken?: boolean;
}

/**
 * A multi-chain deploy in flight, written BEFORE the first transaction so a
 * closed tab can always resume. On-chain `familyInstances` discovery is the
 * truth on resume — this record is only the hint (params + progress).
 */
export interface PendingFamilyRecord {
  familyId: Hex;
  salt: Hex;
  primaryChainId: number;
  params: PendingFamilyParams;
  chains: Record<string, { status: PendingChainStatus; txHash?: Hex }>;
}

const PENDING_KEY = "crowdstake.pendingFamily.v1";

export function loadPendingFamily(): PendingFamilyRecord | null {
  if (typeof window === "undefined") return null;
  try {
    const raw = window.localStorage.getItem(PENDING_KEY);
    return raw ? (JSON.parse(raw) as PendingFamilyRecord) : null;
  } catch {
    return null;
  }
}

export function savePendingFamily(record: PendingFamilyRecord): void {
  if (typeof window === "undefined") return;
  window.localStorage.setItem(PENDING_KEY, JSON.stringify(record));
  // Also keep a durable, per-family copy so "Add a chain" can prefill even
  // after the run finished and the pending record was cleared.
  saveFamilyDeployParams(record);
}

export function clearPendingFamily(): void {
  if (typeof window === "undefined") return;
  window.localStorage.removeItem(PENDING_KEY);
}

/* --------------------- durable per-family deploy params -------------------- */

/**
 * The deploy params for a family, keyed by familyId so extending it later
 * ("Add a chain") reuses the EXACT config/salt/creator — any drift changes the
 * deterministic familyId and mints an orphan. Written at deploy time and NOT
 * cleared when a run finishes (unlike the pending record).
 */
export interface FamilyDeployParamsRecord {
  familyId: Hex;
  salt: Hex;
  primaryChainId: number;
  params: PendingFamilyParams;
}

const familyParamsKey = (familyId: Hex) =>
  `crowdstake.familyParams.v1.${familyId.toLowerCase()}`;

export function saveFamilyDeployParams(record: FamilyDeployParamsRecord): void {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(
      familyParamsKey(record.familyId),
      JSON.stringify({
        familyId: record.familyId,
        salt: record.salt,
        primaryChainId: record.primaryChainId,
        params: record.params,
      }),
    );
  } catch {
    /* quota/eviction — prefill is a convenience, not a correctness requirement */
  }
}

export function loadFamilyDeployParams(
  familyId: Hex,
): FamilyDeployParamsRecord | null {
  if (typeof window === "undefined") return null;
  try {
    const raw = window.localStorage.getItem(familyParamsKey(familyId));
    return raw ? (JSON.parse(raw) as FamilyDeployParamsRecord) : null;
  } catch {
    return null;
  }
}
