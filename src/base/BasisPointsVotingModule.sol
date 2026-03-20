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
        uint256 maxPoints;
        /// @notice Vote distribution across projects for each cycle
        mapping(uint256 => uint256[]) projectDistributions;
        /// @notice Tracks voting power used by each voter in each cycle
        mapping(uint256 => mapping(address => uint256)) voterCyclePower;
        /// @notice Tracks points allocated by each voter in each cycle
        mapping(uint256 => mapping(address => uint256[])) voterCyclePoints;
    }

    // keccak256(abi.encode(uint256(keccak256("crowdstake.storage.BasisPointsVotingModule")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant BASIS_POINTS_VOTING_MODULE_STORAGE =
        0x36e581454c484c4e200212d5304c93307b309208c9d5c05d80ca836f1eed6600;

    function _getBasisPointsVotingModuleStorage() private pure returns (BasisPointsVotingModuleStorage storage $) {
        assembly {
            $.slot := BASIS_POINTS_VOTING_MODULE_STORAGE
        }
    }

    // ============ Public Getters ============

    function maxPoints() public view returns (uint256) {
        return _getBasisPointsVotingModuleStorage().maxPoints;
    }

    function projectDistributions(uint256 cycle, uint256 index) public view returns (uint256) {
        return _getBasisPointsVotingModuleStorage().projectDistributions[cycle][index];
    }

    function voterCyclePower(uint256 cycle, address voter) public view returns (uint256) {
        return _getBasisPointsVotingModuleStorage().voterCyclePower[cycle][voter];
    }

    function voterCyclePoints(uint256 cycle, address voter, uint256 index) public view returns (uint256) {
        return _getBasisPointsVotingModuleStorage().voterCyclePoints[cycle][voter][index];
    }

    // ============ Constructor ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        // _disableInitializers(); // Only for proxy deployments
    }

    // ============ Initialization ============

    /// @notice Initializes the basis points voting module
    function initialize(
        uint256 _maxPoints,
        IVotingPowerStrategy[] calldata _strategies,
        address _distributionModule,
        address _recipientRegistry,
        address _cycleModule
    ) external initializer {
        _getBasisPointsVotingModuleStorage().maxPoints = _maxPoints;
        __AbstractVotingModule_init(_strategies, _distributionModule, _recipientRegistry, _cycleModule);
    }

    // ============ External Functions ============

    /// @notice Casts a vote with an EIP-712 signature
    function castVoteWithSignature(address voter, uint256[] calldata points, uint256 nonce, bytes calldata signature)
        external
    {
        _castSingleVote(voter, points, nonce, signature);
    }

    /// @notice Casts multiple votes in a single transaction for gas efficiency
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
    function getCurrentVotingDistribution() external view returns (uint256[] memory) {
        uint256 currentCycle = cycleModule().getCurrentCycle();
        return _getBasisPointsVotingModuleStorage().projectDistributions[currentCycle];
    }

    /// @notice Gets the vote distribution for a specific cycle
    function getProjectDistributions(uint256 cycle) external view returns (uint256[] memory) {
        return _getBasisPointsVotingModuleStorage().projectDistributions[cycle];
    }

    // ============ Admin Functions ============

    /// @notice Sets the maximum points that can be allocated per recipient
    function setMaxPoints(uint256 _maxPoints) external onlyOwner {
        _getBasisPointsVotingModuleStorage().maxPoints = _maxPoints;
        emit MaxPointsSet(_maxPoints);
    }

    // ============ Internal Functions ============

    /// @notice Processes and records a vote
    function _processVote(address voter, uint256[] calldata points, uint256 votingPower) internal override {
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
}
