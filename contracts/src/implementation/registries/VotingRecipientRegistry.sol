// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AbstractRecipientRegistry} from "../../abstract/AbstractRecipientRegistry.sol";
import {CrossChainRegistryBase} from "../../abstract/CrossChainRegistryBase.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @title VotingRecipientRegistry
/// @notice Democratic registry where all current recipients must vote to add new recipients
/// @dev Requires 100% unanimous consent from all current recipients to add new ones
/// @dev Proposals expire after 7 days if not executed
/// @dev Family instances (familyId != 0) replay proposals and votes cross-chain via chain-agnostic
///      signatures: the proposalKey is the EIP-712 struct hash (content-addressed, so the same
///      proposal exists under the same key on every sibling), and the SIGNED electorate must match
///      the local recipient set (order-independent) → identical requiredVotes everywhere. The
///      classic mutation paths are gated onlyClassicRegistry on family instances so a chain-local
///      proposal cannot silently break family set-equality.
/// @author BreadKit Protocol
contract VotingRecipientRegistry is AbstractRecipientRegistry, CrossChainRegistryBase {
    using ECDSA for bytes32;

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
        /// @notice Mapping of addresses eligible to vote, snapshotted at proposal creation
        mapping(address => bool) isEligibleVoter;
        /// @notice Whether this proposal has been executed (prevents double execution)
        bool executed;
        /// @notice Timestamp when this proposal was created (for expiry calculation)
        uint256 createdAt;
        /// @notice Number of votes required for this proposal to pass, snapshotted at creation
        uint256 requiredVotes;
    }

    /// @notice A cross-chain (family) proposal, keyed by its EIP-712 struct hash
    /// @dev Content-addressed: the same signed proposal exists under the same key on every sibling.
    ///      Snapshots the SIGNED electorate so requiredVotes is identical family-wide.
    struct CrossChainProposal {
        /// @notice The address being proposed for addition or removal
        address candidate;
        /// @notice True if this is an addition proposal, false for removal
        bool isAddition;
        /// @notice Whether this proposal has been executed on this chain
        bool executed;
        /// @notice Absolute Unix timestamp after which the proposal can no longer be acted on
        uint256 expiresAt;
        /// @notice Current number of votes received on this chain
        uint256 voteCount;
        /// @notice Votes required to pass (snapshotted from the signed electorate at creation)
        uint256 requiredVotes;
        /// @notice Whether an address has voted on this proposal on this chain
        mapping(address => bool) hasVoted;
        /// @notice Whether an address is in the signed electorate (snapshotted at creation)
        mapping(address => bool) isEligibleVoter;
    }

    // ============ Cross-chain EIP-712 Typehashes ============

    /// @notice EIP-712 typehash for a cross-chain proposal
    /// @dev proposalKey = keccak256(abi.encode(this typehash, ...)) — the struct hash itself.
    ///      Pinned for frontend/relay parity — do NOT change without updating both.
    bytes32 public constant CROSS_CHAIN_PROPOSAL_TYPEHASH = keccak256(
        "CrossChainProposal(address proposer,address candidate,bool isAddition,address[] electorate,uint256 expiresAt,uint256 nonce)"
    );

    /// @notice EIP-712 typehash for a cross-chain proposal vote
    /// @dev No nonce: per-chain replay is blocked by hasVoted, cross-proposal by proposalKey,
    ///      cross-family by the domain salt. Pinned for frontend/relay parity.
    bytes32 public constant CROSS_CHAIN_PROPOSAL_VOTE_TYPEHASH =
        keccak256("CrossChainProposalVote(address voter,bytes32 proposalKey,uint256 deadline)");

    // ============ EIP-7201 Namespaced Storage ============

    /// @custom:storage-location erc7201:crowdstake.storage.VotingRecipientRegistry
    struct VotingRecipientRegistryStorage {
        /// @notice Mapping from proposal ID to proposal data
        /// @dev Proposal IDs start from 0 and increment sequentially
        mapping(uint256 => Proposal) proposals;
        /// @notice Total number of proposals created (also serves as next proposal ID)
        /// @dev Incremented each time a new proposal is created
        uint256 proposalCount;
        /// @notice Time limit for proposals before they expire
        /// @dev Configurable value set during initialization, after which proposals cannot be voted on or executed
        /// @dev Can be updated by the admin using setProposalExpiry function
        uint256 proposalExpiry;
        /// @notice Cross-chain proposals keyed by their EIP-712 struct hash (content-addressed)
        /// @dev Append-only addition to this namespace; classic proposals are unaffected.
        mapping(bytes32 => CrossChainProposal) crossChainProposals;
        /// @notice Ordered list of every cross-chain proposalKey ever created on this chain
        /// @dev Append-only; enables enumeration for indexers/frontends.
        bytes32[] crossChainProposalKeys;
        /// @notice true = the classic path leaves the queue open (voidable via
        ///         clearAdditionQueue/clearRemovalQueue) until processQueue() is called
        ///         separately. false (default, zero value) = atomic: _processQueue() runs
        ///         immediately after queueing.
        /// @dev Stored inverted deliberately — a beacon upgrade zeroes any newly added
        ///      storage field on every already-deployed instance, so the default must be
        ///      "atomic" without needing a migration. The cross-chain path is unaffected by
        ///      this flag: it is always atomic, see _executeCrossChainProposal.
        bool voidableExecutionEnabled;
    }

    // keccak256(abi.encode(uint256(keccak256("crowdstake.storage.VotingRecipientRegistry")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant VOTING_RECIPIENT_REGISTRY_STORAGE =
        0xd1130eee9b149c4593e65f48b107ed420660e6ad58daa79da60d56a941d9d900;

    function _getVotingRecipientRegistryStorage() private pure returns (VotingRecipientRegistryStorage storage $) {
        assembly {
            $.slot := VOTING_RECIPIENT_REGISTRY_STORAGE
        }
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ============ Public Getters ============

    /// @notice Mapping from proposal ID to proposal data
    /// @dev Proposal IDs start from 0 and increment sequentially
    function proposals(uint256 proposalId)
        public
        view
        returns (address candidate, bool isAddition, uint256 voteCount, bool executed, uint256 createdAt)
    {
        Proposal storage proposal = _getVotingRecipientRegistryStorage().proposals[proposalId];
        return (proposal.candidate, proposal.isAddition, proposal.voteCount, proposal.executed, proposal.createdAt);
    }

    /// @notice Total number of proposals created (also serves as next proposal ID)
    /// @dev Incremented each time a new proposal is created
    function proposalCount() public view returns (uint256) {
        return _getVotingRecipientRegistryStorage().proposalCount;
    }

    /// @notice Time limit for proposals before they expire
    /// @dev Configurable value set during initialization, after which proposals cannot be voted on or executed
    /// @dev Can be updated by the admin using setProposalExpiry function
    function proposalExpiry() public view returns (uint256) {
        return _getVotingRecipientRegistryStorage().proposalExpiry;
    }

    // ============ Events ============

    /// @notice Emitted when a new proposal is created
    /// @param proposalId The unique ID of the created proposal
    /// @param candidate The address being proposed for addition or removal
    /// @param isAddition True if this is an addition proposal, false for removal
    event ProposalCreated(uint256 indexed proposalId, address indexed candidate, bool isAddition);

    /// @notice Emitted when a recipient casts a vote on a proposal
    /// @param proposalId The ID of the proposal being voted on
    /// @param voter The address of the recipient who cast the vote
    event VoteCast(uint256 indexed proposalId, address indexed voter);

    /// @notice Emitted when a proposal is successfully executed
    /// @param proposalId The ID of the executed proposal
    event ProposalExecuted(uint256 indexed proposalId);

    /// @notice Emitted when a proposal expires without being executed
    /// @param proposalId The ID of the expired proposal
    event ProposalExpiredEvent(uint256 indexed proposalId);

    /// @notice Emitted when the proposal expiry duration is updated
    /// @param oldExpiry The previous expiry duration in seconds
    /// @param newExpiry The new expiry duration in seconds
    event ProposalExpiryUpdated(uint256 oldExpiry, uint256 newExpiry);

    /// @notice Emitted when the classic-path execution mode is updated
    /// @dev Cross-chain execution is unaffected — always atomic regardless of this flag.
    /// @param atomicExecutionEnabled True if the classic path now executes atomically
    event AtomicExecutionUpdated(bool atomicExecutionEnabled);

    /// @notice Emitted when a cross-chain proposal is created on this chain
    /// @dev Re-emits the full signed payload so the relay listener can propagate it to siblings.
    /// @param proposalKey The EIP-712 struct hash identifying the proposal family-wide
    /// @param proposer The proposer who signed and auto-voted
    /// @param candidate The address proposed for addition or removal
    /// @param isAddition True if this is an addition proposal, false for removal
    /// @param electorate The signed electorate (snapshotted as eligible voters)
    /// @param expiresAt Absolute Unix timestamp after which the proposal cannot be acted on
    /// @param nonce The nonce distinguishing repeat proposals of identical content
    /// @param signature The chain-agnostic EIP-712 signature over the family domain
    event CrossChainProposalCreated(
        bytes32 indexed proposalKey,
        address proposer,
        address candidate,
        bool isAddition,
        address[] electorate,
        uint256 expiresAt,
        uint256 nonce,
        bytes signature
    );

    /// @notice Emitted when a cross-chain proposal vote is cast on this chain
    /// @dev Re-emits the full signed payload so the relay listener can propagate it to siblings.
    /// @param proposalKey The EIP-712 struct hash identifying the proposal family-wide
    /// @param voter The voter who signed
    /// @param deadline Unix timestamp after which the vote signature is invalid
    /// @param signature The chain-agnostic EIP-712 signature over the family domain
    event CrossChainProposalVoteCast(bytes32 indexed proposalKey, address voter, uint256 deadline, bytes signature);

    /// @notice Emitted when a cross-chain proposal is executed on this chain
    /// @param proposalKey The EIP-712 struct hash identifying the proposal family-wide
    event CrossChainProposalExecuted(bytes32 indexed proposalKey);

    // ============ Errors ============

    /// @notice Thrown when a non-recipient attempts to perform recipient-only actions
    error NotARecipient();

    /// @notice Thrown when attempting to access a proposal that doesn't exist
    error ProposalNotFound();

    /// @notice Thrown when a recipient attempts to vote on the same proposal twice
    error AlreadyVoted();

    /// @notice Thrown when attempting to vote on or execute a proposal that has already been executed
    error ProposalAlreadyExecuted();

    /// @notice Thrown when attempting to vote on or execute a proposal that has expired
    error ProposalExpired();

    /// @notice Thrown when attempting to execute a proposal without sufficient votes
    error NotEnoughVotes();

    /// @notice Thrown when a voter was not a recipient at the time the proposal was created
    error NotEligibleVoter();

    /// @notice Thrown when attempting to initialize the registry with an empty recipients array
    error NoRecipients();

    /// @notice Thrown when attempting to set an invalid proposal expiry duration
    error InvalidProposalExpiry();

    /// @notice Thrown when creating a cross-chain proposal whose key already exists on this chain
    error ProposalAlreadyExists();

    /// @notice Thrown when a signed absolute expiry exceeds block.timestamp + proposalExpiry
    error ExpiryTooFar();

    // ============ Initialization ============

    /// @notice Initialize the registry with a set of initial recipients (classic instance)
    /// @dev Back-compat overload: familyId = 0 (cross-chain path disabled).
    /// @param admin The address that will have administrative control (limited to emergency functions)
    /// @param initialRecipients Array of addresses that will be the initial voting recipients
    /// @param _proposalExpiry Time limit in seconds for how long proposals remain valid for voting
    function initialize(address admin, address[] memory initialRecipients, uint256 _proposalExpiry) public initializer {
        _initialize(admin, initialRecipients, _proposalExpiry, bytes32(0));
    }

    /// @notice Initialize the registry with a set of initial recipients and a family identity
    /// @dev This function replaces the constructor for upgradeable contracts
    /// @dev The admin is set but only used for emergency functions like clearing queues
    /// @dev All recipient changes after initialization must go through the voting process
    /// @dev Can only be called once due to the initializer modifier
    /// @param admin The address that will have administrative control (limited to emergency functions)
    /// @param initialRecipients Array of addresses that will be the initial voting recipients
    /// @param _proposalExpiry Time limit in seconds for how long proposals remain valid for voting
    /// @param _familyId Cross-chain family identity (0 = classic chain-bound instance)
    function initialize(address admin, address[] memory initialRecipients, uint256 _proposalExpiry, bytes32 _familyId)
        public
        initializer
    {
        _initialize(admin, initialRecipients, _proposalExpiry, _familyId);
    }

    /// @dev Shared initializer body for both overloads.
    function _initialize(address admin, address[] memory initialRecipients, uint256 _proposalExpiry, bytes32 _familyId)
        private
    {
        __Ownable_init(admin);
        __CrossChainRegistryBase_init(_familyId);

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
    /// @dev Only the admin (owner) can call this function
    /// @dev Setting expiry to 0 is not allowed to prevent immediate expiration of all proposals
    /// @dev This change affects all future proposals, existing proposals use their original expiry
    /// @param newExpiry The new expiry duration in seconds
    function setProposalExpiry(uint256 newExpiry) external onlyOwner {
        if (newExpiry == 0) revert InvalidProposalExpiry();

        VotingRecipientRegistryStorage storage $ = _getVotingRecipientRegistryStorage();
        uint256 oldExpiry = $.proposalExpiry;
        $.proposalExpiry = newExpiry;

        emit ProposalExpiryUpdated(oldExpiry, newExpiry);
    }

    /// @notice Whether the classic path executes atomically (default) or leaves a
    ///         voidable window open until processQueue() is called separately
    /// @dev Cross-chain execution is always atomic, regardless of this flag.
    function atomicExecutionEnabled() public view returns (bool) {
        return !_getVotingRecipientRegistryStorage().voidableExecutionEnabled;
    }

    /// @notice Switch the classic path between atomic and voidable execution
    /// @dev Only the admin (owner) can call this function. Does not affect the
    ///      cross-chain path, which is always atomic.
    /// @param atomicExecutionEnabled_ True for atomic (no cancellation window), false for
    ///        the voidable behavior (owner can clear the queue before processQueue() runs)
    function setAtomicExecution(bool atomicExecutionEnabled_) external onlyOwner {
        _getVotingRecipientRegistryStorage().voidableExecutionEnabled = !atomicExecutionEnabled_;
        emit AtomicExecutionUpdated(atomicExecutionEnabled_);
    }

    /// @notice Queue a recipient for addition through the voting process
    /// @dev This creates a proposal instead of directly queueing
    /// @dev Only existing recipients can call this function
    /// @dev The proposer automatically votes for their own proposal
    /// @param recipient Address to propose for addition to the recipient list
    function queueRecipientAddition(address recipient) external onlyClassicRegistry {
        proposeAddition(recipient);
    }

    /// @notice Queue a recipient for removal through the voting process
    /// @dev This creates a proposal instead of directly queueing
    /// @dev Only existing recipients can call this function
    /// @dev The proposer automatically votes for their own proposal
    /// @param recipient Address to propose for removal from the recipient list
    function queueRecipientRemoval(address recipient) external onlyClassicRegistry {
        proposeRemoval(recipient);
    }

    /// @notice Create a proposal to add a new recipient to the registry
    /// @dev Only existing recipients can create proposals
    /// @dev The proposer automatically casts the first vote
    /// @dev Proposals expire after the configured proposalExpiry time if not executed
    /// @dev Emits ProposalCreated and VoteCast events
    /// @param candidate The address to propose for addition
    /// @return proposalId The unique ID of the created proposal
    function proposeAddition(address candidate) public onlyClassicRegistry returns (uint256 proposalId) {
        return _propose(candidate, true);
    }

    /// @notice Create a proposal to remove an existing recipient from the registry
    /// @dev Only existing recipients can create proposals
    /// @dev The proposer automatically casts the first vote
    /// @dev Proposals expire after the configured proposalExpiry time if not executed
    /// @dev Removal proposals require n-1 votes (all except the one being removed)
    /// @dev Emits ProposalCreated and VoteCast events
    /// @param candidate The address to propose for removal
    /// @return proposalId The unique ID of the created proposal
    function proposeRemoval(address candidate) public onlyClassicRegistry returns (uint256 proposalId) {
        return _propose(candidate, false);
    }

    /// @notice Internal function to handle proposal creation with validation
    /// @dev Validates proposer permissions and candidate eligibility based on proposal type
    /// @dev Eliminates code duplication between proposeAddition and proposeRemoval
    /// @param candidate The address being proposed for addition or removal
    /// @param isAddition True if this is an addition proposal, false for removal
    /// @return proposalId The unique ID of the created proposal
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
    /// @dev Handles proposal creation, automatic voting by proposer, and event emission
    /// @dev This function eliminates code duplication between proposeAddition and proposeRemoval
    /// @param candidate The address being proposed for addition or removal
    /// @param isAddition True if this is an addition proposal, false for removal
    /// @return proposalId The unique ID of the created proposal
    function _createProposal(address candidate, bool isAddition) internal returns (uint256 proposalId) {
        VotingRecipientRegistryStorage storage $ = _getVotingRecipientRegistryStorage();
        proposalId = $.proposalCount++;
        Proposal storage proposal = $.proposals[proposalId];
        proposal.candidate = candidate;
        proposal.isAddition = isAddition;
        proposal.createdAt = block.timestamp;
        AbstractRecipientRegistryStorage storage base = _getAbstractRecipientRegistryStorage();
        proposal.requiredVotes = isAddition ? base.recipients.length : base.recipients.length - 1;

        // Snapshot eligible voters from the current recipient set
        for (uint256 i = 0; i < base.recipients.length; i++) {
            proposal.isEligibleVoter[base.recipients[i]] = true;
        }

        // Proposer automatically votes for their proposal
        proposal.hasVoted[msg.sender] = true;
        proposal.voteCount = 1;

        emit ProposalCreated(proposalId, candidate, isAddition);
        emit VoteCast(proposalId, msg.sender);
    }

    /// @notice Cast a vote on an existing proposal
    /// @dev Only recipients who were active at proposal creation can vote (snapshotted eligibility)
    /// @dev Voters cannot vote twice on the same proposal
    /// @dev Voting is not allowed on expired or already executed proposals
    /// @dev Automatically executes the proposal if enough votes are reached
    /// @dev Emits VoteCast event and potentially ProposalExecuted if threshold reached
    /// @param proposalId The ID of the proposal to vote on
    function vote(uint256 proposalId) external onlyClassicRegistry {
        VotingRecipientRegistryStorage storage $ = _getVotingRecipientRegistryStorage();
        Proposal storage proposal = $.proposals[proposalId];
        if (proposal.candidate == address(0)) revert ProposalNotFound();
        if (proposal.executed) revert ProposalAlreadyExecuted();
        if (block.timestamp > proposal.createdAt + $.proposalExpiry) revert ProposalExpired();
        if (!proposal.isEligibleVoter[msg.sender]) revert NotEligibleVoter();
        if (proposal.hasVoted[msg.sender]) revert AlreadyVoted();

        proposal.hasVoted[msg.sender] = true;
        proposal.voteCount++;

        emit VoteCast(proposalId, msg.sender);

        // Check if we have enough votes to execute automatically
        if (proposal.voteCount == proposal.requiredVotes) {
            _executeProposal(proposalId);
        }
    }

    /// @notice Manually execute a proposal that has received sufficient votes
    /// @dev Anyone can call this function if the proposal has enough votes
    /// @dev Proposals cannot be executed if they are expired or already executed
    /// @dev Vote threshold is snapshotted at proposal creation and does not change
    /// @param proposalId The ID of the proposal to execute
    function executeProposal(uint256 proposalId) external onlyClassicRegistry {
        VotingRecipientRegistryStorage storage $ = _getVotingRecipientRegistryStorage();
        Proposal storage proposal = $.proposals[proposalId];
        if (proposal.candidate == address(0)) revert ProposalNotFound();
        if (proposal.executed) revert ProposalAlreadyExecuted();
        if (block.timestamp > proposal.createdAt + $.proposalExpiry) revert ProposalExpired();

        if (proposal.requiredVotes == 0) revert NotEnoughVotes();
        if (proposal.voteCount < proposal.requiredVotes) revert NotEnoughVotes();

        _executeProposal(proposalId);
    }

    /// @notice Internal function to execute a proposal and queue recipients
    /// @dev Marks the proposal as executed to prevent double execution
    /// @dev Queues the candidate for addition or removal based on proposal type
    /// @dev Atomic by default: processes the queue in the same call, closing the
    ///      cancellation window. If voidableExecutionEnabled is set, the queue is left
    ///      open and must be processed separately by calling processQueue().
    /// @dev Emits ProposalExecuted event after successful execution
    /// @param proposalId The ID of the proposal to execute
    function _executeProposal(uint256 proposalId) internal {
        VotingRecipientRegistryStorage storage $ = _getVotingRecipientRegistryStorage();
        Proposal storage proposal = $.proposals[proposalId];
        proposal.executed = true;

        if (proposal.isAddition) {
            _queueForAddition(proposal.candidate);
        } else {
            _queueForRemoval(proposal.candidate);
        }

        if (!$.voidableExecutionEnabled) _processQueue();

        emit ProposalExecuted(proposalId);
    }

    // ============ Cross-chain (family) governance ============

    /// @notice Create a cross-chain proposal from a chain-agnostic proposer signature
    /// @dev Permissionless delivery. proposalKey = the EIP-712 struct hash (content-addressed, so
    ///      the same proposal exists under the same key on every sibling). The SIGNED electorate
    ///      must equal the local recipient set (order-independent) → identical requiredVotes
    ///      everywhere, or fail-loud RecipientSetMismatch. The proposer must be in the electorate
    ///      and auto-votes on creation.
    /// @param proposer The proposer who signed (must be in the electorate)
    /// @param candidate The address proposed for addition or removal
    /// @param isAddition True for an addition proposal, false for removal
    /// @param electorate The recipient set as seen on the signing chain (must match locally)
    /// @param expiresAt Absolute Unix timestamp the proposal expires at (bounded on-chain)
    /// @param nonce Distinguishes repeat proposals of identical content
    /// @param signature Chain-agnostic EIP-712 signature over the family domain
    /// @return proposalKey The EIP-712 struct hash identifying the proposal family-wide
    function createCrossChainProposal(
        address proposer,
        address candidate,
        bool isAddition,
        address[] calldata electorate,
        uint256 expiresAt,
        uint256 nonce,
        bytes calldata signature
    ) external crossChainOnly returns (bytes32 proposalKey) {
        VotingRecipientRegistryStorage storage $ = _getVotingRecipientRegistryStorage();

        // Bound the signed absolute expiry against this chain's ceiling.
        if (expiresAt > block.timestamp + $.proposalExpiry) revert ExpiryTooFar();
        if (block.timestamp > expiresAt) revert ProposalExpired();

        proposalKey = keccak256(
            abi.encode(
                CROSS_CHAIN_PROPOSAL_TYPEHASH,
                proposer,
                candidate,
                isAddition,
                keccak256(abi.encodePacked(electorate)),
                expiresAt,
                nonce
            )
        );

        // Key-existence dedup — concurrent proposals must not supersede each other.
        if ($.crossChainProposals[proposalKey].candidate != address(0)) revert ProposalAlreadyExists();

        // Candidate eligibility mirrors the classic path.
        AbstractRecipientRegistryStorage storage base = _getAbstractRecipientRegistryStorage();
        if (isAddition) {
            if (candidate == address(0)) revert InvalidRecipient();
            if (base.isRecipientMapping[candidate]) revert RecipientAlreadyExists();
        } else {
            if (!base.isRecipientMapping[candidate]) revert RecipientNotFound();
        }

        // The signed electorate must equal the local recipient set (order-independent).
        _requireElectorateMatchesLocal(electorate);

        // Proposer must be in the electorate.
        if (!_electorateContains(electorate, proposer)) revert NotEligibleVoter();

        // Verify the chain-agnostic signature recovers to the proposer.
        if (_hashCrossChainTypedData(proposalKey).recover(signature) != proposer) revert InvalidSignature();

        // Snapshot the proposal from the signed electorate.
        CrossChainProposal storage proposal = $.crossChainProposals[proposalKey];
        proposal.candidate = candidate;
        proposal.isAddition = isAddition;
        proposal.expiresAt = expiresAt;
        proposal.requiredVotes = isAddition ? electorate.length : electorate.length - 1;
        for (uint256 i = 0; i < electorate.length; i++) {
            proposal.isEligibleVoter[electorate[i]] = true;
        }
        $.crossChainProposalKeys.push(proposalKey);

        // Proposer auto-votes on creation.
        proposal.hasVoted[proposer] = true;
        proposal.voteCount = 1;

        emit CrossChainProposalCreated(
            proposalKey, proposer, candidate, isAddition, electorate, expiresAt, nonce, signature
        );

        // A single-member electorate reaches threshold on creation.
        if (proposal.voteCount >= proposal.requiredVotes) {
            _executeCrossChainProposal(proposalKey);
        }
    }

    /// @notice Cast a vote on a cross-chain proposal from a chain-agnostic voter signature
    /// @dev Permissionless delivery. No nonce: per-chain replay is blocked by hasVoted,
    ///      cross-proposal by proposalKey in the signature, cross-family by the domain salt.
    ///      deadline bounds floating signatures and is checked independently of expiry.
    /// @param voter The voter who signed
    /// @param proposalKey The EIP-712 struct hash identifying the proposal
    /// @param deadline Unix timestamp after which the vote signature is invalid
    /// @param signature Chain-agnostic EIP-712 signature over the family domain
    function castCrossChainProposalVote(address voter, bytes32 proposalKey, uint256 deadline, bytes calldata signature)
        external
        crossChainOnly
    {
        VotingRecipientRegistryStorage storage $ = _getVotingRecipientRegistryStorage();
        CrossChainProposal storage proposal = $.crossChainProposals[proposalKey];

        if (proposal.candidate == address(0)) revert ProposalNotFound();
        if (block.timestamp > deadline) revert SignatureExpired();
        if (proposal.executed) revert ProposalAlreadyExecuted();
        if (block.timestamp > proposal.expiresAt) revert ProposalExpired();
        if (!proposal.isEligibleVoter[voter]) revert NotEligibleVoter();
        if (proposal.hasVoted[voter]) revert AlreadyVoted();

        // Verify the chain-agnostic signature recovers to the voter.
        bytes32 structHash = keccak256(abi.encode(CROSS_CHAIN_PROPOSAL_VOTE_TYPEHASH, voter, proposalKey, deadline));
        if (_hashCrossChainTypedData(structHash).recover(signature) != voter) revert InvalidSignature();

        proposal.hasVoted[voter] = true;
        proposal.voteCount++;

        emit CrossChainProposalVoteCast(proposalKey, voter, deadline, signature);

        if (proposal.voteCount >= proposal.requiredVotes) {
            _executeCrossChainProposal(proposalKey);
        }
    }

    /// @notice Permissionlessly execute a cross-chain proposal that has reached its threshold
    /// @dev Anyone can call. Reverts if not found, executed, expired, or lacking votes.
    /// @param proposalKey The EIP-712 struct hash identifying the proposal
    function executeCrossChainProposal(bytes32 proposalKey) external crossChainOnly {
        VotingRecipientRegistryStorage storage $ = _getVotingRecipientRegistryStorage();
        CrossChainProposal storage proposal = $.crossChainProposals[proposalKey];

        if (proposal.candidate == address(0)) revert ProposalNotFound();
        if (proposal.executed) revert ProposalAlreadyExecuted();
        if (block.timestamp > proposal.expiresAt) revert ProposalExpired();
        if (proposal.voteCount < proposal.requiredVotes) revert NotEnoughVotes();

        _executeCrossChainProposal(proposalKey);
    }

    /// @notice Internal execution: always queue + processQueue in the same call.
    /// @dev The queue is empty at every execution (each execution drains it), so per-chain
    ///      delivery order of independent proposals can never trip the ascending-queue invariant
    ///      inside a vote tx. If the effect is already in place (add && already recipient /
    ///      remove && absent) the execution is a no-op — marked executed, event emitted, no queue.
    function _executeCrossChainProposal(bytes32 proposalKey) internal {
        CrossChainProposal storage proposal = _getVotingRecipientRegistryStorage().crossChainProposals[proposalKey];
        proposal.executed = true;

        AbstractRecipientRegistryStorage storage base = _getAbstractRecipientRegistryStorage();
        bool isRecipientNow = base.isRecipientMapping[proposal.candidate];

        if (proposal.isAddition) {
            if (!isRecipientNow) {
                _queueForAddition(proposal.candidate);
                _processQueue();
            }
        } else {
            if (isRecipientNow) {
                _queueForRemoval(proposal.candidate);
                _processQueue();
            }
        }

        emit CrossChainProposalExecuted(proposalKey);
    }

    /// @dev Set-equality between the signed electorate and the local recipient set,
    ///      order-independent. Reuses the identity-match loop shape from BasisPointsVotingModule.
    function _requireElectorateMatchesLocal(address[] calldata electorate) private view {
        address[] memory local = _getAbstractRecipientRegistryStorage().recipients;
        if (electorate.length != local.length) revert RecipientSetMismatch();

        for (uint256 i = 0; i < local.length; i++) {
            bool found = false;
            for (uint256 j = 0; j < electorate.length; j++) {
                if (electorate[j] == local[i]) {
                    if (found) revert RecipientSetMismatch();
                    found = true;
                }
            }
            if (!found) revert RecipientSetMismatch();
        }
    }

    /// @dev True if `who` appears in the signed electorate.
    function _electorateContains(address[] calldata electorate, address who) private pure returns (bool) {
        for (uint256 i = 0; i < electorate.length; i++) {
            if (electorate[i] == who) return true;
        }
        return false;
    }

    // ============ Classic Views ============

    /// @notice Get comprehensive details about a specific proposal
    /// @dev Returns all relevant information about a proposal in one call
    /// @dev Gas efficient alternative to multiple separate calls
    /// @param proposalId The ID of the proposal to query
    /// @return candidate The address being proposed for addition or removal
    /// @return isAddition Whether this is an addition (true) or removal (false) proposal
    /// @return voteCount Current number of votes the proposal has received
    /// @return requiredVotes Number of votes needed for the proposal to pass (snapshotted at creation)
    /// @return executed Whether the proposal has been executed successfully
    /// @return createdAt Timestamp when the proposal was created (for expiry calculation)
    function getProposal(uint256 proposalId)
        external
        view
        returns (
            address candidate,
            bool isAddition,
            uint256 voteCount,
            uint256 requiredVotes,
            bool executed,
            uint256 createdAt
        )
    {
        Proposal storage proposal = _getVotingRecipientRegistryStorage().proposals[proposalId];
        if (proposal.candidate == address(0)) revert ProposalNotFound();
        return (
            proposal.candidate,
            proposal.isAddition,
            proposal.voteCount,
            proposal.requiredVotes,
            proposal.executed,
            proposal.createdAt
        );
    }

    /// @notice Check if a specific address has voted on a proposal
    /// @dev Useful for frontend applications to show voting status
    /// @dev Returns false for non-existent proposals or voters
    /// @param proposalId The ID of the proposal to check
    /// @param voter The address to check voting status for
    /// @return hasVoted_ True if the address has voted on this proposal, false otherwise
    function hasVoted(uint256 proposalId, address voter) external view returns (bool hasVoted_) {
        return _getVotingRecipientRegistryStorage().proposals[proposalId].hasVoted[voter];
    }

    /// @notice Check if an address was eligible to vote on a proposal
    /// @dev Eligibility is snapshotted at proposal creation from the recipient set at that time
    /// @param proposalId The ID of the proposal to check
    /// @param voter The address to check eligibility for
    /// @return isEligible True if the address was a recipient when the proposal was created
    function isEligibleVoter(uint256 proposalId, address voter) external view returns (bool isEligible) {
        return _getVotingRecipientRegistryStorage().proposals[proposalId].isEligibleVoter[voter];
    }

    /// @notice Check if a proposal has expired and can no longer be voted on
    /// @dev Proposals expire after the configured proposalExpiry time from creation
    /// @dev Expired proposals cannot receive votes or be executed
    /// @param proposalId The ID of the proposal to check
    /// @return isExpired True if the proposal has expired, false otherwise
    function isProposalExpired(uint256 proposalId) external view returns (bool isExpired) {
        VotingRecipientRegistryStorage storage $ = _getVotingRecipientRegistryStorage();
        Proposal storage proposal = $.proposals[proposalId];
        return block.timestamp > proposal.createdAt + $.proposalExpiry;
    }

    /// @notice Get the number of votes required for a proposal to pass
    /// @dev Returns the snapshotted value from proposal creation time
    /// @param proposalId The ID of the proposal to check requirements for
    /// @return requiredVotes Number of votes needed for the proposal to be executable
    function getRequiredVotes(uint256 proposalId) external view returns (uint256 requiredVotes) {
        Proposal storage proposal = _getVotingRecipientRegistryStorage().proposals[proposalId];
        if (proposal.candidate == address(0)) revert ProposalNotFound();

        return proposal.requiredVotes;
    }

    // ============ Cross-chain Views ============

    /// @notice Number of cross-chain proposals ever created on this chain
    function crossChainProposalCount() external view returns (uint256) {
        return _getVotingRecipientRegistryStorage().crossChainProposalKeys.length;
    }

    /// @notice The cross-chain proposalKey at the given index (creation order)
    /// @param index Index into the append-only proposalKeys list
    function crossChainProposalKeyAt(uint256 index) external view returns (bytes32) {
        return _getVotingRecipientRegistryStorage().crossChainProposalKeys[index];
    }

    /// @notice Get the details of a cross-chain proposal
    /// @param proposalKey The EIP-712 struct hash identifying the proposal
    /// @return candidate The address proposed for addition or removal
    /// @return isAddition Whether this is an addition (true) or removal (false) proposal
    /// @return executed Whether the proposal has been executed on this chain
    /// @return expiresAt Absolute Unix timestamp the proposal expires at
    /// @return voteCount Current number of votes on this chain
    /// @return requiredVotes Votes required to pass (snapshotted from the signed electorate)
    function getCrossChainProposal(bytes32 proposalKey)
        external
        view
        returns (
            address candidate,
            bool isAddition,
            bool executed,
            uint256 expiresAt,
            uint256 voteCount,
            uint256 requiredVotes
        )
    {
        CrossChainProposal storage proposal = _getVotingRecipientRegistryStorage().crossChainProposals[proposalKey];
        if (proposal.candidate == address(0)) revert ProposalNotFound();
        return (
            proposal.candidate,
            proposal.isAddition,
            proposal.executed,
            proposal.expiresAt,
            proposal.voteCount,
            proposal.requiredVotes
        );
    }

    /// @notice Whether an address has voted on a cross-chain proposal on this chain
    /// @param proposalKey The EIP-712 struct hash identifying the proposal
    /// @param voter The address to check
    function hasVotedCrossChain(bytes32 proposalKey, address voter) external view returns (bool) {
        return _getVotingRecipientRegistryStorage().crossChainProposals[proposalKey].hasVoted[voter];
    }

    /// @notice Whether an address is in the signed electorate of a cross-chain proposal
    /// @param proposalKey The EIP-712 struct hash identifying the proposal
    /// @param voter The address to check
    function isEligibleCrossChainVoter(bytes32 proposalKey, address voter) external view returns (bool) {
        return _getVotingRecipientRegistryStorage().crossChainProposals[proposalKey].isEligibleVoter[voter];
    }
}
