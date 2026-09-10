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
}
