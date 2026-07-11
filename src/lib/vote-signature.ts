import {
  encodeAbiParameters,
  encodePacked,
  keccak256,
  type Address,
  type Hex,
} from "viem";

/**
 * The cross-chain vote's EIP-712 shape — pinned to the contracts' scheme
 * (AbstractVotingModule.crossChainDomainSeparator + CROSS_CHAIN_VOTE_TYPEHASH).
 * The domain is deliberately chainless: no chainId, no verifyingContract —
 * scoping comes from the familyId salt, which is what lets ONE signature land
 * on every sibling chain.
 *
 * The same chainless domain carries the three registry-governance kinds too
 * (registry-update, proposal, proposal-vote): distinct EIP-712 primary types
 * are the firewall between action kinds. Every TYPES const + payload builder
 * below mirrors relay/src/typed-data.ts and the contracts byte-for-byte —
 * pinned by the tracked relay/test/crosschain-vector.json parity assertion.
 */

/** Domain per family: EIP712Domain(string name,string version,bytes32 salt). */
export function crossChainVoteDomain(familyId: Hex) {
  return { name: "CrowdstakingVoting", version: "2", salt: familyId } as const;
}

export const CROSS_CHAIN_VOTE_TYPES = {
  CrossChainVote: [
    { name: "voter", type: "address" },
    { name: "points", type: "uint256[]" },
    { name: "recipients", type: "address[]" },
    { name: "nonce", type: "uint256" },
    { name: "deadline", type: "uint256" },
  ],
} as const;

/** A signed vote stays deliverable for 72 hours. */
export const DEFAULT_DEADLINE_MS = 72 * 60 * 60 * 1000;

/**
 * Next vote nonce: wall-clock ms, bumped past every chain's last-seen nonce so
 * the new signature supersedes the old vote on ALL siblings (nonces are
 * monotonic per chain — a lower nonce is dead on arrival).
 */
export function chooseNonce(lastNonces: bigint[]): bigint {
  const maxSeen = lastNonces.reduce((a, b) => (b > a ? b : a), 0n);
  const now = BigInt(Date.now());
  return now > maxSeen ? now : maxSeen + 1n;
}

/** Deadline in seconds (checked against block.timestamp on-chain). */
export function voteDeadline(nowMs: number = Date.now()): bigint {
  return BigInt(Math.floor((nowMs + DEFAULT_DEADLINE_MS) / 1000));
}

/**
 * The relay POST body (numbers as decimal strings — JSON has no bigint). Also
 * the "Copy signed vote" escape hatch: anyone holding this JSON can deliver
 * the vote via castCrossChainVote.
 */
export interface SignedVotePayload {
  familyId: Hex;
  voter: Address;
  points: string[];
  recipients: Address[];
  nonce: string;
  deadline: string;
  signature: Hex;
}

export function buildVotePayload(
  familyId: Hex,
  voter: Address,
  points: readonly bigint[],
  recipients: readonly Address[],
  nonce: bigint,
  deadline: bigint,
  signature: Hex,
): SignedVotePayload {
  return {
    familyId,
    voter,
    points: points.map((p) => p.toString()),
    recipients: [...recipients],
    nonce: nonce.toString(),
    deadline: deadline.toString(),
    signature,
  };
}

/* ─────────────────────── classic (single-chain) vote ─────────────────── */

/**
 * Classic single-chain vote signature — the recast path for non-family
 * instances. Unlike the chainless family domain above, this is the STANDARD
 * EIP712Upgradeable domain (name "CrowdstakingVoting", version "1", chainId,
 * verifyingContract = the voting module), so the signature is bound to one
 * module on one chain. Mirrors AbstractVotingModule.VOTE_TYPEHASH and its
 * validateSignature assembly byte-for-byte — the direct voteWithData path
 * reverts AlreadyVotedInCurrentCycle, but castVoteWithSignature only gates on
 * nonce uniqueness and _processVote reverts the previous ballot, so recasting
 * is designed in via this signature path.
 */
