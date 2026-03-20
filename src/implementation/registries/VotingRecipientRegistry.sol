// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AbstractRecipientRegistry} from "../../abstract/AbstractRecipientRegistry.sol";

/// @title VotingRecipientRegistry
/// @notice Democratic registry where all current recipients must vote to add new recipients
/// @dev Requires 100% unanimous consent from all current recipients to add new ones
/// @dev Proposals expire after 7 days if not executed
/// @author BreadKit Protocol
contract VotingRecipientRegistry is AbstractRecipientRegistry {
    /// @notice Structure containing all information about a proposal
    struct Proposal {
        /// @notice The address being proposed for addition or removal
        address candidate;
        /// @notice True if this is an addition proposal, false for removal
        bool isAddition;
        /// @notice Current number of votes received for this proposal
        uint256 voteCount;
        /// @notice Mapping of addresses to whether they have voted on this proposal
        mapping(address => bool) hasVoted;
        /// @notice Whether this proposal has been executed (prevents double execution)
        bool executed;
        /// @notice Timestamp when this proposal was created (for expiry calculation)
        uint256 createdAt;
    }

    // ============ EIP-7201 Namespaced Storage ============

    /// @custom:storage-location erc7201:crowdstake.storage.VotingRecipientRegistry
    struct VotingRecipientRegistryStorage {
        /// @notice Mapping from proposal ID to proposal data
        mapping(uint256 => Proposal) proposals;
        /// @notice Total number of proposals created (also serves as next proposal ID)
        uint256 proposalCount;
        /// @notice Time limit for proposals before they expire
        uint256 proposalExpiry;
    }

    // keccak256(abi.encode(uint256(keccak256("crowdstake.storage.VotingRecipientRegistry")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant VOTING_RECIPIENT_REGISTRY_STORAGE =
        0xd1130eee9b149c4593e65f48b107ed420660e6ad58daa79da60d56a941d9d900;

    function _getVotingRecipientRegistryStorage()
        private
        pure
        returns (VotingRecipientRegistryStorage storage $)
    {
        assembly {
            $.slot := VOTING_RECIPIENT_REGISTRY_STORAGE
        }
    }

    // ============ Public Getters ============

    function proposals(uint256 proposalId)
        public
        view
        returns (address candidate, bool isAddition, uint256 voteCount, bool executed, uint256 createdAt)
    {
        Proposal storage proposal = _getVotingRecipientRegistryStorage().proposals[proposalId];
        return (proposal.candidate, proposal.isAddition, proposal.voteCount, proposal.executed, proposal.createdAt);
    }

    function proposalCount() public view returns (uint256) {
        return _getVotingRecipientRegistryStorage().proposalCount;
    }

    function proposalExpiry() public view returns (uint256) {
        return _getVotingRecipientRegistryStorage().proposalExpiry;
    }

    // ============ Events ============

    event ProposalCreated(uint256 indexed proposalId, address indexed candidate, bool isAddition);
    event VoteCast(uint256 indexed proposalId, address indexed voter);
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalExpiredEvent(uint256 indexed proposalId);
    event ProposalExpiryUpdated(uint256 oldExpiry, uint256 newExpiry);

    // ============ Errors ============

    error NotARecipient();
    error ProposalNotFound();
    error AlreadyVoted();
    error ProposalAlreadyExecuted();
    error ProposalExpired();
    error NotEnoughVotes();
    error NoRecipients();
    error InvalidProposalExpiry();

    // ============ Initialization ============

    /// @notice Initialize the registry with a set of initial recipients
    function initialize(address admin, address[] memory initialRecipients, uint256 _proposalExpiry) public initializer {
        __Ownable_init(admin);

        if (initialRecipients.length == 0) revert NoRecipients();
        if (_proposalExpiry == 0) revert InvalidProposalExpiry();

        VotingRecipientRegistryStorage storage $ = _getVotingRecipientRegistryStorage();
        $.proposalExpiry = _proposalExpiry;

        AbstractRecipientRegistryStorage storage base = _getAbstractRecipientRegistryStorage();
        for (uint256 i = 0; i < initialRecipients.length; i++) {
            address recipient = initialRecipients[i];
            if (recipient == address(0)) revert InvalidRecipient();
            if (base.isRecipientMapping[recipient]) revert RecipientAlreadyExists();

            base.recipients.push(recipient);
            base.isRecipientMapping[recipient] = true;
            emit RecipientAdded(recipient);
        }
    }

    /// @notice Update the proposal expiry duration
    function setProposalExpiry(uint256 newExpiry) external onlyOwner {
        if (newExpiry == 0) revert InvalidProposalExpiry();

        VotingRecipientRegistryStorage storage $ = _getVotingRecipientRegistryStorage();
        uint256 oldExpiry = $.proposalExpiry;
        $.proposalExpiry = newExpiry;

        emit ProposalExpiryUpdated(oldExpiry, newExpiry);
    }

    /// @notice Queue a recipient for addition through the voting process
    function queueRecipientAddition(address recipient) external {
        proposeAddition(recipient);
    }

    /// @notice Queue a recipient for removal through the voting process
    function queueRecipientRemoval(address recipient) external {
        proposeRemoval(recipient);
    }

    /// @notice Create a proposal to add a new recipient to the registry
    function proposeAddition(address candidate) public returns (uint256 proposalId) {
        return _propose(candidate, true);
    }

    /// @notice Create a proposal to remove an existing recipient from the registry
    function proposeRemoval(address candidate) public returns (uint256 proposalId) {
        return _propose(candidate, false);
    }

    /// @notice Internal function to handle proposal creation with validation
    function _propose(address candidate, bool isAddition) internal returns (uint256 proposalId) {
        AbstractRecipientRegistryStorage storage base = _getAbstractRecipientRegistryStorage();
        if (!base.isRecipientMapping[msg.sender]) revert NotARecipient();

        if (isAddition) {
            if (candidate == address(0)) revert InvalidRecipient();
            if (base.isRecipientMapping[candidate]) revert RecipientAlreadyExists();
        } else {
            if (!base.isRecipientMapping[candidate]) revert RecipientNotFound();
        }

        return _createProposal(candidate, isAddition);
    }

    /// @notice Internal function to create a proposal with common logic
    function _createProposal(address candidate, bool isAddition) internal returns (uint256 proposalId) {
        VotingRecipientRegistryStorage storage $ = _getVotingRecipientRegistryStorage();
        proposalId = $.proposalCount++;
        Proposal storage proposal = $.proposals[proposalId];
        proposal.candidate = candidate;
        proposal.isAddition = isAddition;
        proposal.createdAt = block.timestamp;

        // Proposer automatically votes for their proposal
        proposal.hasVoted[msg.sender] = true;
        proposal.voteCount = 1;

        emit ProposalCreated(proposalId, candidate, isAddition);
        emit VoteCast(proposalId, msg.sender);
    }

    /// @notice Cast a vote on an existing proposal
    function vote(uint256 proposalId) external {
        AbstractRecipientRegistryStorage storage base = _getAbstractRecipientRegistryStorage();
        if (!base.isRecipientMapping[msg.sender]) revert NotARecipient();

        VotingRecipientRegistryStorage storage $ = _getVotingRecipientRegistryStorage();
        Proposal storage proposal = $.proposals[proposalId];
        if (proposal.candidate == address(0)) revert ProposalNotFound();
        if (proposal.executed) revert ProposalAlreadyExecuted();
        if (block.timestamp > proposal.createdAt + $.proposalExpiry) revert ProposalExpired();
        if (proposal.hasVoted[msg.sender]) revert AlreadyVoted();

        proposal.hasVoted[msg.sender] = true;
        proposal.voteCount++;

        emit VoteCast(proposalId, msg.sender);

        // Check if we have enough votes to execute automatically
        uint256 requiredVotes = proposal.isAddition ? base.recipients.length : base.recipients.length - 1;
        if (proposal.voteCount == requiredVotes) {
            _executeProposal(proposalId);
        }
    }

    /// @notice Manually execute a proposal that has received sufficient votes
    function executeProposal(uint256 proposalId) external {
        VotingRecipientRegistryStorage storage $ = _getVotingRecipientRegistryStorage();
        AbstractRecipientRegistryStorage storage base = _getAbstractRecipientRegistryStorage();
        Proposal storage proposal = $.proposals[proposalId];
        if (proposal.candidate == address(0)) revert ProposalNotFound();
        if (proposal.executed) revert ProposalAlreadyExecuted();
        if (block.timestamp > proposal.createdAt + $.proposalExpiry) revert ProposalExpired();

        uint256 requiredVotes = proposal.isAddition ? base.recipients.length : base.recipients.length - 1;

        if (proposal.voteCount < requiredVotes) revert NotEnoughVotes();

        _executeProposal(proposalId);
    }

    /// @notice Internal function to execute a proposal and queue recipients
    function _executeProposal(uint256 proposalId) internal {
        Proposal storage proposal = _getVotingRecipientRegistryStorage().proposals[proposalId];
        proposal.executed = true;

        if (proposal.isAddition) {
            _queueForAddition(proposal.candidate);
        } else {
            _queueForRemoval(proposal.candidate);
        }

        emit ProposalExecuted(proposalId);
    }

    /// @notice Get comprehensive details about a specific proposal
    function getProposal(uint256 proposalId)
        external
        view
        returns (address candidate, bool isAddition, uint256 voteCount, bool executed, uint256 createdAt)
    {
        Proposal storage proposal = _getVotingRecipientRegistryStorage().proposals[proposalId];
        return (proposal.candidate, proposal.isAddition, proposal.voteCount, proposal.executed, proposal.createdAt);
    }

    /// @notice Check if a specific address has voted on a proposal
    function hasVoted(uint256 proposalId, address voter) external view returns (bool hasVoted_) {
        return _getVotingRecipientRegistryStorage().proposals[proposalId].hasVoted[voter];
    }

    /// @notice Check if a proposal has expired
    function isProposalExpired(uint256 proposalId) external view returns (bool isExpired) {
        VotingRecipientRegistryStorage storage $ = _getVotingRecipientRegistryStorage();
        Proposal storage proposal = $.proposals[proposalId];
        return block.timestamp > proposal.createdAt + $.proposalExpiry;
    }
}
