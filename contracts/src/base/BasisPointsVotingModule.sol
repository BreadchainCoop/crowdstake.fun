// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AbstractVotingModule} from "../abstract/AbstractVotingModule.sol";
import {IVotingPowerStrategy} from "../interfaces/IVotingPowerStrategy.sol";

/// @title BasisPointsVotingModule
/// @author BreadKit
/// @notice Concrete implementation of voting module using basis points for vote allocation
/// @dev Extends AbstractVotingModule to provide basis points-based voting functionality.
///      This module allows users to allocate voting points across multiple recipients
///      using signature-based voting for gas efficiency and better UX.
/// @custom:security-contact security@breadchain.xyz
contract BasisPointsVotingModule is AbstractVotingModule {
    // ============ EIP-7201 Namespaced Storage ============

    /// @custom:storage-location erc7201:crowdstake.storage.BasisPointsVotingModule
    struct BasisPointsVotingModuleStorage {
        /// @notice Maximum points that can be allocated to a single recipient
        /// @dev Configurable per implementation to control vote distribution
        uint256 maxPoints;
        /// @notice Vote distribution across projects for each cycle
        /// @dev cycle => array of weighted votes per project
        mapping(uint256 => uint256[]) projectDistributions;
        /// @notice Tracks voting power used by each voter in each cycle
        /// @dev cycle => voter => voting power used
        mapping(uint256 => mapping(address => uint256)) voterCyclePower;
        /// @notice Tracks points allocated by each voter in each cycle
        /// @dev cycle => voter => points array
        mapping(uint256 => mapping(address => uint256[])) voterCyclePoints;
    }

    // keccak256(abi.encode(uint256(keccak256("crowdstake.storage.BasisPointsVotingModule")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant BASIS_POINTS_VOTING_MODULE_STORAGE =
        0x36e581454c484c4e200212d5304c93307b309208c9d5c05d80ca836f1eed6600;

    function _getBasisPointsVotingModuleStorage() internal pure returns (BasisPointsVotingModuleStorage storage $) {
        assembly {
            $.slot := BASIS_POINTS_VOTING_MODULE_STORAGE
        }
    }

    // ============ Public Getters ============

    /// @notice Maximum points that can be allocated to a single recipient
    /// @dev Configurable per implementation to control vote distribution
    function maxPoints() public view returns (uint256) {
        return _getBasisPointsVotingModuleStorage().maxPoints;
    }

    /// @notice Vote distribution across projects for each cycle
    /// @dev cycle => array of weighted votes per project
    function projectDistributions(uint256 cycle, uint256 index) public view returns (uint256) {
        return _getBasisPointsVotingModuleStorage().projectDistributions[cycle][index];
    }

    /// @notice Tracks voting power used by each voter in each cycle
    /// @dev cycle => voter => voting power used
    function voterCyclePower(uint256 cycle, address voter) public view returns (uint256) {
        return _getBasisPointsVotingModuleStorage().voterCyclePower[cycle][voter];
    }

    /// @notice Tracks points allocated by each voter in each cycle
    /// @dev cycle => voter => points array
    function voterCyclePoints(uint256 cycle, address voter, uint256 index) public view returns (uint256) {
        return _getBasisPointsVotingModuleStorage().voterCyclePoints[cycle][voter][index];
    }

    // ============ Constructor ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ============ Initialization ============

    /// @notice Initializes the basis points voting module
    /// @dev Sets up the voting module with strategies and external dependencies.
    ///      Can only be called once due to initializer modifier.
    ///      Derives recipientRegistry and cycleModule from the distribution module.
    /// @param _maxPoints Maximum points that can be allocated per recipient (e.g., 100 for percentage-based)
    /// @param _strategies Array of voting power strategy contracts to use for power calculation
    /// @param _distributionModule Address of the distribution module (recipientRegistry and cycleModule are derived from it)
    /// @param _owner Address that will own this contract (receives onlyOwner privileges)
    function initialize(
        uint256 _maxPoints,
        IVotingPowerStrategy[] calldata _strategies,
        address _distributionModule,
        address _owner
    ) external initializer {
        _getBasisPointsVotingModuleStorage().maxPoints = _maxPoints;
        __AbstractVotingModule_init(_strategies, _distributionModule, _owner);
    }

    // ============ External Functions ============

    /// @notice Casts a vote with an EIP-712 signature
    /// @dev Validates the signature and processes the vote using the voter's current voting power.
    ///      The signature must be valid and the nonce must not have been used.
    /// @param voter The address of the voter casting the vote
    /// @param points Array of basis points to allocate to each recipient (must sum to <= maxPoints per recipient)
    /// @param nonce Unique nonce for this vote to prevent replay attacks
    /// @param signature EIP-712 signature authorizing this vote
    function castVoteWithSignature(address voter, uint256[] calldata points, uint256 nonce, bytes calldata signature)
        external
    {
        _castSingleVote(voter, points, nonce, signature);
    }

    /// @notice Casts a vote with an EIP-712 signature and additional bytes parameters
    /// @dev Same as castVoteWithSignature but also passes arbitrary bytes data to downstream
    ///      implementations (e.g., multiplier indices, metadata, conditional voting params).
    ///      See _handleAdditionalVoteData for the downstream hook.
    /// @param voter The address of the voter casting the vote
    /// @param points Array of basis points to allocate to each recipient
    /// @param nonce Unique nonce for this vote to prevent replay attacks
    /// @param signature EIP-712 signature authorizing this vote
    /// @param additionalData Arbitrary bytes data passed to downstream implementations
    function castVoteWithSignatureAndParams(
        address voter,
        uint256[] calldata points,
        uint256 nonce,
        bytes calldata signature,
        bytes calldata additionalData
    ) external {
        _castSingleVoteWithParams(voter, points, nonce, signature, additionalData);
    }

    /// @notice Casts a direct vote with additional bytes data (no EIP-712 signature required)
    /// @dev msg.sender is the voter. Validates points, records the vote, and invokes the
    ///      _handleAdditionalVoteData hook. Reverts if the caller already voted this cycle.
    ///      Emits VoteWithData. See Issue #62.
    /// @param points Array of basis points to allocate to each recipient
    /// @param data Arbitrary bytes data forwarded to _handleAdditionalVoteData
    function voteWithData(uint256[] calldata points, bytes calldata data) external {
        if (hasVotedInCurrentCycle(msg.sender)) revert AlreadyVotedInCurrentCycle();
        if (!_validateVotePoints(points)) revert InvalidPointsDistribution();

        uint256 votingPower = _calculateTotalVotingPower(msg.sender);
        _processVoteWithParams(msg.sender, points, votingPower, data);

        emit VoteWithData(msg.sender, points, data);
    }

    /// @notice Casts multiple direct votes with additional data in a single transaction
    /// @dev Processes each (voter, points, data) tuple atomically. If any entry fails, the
    ///      entire batch reverts. Limited to MAX_BATCH_SIZE entries. Does NOT require
    ///      EIP-712 signatures — suitable for keeper / relayer flows where voting power is
    ///      determined by on-chain token holdings. See Issue #62.
    /// @param voters Array of voter addresses
    /// @param points Array of point allocations per voter
    /// @param data Array of arbitrary bytes data per voter
    function voteWithDataBatch(address[] calldata voters, uint256[][] calldata points, bytes[] calldata data)
        external
        onlyOwner
    {
        if (voters.length != points.length) revert ArrayLengthMismatch();
        if (voters.length != data.length) revert ArrayLengthMismatch();
        if (voters.length > MAX_BATCH_SIZE) revert BatchTooLarge();

        for (uint256 i = 0; i < voters.length; i++) {
            if (hasVotedInCurrentCycle(voters[i])) revert AlreadyVotedInCurrentCycle();
            if (!_validateVotePoints(points[i])) revert InvalidPointsDistribution();
            uint256 votingPower = _calculateTotalVotingPower(voters[i]);
            _processVoteWithParams(voters[i], points[i], votingPower, data[i]);
            emit VoteWithData(voters[i], points[i], data[i]);
        }
    }

    /// @notice Casts multiple votes in a single transaction for gas efficiency
    /// @dev Processes multiple votes atomically. If any vote fails, the entire batch reverts.
    ///      Limited to MAX_BATCH_SIZE votes per transaction to prevent gas limit issues.
    /// @param voters Array of voter addresses
    /// @param points Array of point allocations for each voter
    /// @param nonces Array of nonces for each vote
    /// @param signatures Array of EIP-712 signatures for each vote
    function castBatchVotesWithSignature(
        address[] calldata voters,
        uint256[][] calldata points,
        uint256[] calldata nonces,
        bytes[] calldata signatures
    ) external {
        // Validate array lengths match
        if (voters.length != points.length) revert ArrayLengthMismatch();
        if (voters.length != nonces.length) revert ArrayLengthMismatch();
        if (voters.length != signatures.length) revert ArrayLengthMismatch();

        // Check batch size limit
        if (voters.length > MAX_BATCH_SIZE) {
            revert BatchTooLarge();
        }

        // Process each vote
        for (uint256 i = 0; i < voters.length; i++) {
            _castSingleVote(voters[i], points[i], nonces[i], signatures[i]);
        }

        emit BatchVotesCast(voters, nonces);
    }

    // ============ View Functions ============

    /// @notice Gets the current voting distribution for the active cycle
    /// @dev Returns the array of weighted votes for each project in the current cycle
    /// @return Array of vote weights for each project
    function getCurrentVotingDistribution() external view returns (uint256[] memory) {
        uint256 currentCycle = cycleModule().getCurrentCycle();
        return _getBasisPointsVotingModuleStorage().projectDistributions[currentCycle];
    }

    /// @notice Gets the vote distribution for a specific cycle
    /// @dev Returns the weighted vote totals for each recipient
    /// @param cycle The cycle number to check
    /// @return Array of weighted vote totals for each recipient
    function getProjectDistributions(uint256 cycle) external view returns (uint256[] memory) {
        return _getBasisPointsVotingModuleStorage().projectDistributions[cycle];
    }

    // ============ Admin Functions ============

    /// @notice Sets the maximum points that can be allocated per recipient
    /// @dev Only callable by owner
    /// @param _maxPoints The new maximum points value
    function setMaxPoints(uint256 _maxPoints) external onlyOwner {
        _getBasisPointsVotingModuleStorage().maxPoints = _maxPoints;
        emit MaxPointsSet(_maxPoints);
    }

    // ============ Internal Functions ============

    /// @notice Processes and records a vote
    /// @dev Updates project distributions and cycle voting power. Handles vote recasting by replacing previous vote.
    /// @param voter Address of the voter
    /// @param points Array of points allocated to each recipient
    /// @param votingPower Total voting power of the voter
    function _processVote(address voter, uint256[] calldata points, uint256 votingPower) internal virtual override {
        AbstractVotingModuleStorage storage base = _getAbstractVotingModuleStorage();
        BasisPointsVotingModuleStorage storage $ = _getBasisPointsVotingModuleStorage();
        uint256 currentCycle = base.cycleModule.getCurrentCycle();

        // Check if voter has already voted in this cycle and revert their previous vote
        uint256 previousVotingPower = $.voterCyclePower[currentCycle][voter];
        if (previousVotingPower > 0) {
            // Revert previous vote's impact on total voting power
            base.totalCycleVotingPower[currentCycle] -= previousVotingPower;

            // Revert previous vote's impact on project distributions
            uint256[] storage previousPoints = $.voterCyclePoints[currentCycle][voter];
            uint256 previousTotalPoints;
            for (uint256 i = 0; i < previousPoints.length; i++) {
                previousTotalPoints += previousPoints[i];
            }
            for (uint256 i = 0; i < previousPoints.length; i++) {
                uint256 previousAllocation =
                    (previousPoints[i] * previousVotingPower * PRECISION) / previousTotalPoints / PRECISION;
                $.projectDistributions[currentCycle][i] -= previousAllocation;
            }
        }

        // Apply new vote
        base.totalCycleVotingPower[currentCycle] += votingPower;

        // Compute total points for proportional allocation
        uint256 totalPoints;
        for (uint256 i = 0; i < points.length; i++) {
            totalPoints += points[i];
        }

        // Store voter's current voting power and points, and update project distributions
        $.voterCyclePower[currentCycle][voter] = votingPower;
        delete $.voterCyclePoints[currentCycle][voter]; // Clear previous points array
        for (uint256 i = 0; i < points.length; i++) {
            $.voterCyclePoints[currentCycle][voter].push(points[i]);

            // Calculate and update project distributions in same loop for gas efficiency
            uint256 allocation = (points[i] * votingPower * PRECISION) / totalPoints / PRECISION;
            if (i >= $.projectDistributions[currentCycle].length) {
                $.projectDistributions[currentCycle].push(allocation);
            } else {
                $.projectDistributions[currentCycle][i] += allocation;
            }
        }

        // Update last voted block number
        base.accountLastVotedBlock[voter] = block.number;
    }

    /// @notice Validates vote points distribution
    /// @dev Checks if points array is valid according to basis points rules
    /// @param points Array of points to validate
    /// @return True if points are valid, false otherwise
    function _validateVotePoints(uint256[] calldata points) internal view override returns (bool) {
        if (points.length == 0) return false;

        // Validate array length against recipient registry
        uint256 recipientCount = _getAbstractVotingModuleStorage().recipientRegistry.getRecipientCount();
        if (points.length != recipientCount) return false;

        uint256 _maxPoints = _getBasisPointsVotingModuleStorage().maxPoints;
        uint256 totalPoints;
        for (uint256 i = 0; i < points.length; i++) {
            if (points[i] > _maxPoints) revert ExceedsMaxPoints();
            totalPoints += points[i];
        }

        if (totalPoints == 0) revert ZeroVotePoints();

        return true;
    }

    /// @notice Processes a single vote with additional data for downstream implementations
    /// @dev Mirrors _castSingleVote but calls _processVoteWithParams to invoke the additionalData hook.
    /// @param voter Address of the voter
    /// @param points Array of points to allocate to each recipient
    /// @param nonce Unique nonce for replay protection
    /// @param signature EIP-712 signature from the voter
    /// @param additionalData Arbitrary bytes data for downstream implementations
    function _castSingleVoteWithParams(
        address voter,
        uint256[] calldata points,
        uint256 nonce,
        bytes calldata signature,
        bytes calldata additionalData
    ) internal {
        AbstractVotingModuleStorage storage $ = _getAbstractVotingModuleStorage();

        if (isNonceUsed(voter, nonce)) revert NonceAlreadyUsed();
        if (!_validateVotePoints(points)) revert InvalidPointsDistribution();
        if (!validateSignature(voter, points, nonce, signature)) revert InvalidSignature();

        $.usedNonces[voter][nonce] = true;

        uint256 votingPower = _calculateTotalVotingPower(voter);
        _processVoteWithParams(voter, points, votingPower, additionalData);

        emit VoteCastWithParams(voter, points, votingPower, nonce, signature, additionalData);
    }

    /// @notice Hook for downstream implementations to act on additional vote data
    /// @dev BasisPointsVotingModule does not use additionalData — override this in
    ///      downstream implementations that need it (e.g., multiplier indices, metadata).
    ///      Marked virtual so that subclasses can override without mutability restrictions.
    function _handleAdditionalVoteData(address, uint256[] calldata, uint256, bytes calldata) internal virtual override {
        // BasisPointsVotingModule: no-op. Override in downstream implementations.
    }

    // Issue #43: Store required votes at proposal creation in VotingRecipientRegistry
    // https://github.com/BreadchainCoop/breadkit/issues/43
    // TODO: Implement when VotingRecipientRegistry is added
    // /// @notice Gets the required number of votes for a proposal
    // /// @dev Returns the stored required votes for proposal execution
    // /// @param proposalId The ID of the proposal
    // /// @return The number of required votes
    // function getRequiredVotes(uint256 proposalId) external view override returns (uint256) {
    //     // Will be implemented when VotingRecipientRegistry is added
    //     // return votingRecipientRegistry.getRequiredVotes(proposalId);
    // }
}