export function classicVoteDomain(chainId: number, votingModule: Address) {
  return {
    name: "CrowdstakingVoting",
    version: "1",
    chainId,
    verifyingContract: votingModule,
  } as const;
}

/** Mirrors VOTE_TYPEHASH = keccak256("Vote(address voter,bytes32 pointsHash,uint256 nonce)"). */
export const CLASSIC_VOTE_TYPES = {
  Vote: [
    { name: "voter", type: "address" },
    { name: "pointsHash", type: "bytes32" },
    { name: "nonce", type: "uint256" },
  ],
} as const;

/**
 * pointsHash = keccak256 of the tightly-packed 32-byte words of the points
 * array — the contract's validateSignature calldatacopies points.offset for
 * points.length * 0x20 bytes and hashes that (no length prefix, no ABI head),
 * which is exactly encodePacked over uint256[].
 */
export function classicPointsHash(points: readonly bigint[]): Hex {
  return keccak256(encodePacked(["uint256[]"], [[...points]]));
}

/* ─────────────────────────── registry-update ─────────────────────────── */

/**
 * Admin "desired set" registry update. The signed array is the FULL DESIRED
 * SET (strictly ascending, canonical) — each chain computes its own delta, so
 * one signature heals arbitrary drift. Mirrors AdminRecipientRegistry
 * .CROSS_CHAIN_REGISTRY_UPDATE_TYPEHASH.
 */
export const CROSS_CHAIN_REGISTRY_UPDATE_TYPES = {
  CrossChainRegistryUpdate: [
    { name: "admin", type: "address" },
    { name: "recipients", type: "address[]" },
    { name: "nonce", type: "uint256" },
    { name: "deadline", type: "uint256" },
  ],
} as const;

/** Sort recipients strictly ascending by uint160(address) — the signed canon. */
export function sortRecipientsAscending(
  recipients: readonly Address[],
): Address[] {
  return [...recipients].sort((a, b) =>
    BigInt(a) < BigInt(b) ? -1 : BigInt(a) > BigInt(b) ? 1 : 0,
  );
}

/** The relay POST body / copyable escape hatch for a registry update. */
export interface SignedRegistryUpdatePayload {
  kind: "registry-update";
  familyId: Hex;
  admin: Address;
  recipients: Address[];
  nonce: string;
  deadline: string;
  signature: Hex;
}

/**
 * Build the registry-update payload. `recipients` is sorted ascending here so
 * the caller can pass any order — the ascending set is what was signed.
 */
export function buildRegistryUpdatePayload(
  familyId: Hex,
  admin: Address,
  recipients: readonly Address[],
  nonce: bigint,
  deadline: bigint,
  signature: Hex,
): SignedRegistryUpdatePayload {
  return {
    kind: "registry-update",
    familyId,
    admin,
    recipients: sortRecipientsAscending(recipients),
    nonce: nonce.toString(),
    deadline: deadline.toString(),
    signature,
  };
}

/* ───────────────────────────── proposal ──────────────────────────────── */

/**
 * Democratic cross-chain proposal. The signed electorate replaces the local
 * snapshot; each chain validates set-equality vs its recipients. Mirrors
 * VotingRecipientRegistry.CROSS_CHAIN_PROPOSAL_TYPEHASH.
 */
export const CROSS_CHAIN_PROPOSAL_TYPES = {
  CrossChainProposal: [
    { name: "proposer", type: "address" },
    { name: "candidate", type: "address" },
    { name: "isAddition", type: "bool" },
    { name: "electorate", type: "address[]" },
    { name: "expiresAt", type: "uint256" },
    { name: "nonce", type: "uint256" },
  ],
} as const;

/** The typehash matching the contract's CROSS_CHAIN_PROPOSAL_TYPEHASH. */
export const CROSS_CHAIN_PROPOSAL_TYPEHASH = keccak256(
  encodePacked(
    ["string"],
    [
      "CrossChainProposal(address proposer,address candidate,bool isAddition,address[] electorate,uint256 expiresAt,uint256 nonce)",
    ],
  ),
);

