// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title GovernanceCallRegistryBase
/// @author BreadKit Protocol
/// @notice Shared plumbing for recipient-governed calls: a registry mixing this in can let its
///         recipients propose, vote on and execute an arbitrary call to another contract, reusing
///         the same propose/vote/execute shape already used for recipient changes.
/// @dev Deliberately standalone — no parents, no interface, and an EIP-7201 namespace of its own,
///      on the same principle as CrossChainRegistryBase. It therefore CANNOT read the host's
///      recipient set: the host reads it and passes the electorate in as a parameter, the same way
///      the cross-chain path already passes a signed electorate.
abstract contract GovernanceCallRegistryBase {
    /// @notice A proposal to perform `callData` on `target`, decided by the recipients
    /// @dev Electorate and threshold are snapshotted at creation, mirroring the classic recipient
    ///      proposals: later changes to the recipient set must not move the goalposts of a vote
    ///      already under way.
    struct GovernanceCallProposal {
        /// @notice The contract the call is aimed at — may be the host registry itself
        address target;
        /// @notice ABI-encoded call performed on `target` once the proposal passes
        bytes callData;
        /// @notice Absolute Unix timestamp after which the proposal can no longer be acted on
        /// @dev Absolute rather than derived from the host's current setting: the expiry is read
        ///      once, at creation, so changing it later cannot shorten or extend an open proposal.
        uint256 expiresAt;
        /// @notice Votes received so far
        uint256 voteCount;
        /// @notice Votes needed to pass, snapshotted at creation
        uint256 requiredVotes;
        /// @notice Whether the proposal has been executed — prevents double execution
        bool executed;
        /// @notice Whether an address has already voted on this proposal
        mapping(address => bool) hasVoted;
        /// @notice Whether an address was in the electorate snapshotted at creation
        mapping(address => bool) isEligibleVoter;
    }

    /// @custom:storage-location erc7201:crowdstake.storage.GovernanceCallRegistryBase
    struct GovernanceCallRegistryBaseStorage {
        /// @notice Id assigned to the next proposal, monotonic
        uint256 proposalCount;
        /// @notice Every governance-call proposal, by id
        mapping(uint256 => GovernanceCallProposal) proposals;
    }

    // keccak256(abi.encode(uint256(keccak256("crowdstake.storage.GovernanceCallRegistryBase")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant GOVERNANCE_CALL_REGISTRY_BASE_STORAGE =
        0x2cbccaf3fc8f64d45f9c4470c725695a246b8f36c5b9c55dfd91f0124fead900;

    function _getGovernanceCallRegistryBaseStorage()
        internal
        pure
        returns (GovernanceCallRegistryBaseStorage storage $)
    {
        assembly {
            $.slot := GOVERNANCE_CALL_REGISTRY_BASE_STORAGE
        }
    }

    // ============ Events ============

    /// @notice Emitted when a new governance-call proposal is created
    event GovernanceCallProposed(uint256 indexed proposalId, address indexed target, bytes callData);

    /// @notice Emitted when a recipient votes on a governance-call proposal
    event GovernanceCallVoteCast(uint256 indexed proposalId, address indexed voter);

    /// @notice Emitted once a governance-call proposal's target call has been performed
    event GovernanceCallExecuted(uint256 indexed proposalId);

    // ============ Errors ============

    /// @dev All names are prefixed `GovernanceCall` — a host mixing this in (VotingRecipientRegistry)
    ///      already declares NotARecipient/ProposalNotFound/AlreadyVoted/etc. for the classic recipient
    ///      flow, and Solidity does not allow two identically-named errors in one inheritance chain.

    /// @notice Thrown when proposing a governance-call with the zero address as target
    /// @dev Guarded at creation so the zero address stays free to mean "no such proposal" (see
    ///      GovernanceCallNotFound) — the same sentinel trick the classic path uses for `candidate`.
    error GovernanceCallInvalidTarget();

    /// @notice Thrown when `proposalId` does not correspond to a created proposal
    error GovernanceCallNotFound();

    /// @notice Thrown when the caller already voted on this proposal
    error GovernanceCallAlreadyVoted();

    /// @notice Thrown when acting on a proposal that has already been executed
    error GovernanceCallAlreadyExecuted();

    /// @notice Thrown when acting on a proposal past its snapshotted `expiresAt`
    error GovernanceCallExpired();

    /// @notice Thrown when the caller was not part of the electorate snapshotted at creation
    error GovernanceCallNotEligibleVoter();

    /// @notice Thrown when executing a proposal that has not reached `requiredVotes`
    /// @dev Also covers `requiredVotes == 0`, defense in depth mirroring the classic path's guard —
    ///      an empty electorate should never be able to "execute" for free.
    error GovernanceCallInsufficientVotes();
}
