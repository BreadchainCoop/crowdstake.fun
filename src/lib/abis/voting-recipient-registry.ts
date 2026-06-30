import { parseAbi } from "viem";

/**
 * VotingRecipientRegistry — the democratic registry where current recipients
 * propose and vote to add/remove recipients (unanimous to add, n-1 to remove).
 * Includes the inherited registry reads/writes plus the proposal lifecycle, and
 * the full error set so reverts decode to readable names.
 */
export const votingRecipientRegistryAbi = parseAbi([
  // --- proposal reads ---
  "function proposalCount() view returns (uint256)",
  "function proposalExpiry() view returns (uint256)",
  "function getProposal(uint256 proposalId) view returns (address candidate, bool isAddition, uint256 voteCount, uint256 requiredVotes, bool executed, uint256 createdAt)",
  "function hasVoted(uint256 proposalId, address voter) view returns (bool)",
  "function isEligibleVoter(uint256 proposalId, address voter) view returns (bool)",
  "function isProposalExpired(uint256 proposalId) view returns (bool)",
  "function getRequiredVotes(uint256 proposalId) view returns (uint256)",
  // --- inherited registry reads ---
  "function getRecipients() view returns (address[])",
  "function getQueuedAdditions() view returns (address[])",
  "function getQueuedRemovals() view returns (address[])",
  "function isRecipient(address account) view returns (bool)",
  "function owner() view returns (address)",
  // --- proposal writes ---
  "function proposeAddition(address candidate) returns (uint256)",
  "function proposeRemoval(address candidate) returns (uint256)",
  "function vote(uint256 proposalId)",
  "function executeProposal(uint256 proposalId)",
  "function setProposalExpiry(uint256 newExpiry)",
  // --- inherited registry writes ---
  "function processQueue()",
  "function clearAdditionQueue()",
  "function clearRemovalQueue()",
  // --- events ---
  "event ProposalCreated(uint256 indexed proposalId, address indexed candidate, bool isAddition)",
  "event VoteCast(uint256 indexed proposalId, address indexed voter)",
  "event ProposalExecuted(uint256 indexed proposalId)",
  // --- errors (so parseTxError surfaces names) ---
  "error NotARecipient()",
  "error ProposalNotFound()",
  "error AlreadyVoted()",
  "error ProposalAlreadyExecuted()",
  "error ProposalExpired()",
  "error NotEnoughVotes()",
  "error NotEligibleVoter()",
  "error NoRecipients()",
  "error InvalidProposalExpiry()",
  "error InvalidRecipient()",
  "error RecipientAlreadyExists()",
  "error RecipientNotFound()",
  "error QueueNotSorted()",
  "error MaxQueueSizeReached()",
]);