export interface CrossChainProposalMessage {
  proposer: Address;
  candidate: Address;
  isAddition: boolean;
  electorate: readonly Address[];
  expiresAt: bigint;
  nonce: bigint;
}

/**
 * proposalKey = the EIP-712 struct hash itself (content-addressed,
 * chain-agnostic, so the same proposal exists under the same key everywhere).
 * Hand-rolled to reproduce the contract's
 *   keccak256(abi.encode(typehash, proposer, candidate, isAddition,
 *     keccak256(abi.encodePacked(electorate)), expiresAt, nonce))
 * EXACTLY — and to stay byte-identical to relay computeProposalKey. Pinned by
 * relay/test/crosschain-vector.json (proposal.proposalKey) — must reproduce it.
 */
export function computeProposalKey(message: CrossChainProposalMessage): Hex {
  const electorateHash = keccak256(
    encodePacked(["address[]"], [[...message.electorate]]),
  );
  return keccak256(
    encodeAbiParameters(
      [
        { type: "bytes32" },
        { type: "address" },
        { type: "address" },
        { type: "bool" },
        { type: "bytes32" },
        { type: "uint256" },
        { type: "uint256" },
      ],
      [
        CROSS_CHAIN_PROPOSAL_TYPEHASH,
        message.proposer,
        message.candidate,
        message.isAddition,
        electorateHash,
        message.expiresAt,
        message.nonce,
      ],
    ),
  );
}

/** The relay POST body / copyable escape hatch for a proposal. */
export interface SignedProposalPayload {
  kind: "proposal";
  familyId: Hex;
  proposer: Address;
  candidate: Address;
  isAddition: boolean;
  electorate: Address[];
  expiresAt: string;
  nonce: string;
  signature: Hex;
}

export function buildProposalPayload(
  familyId: Hex,
  message: CrossChainProposalMessage,
  signature: Hex,
): SignedProposalPayload {
  return {
    kind: "proposal",
    familyId,
    proposer: message.proposer,
    candidate: message.candidate,
    isAddition: message.isAddition,
    electorate: [...message.electorate],
    expiresAt: message.expiresAt.toString(),
    nonce: message.nonce.toString(),
    signature,
  };
}

/**
 * A proposal nonce that only distinguishes REPEAT proposals of identical
 * content (concurrent distinct proposals must NOT supersede each other — the
 * dedup is the proposalKey, not the nonce). Wall-clock ms is unique enough.
 */
export function proposalNonce(nowMs: number = Date.now()): bigint {
  return BigInt(nowMs);
}

/* ─────────────────────────── proposal-vote ───────────────────────────── */

/**
 * A vote on a democratic cross-chain proposal — NO nonce (per-chain replay is
 * blocked by hasVoted, cross-proposal by proposalKey, cross-family by the
 * domain salt). Mirrors VotingRecipientRegistry.CROSS_CHAIN_PROPOSAL_VOTE_TYPEHASH.
 */
export const CROSS_CHAIN_PROPOSAL_VOTE_TYPES = {
  CrossChainProposalVote: [
    { name: "voter", type: "address" },
    { name: "proposalKey", type: "bytes32" },
    { name: "deadline", type: "uint256" },
  ],
} as const;

/** The relay POST body / copyable escape hatch for a proposal vote. */
export interface SignedProposalVotePayload {
  kind: "proposal-vote";
  familyId: Hex;
  voter: Address;
  proposalKey: Hex;
  deadline: string;
  signature: Hex;
}

export function buildProposalVotePayload(
  familyId: Hex,
  voter: Address,
  proposalKey: Hex,
  deadline: bigint,
  signature: Hex,
): SignedProposalVotePayload {
  return {
    kind: "proposal-vote",
    familyId,
    voter,
    proposalKey,
    deadline: deadline.toString(),
    signature,
  };
}
