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

    // ============ Public Getters ============

    /// @dev All four getters below carry a `GovernanceCall` name, not the bare names the classic
    ///      path already uses (`proposals`, `proposalCount`, `hasVoted`, `isEligibleVoter`) —
    ///      same collision problem as the errors above, same fix. Mirrors the naming the project
    ///      already uses to disambiguate the cross-chain getters from the classic ones
    ///      (hasVotedCrossChain, isEligibleCrossChainVoter, crossChainProposalCount,
    ///      getCrossChainProposal).

    /// @notice Read a governance-call proposal by id
    /// @dev `hasVoted`/`isEligibleVoter` are mappings and can't be returned from a struct getter —
    ///      use the dedicated views below for those.
    /// @param proposalId The id of the proposal to read
    function getGovernanceCallProposal(uint256 proposalId)
        public
        view
        returns (
            address target,
            bytes memory callData,
            uint256 expiresAt,
            uint256 voteCount,
            uint256 requiredVotes,
            bool executed
        )
    {
        GovernanceCallProposal storage proposal = _getGovernanceCallRegistryBaseStorage().proposals[proposalId];
        return (
            proposal.target,
            proposal.callData,
            proposal.expiresAt,
            proposal.voteCount,
            proposal.requiredVotes,
            proposal.executed
        );
    }

    /// @notice Total number of governance-call proposals created (also the next proposal id)
    function governanceCallProposalCount() public view returns (uint256) {
        return _getGovernanceCallRegistryBaseStorage().proposalCount;
    }

    /// @notice Check if a specific address has voted on a governance-call proposal
    /// @dev Returns false for non-existent proposals or voters
    /// @param proposalId The id of the proposal to check
    /// @param voter The address to check voting status for
    function hasVotedGovernanceCall(uint256 proposalId, address voter) external view returns (bool hasVoted_) {
        return _getGovernanceCallRegistryBaseStorage().proposals[proposalId].hasVoted[voter];
    }

    /// @notice Check if an address was eligible to vote on a governance-call proposal
    /// @dev Eligibility is snapshotted at creation from the electorate the host passed in
    /// @param proposalId The id of the proposal to check
    /// @param voter The address to check eligibility for
    function isEligibleGovernanceCallVoter(uint256 proposalId, address voter) external view returns (bool isEligible) {
        return _getGovernanceCallRegistryBaseStorage().proposals[proposalId].isEligibleVoter[voter];
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

    // ============ Internal: propose ============

    /// @notice Create a governance-call proposal, casting the proposer's own vote for it
    /// @dev Mirrors VotingRecipientRegistry._propose + _createProposal, but this mixin cannot read
    ///      the host's recipient set (own EIP-7201 namespace) or its `msg.sender`-eligibility gate —
    ///      both are handled by the caller (VotingRecipientRegistry.proposeGovernanceCall) BEFORE
    ///      calling this:
    ///        - the host checks `base.isRecipientMapping[msg.sender]` and reverts its own
    ///          NotARecipient if the caller isn't a current recipient
    ///        - the host reads its own `proposalExpiry()` once and passes the already-computed
    ///          absolute `expiresAt` in
    ///      `msg.sender` here is still the original external caller — Solidity does not change it
    ///      across an internal call — so the auto-vote below credits the right address.
    /// @param target The contract the call is aimed at, may be the host itself
    /// @param callData ABI-encoded call to perform on `target` once the proposal passes
    /// @dev `calldata`, not `memory`: the only caller (VotingRecipientRegistry.proposeGovernanceCall)
    ///      already receives it as `calldata` from the external transaction, so passing it straight
    ///      through avoids an extra copy. Only possible because this internal function currently has
    ///      a single call site that is itself external — if a second caller needed to hand in an
    ///      already-in-memory bytes value, this would have to go back to `memory`.
    /// @param electorate The current recipient set, snapshotted as of this call
    /// @dev `electorate` stays `memory`, not `calldata` — unlike `callData` it never arrives via the
    ///      external transaction, the host builds it by copying its own `base.recipients` out of
    ///      storage, so `calldata` isn't an option here regardless of call-site shape.
    /// @param expiresAt Absolute Unix timestamp the proposal expires at, already computed by the host
    /// @return proposalId The id assigned to the new proposal
    function _proposeGovernanceCall(
        address target,
        bytes calldata callData,
        address[] memory electorate,
        uint256 expiresAt
    ) internal returns (uint256 proposalId) {
        if (target == address(0)) revert GovernanceCallInvalidTarget();

        GovernanceCallRegistryBaseStorage storage $ = _getGovernanceCallRegistryBaseStorage();
        proposalId = $.proposalCount++;
        GovernanceCallProposal storage proposal = $.proposals[proposalId];
        proposal.target = target;
        proposal.callData = callData;
        proposal.expiresAt = expiresAt;
        proposal.requiredVotes = electorate.length;

        // Snapshot eligible voters from the electorate handed in by the host — not re-derived here.
        for (uint256 i = 0; i < electorate.length; i++) {
            proposal.isEligibleVoter[electorate[i]] = true;
        }

        // Proposer automatically votes for their own proposal, same as the classic path.
        // Note: even if requiredVotes == 1 this does NOT auto-execute
        proposal.hasVoted[msg.sender] = true;
        proposal.voteCount = 1;

        emit GovernanceCallProposed(proposalId, target, callData);
        emit GovernanceCallVoteCast(proposalId, msg.sender);
    }
}
