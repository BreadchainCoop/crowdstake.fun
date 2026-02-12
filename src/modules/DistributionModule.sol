// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "../interfaces/IDistributionModule.sol";
import "../interfaces/IRecipientRegistry.sol";
import "../interfaces/IDistributionStrategy.sol";
import "../interfaces/IBreadKitToken.sol";
import "../libraries/YieldDistributionValidator.sol";

/// @title DistributionModule
/// @notice Central orchestrator for yield collection and distribution (issue #10)
/// @dev Coordinates yield claiming, strategy calculation, and recipient transfers
/// @author BreadKit Protocol
contract DistributionModule is IDistributionModule, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using YieldDistributionValidator for uint256;

    /// @notice The yield-bearing token
    IBreadKitToken public token;

    /// @notice The recipient registry
    IRecipientRegistry public recipientRegistry;

    /// @notice The distribution strategy
    IDistributionStrategy public distributionStrategy;

    /// @notice The voting distribution data (externally set from VotingModule)
    uint256[] public votedDistributions;

    /// @notice Cycle length in blocks
    uint256 public cycleLength;

    /// @notice Block number of last distribution
    uint256 public lastDistributionBlock;

    /// @notice Current cycle number
    uint256 public currentCycle;

    /// @notice Whether the system is paused
    bool public paused;

    /// @notice Emergency admin address
    address public emergencyAdmin;

    // Errors
    error NotReady();
    error Paused();
    error NotEmergencyAdmin();
    error InvalidCycleLength();
    error InvalidDivisor();
    error NoYieldAvailable();
    error ZeroRecipients();

    /// @notice Initialize the distribution module
    /// @param admin Admin address
    /// @param _token The yield-bearing token
    /// @param _recipientRegistry The recipient registry
    /// @param _distributionStrategy The distribution strategy
    /// @param _cycleLength Cycle length in blocks
    function initialize(
        address admin,
        address _token,
        address _recipientRegistry,
        address _distributionStrategy,
        uint256 _cycleLength
    ) public initializer {
        __Ownable_init(admin);
        __ReentrancyGuard_init();

        if (_cycleLength == 0) revert InvalidCycleLength();

        token = IBreadKitToken(_token);
        recipientRegistry = IRecipientRegistry(_recipientRegistry);
        distributionStrategy = IDistributionStrategy(_distributionStrategy);
        cycleLength = _cycleLength;
        lastDistributionBlock = block.number;
        currentCycle = 1;
    }

    /// @inheritdoc IDistributionModule
    function distributeYield() external override nonReentrant {
        if (paused) revert Paused();
        if (block.number < lastDistributionBlock + cycleLength) revert NotReady();

        address[] memory recipients = recipientRegistry.getRecipients();
        if (recipients.length == 0) revert ZeroRecipients();

        uint256 totalYield = token.yieldAccrued();
        if (totalYield == 0) revert NoYieldAvailable();

        // Validate yield is distributable (issue #38)
        YieldDistributionValidator.validateYieldDistribution(totalYield, recipients.length);

        // Calculate distribution split
        (uint256 fixedAmount, uint256 votedAmount) = distributionStrategy.calculateDistribution(totalYield);

        // Calculate fixed distributions (equal split)
        uint256[] memory fixedDistributions = new uint256[](recipients.length);
        uint256 fixedPerRecipient = fixedAmount / recipients.length;
        for (uint256 i = 0; i < recipients.length; i++) {
            fixedDistributions[i] = fixedPerRecipient;
        }

        // Calculate voted distributions
        uint256[] memory votedDists = new uint256[](recipients.length);
        uint256 totalVotedWeight = 0;
        for (uint256 i = 0; i < votedDistributions.length && i < recipients.length; i++) {
            totalVotedWeight += votedDistributions[i];
        }

        if (totalVotedWeight > 0) {
            for (uint256 i = 0; i < recipients.length; i++) {
                uint256 weight = i < votedDistributions.length ? votedDistributions[i] : 0;
                votedDists[i] = (votedAmount * weight) / totalVotedWeight;
            }
        } else {
            // If no votes, distribute voted portion equally too
            uint256 votedPerRecipient = votedAmount / recipients.length;
            for (uint256 i = 0; i < recipients.length; i++) {
                votedDists[i] = votedPerRecipient;
            }
        }

        // Claim yield and distribute
        uint256 totalDistributed = 0;
        for (uint256 i = 0; i < recipients.length; i++) {
            uint256 amount = fixedDistributions[i] + votedDists[i];
            if (amount > 0) {
                token.claimYield(amount, recipients[i]);
                totalDistributed += amount;
            }
        }

        // Update state
        lastDistributionBlock = block.number;
        currentCycle++;

        // Process any pending recipient changes
        recipientRegistry.processQueue();

        emit YieldDistributed(totalYield, totalVotedWeight, recipients, votedDists, fixedDistributions);
        emit CycleCompleted(currentCycle - 1, block.number);
    }

    /// @inheritdoc IDistributionModule
    function getCurrentDistributionState() external view override returns (DistributionState memory state) {
        address[] memory recipients = recipientRegistry.getRecipients();
        uint256 totalYield = token.yieldAccrued();

        (uint256 fixedAmount, uint256 votedAmount) = distributionStrategy.previewDistribution(totalYield);

        uint256 totalVotes = 0;
        for (uint256 i = 0; i < votedDistributions.length; i++) {
            totalVotes += votedDistributions[i];
        }

        state = DistributionState({
            totalYield: totalYield,
            fixedAmount: fixedAmount,
            votedAmount: votedAmount,
            totalVotes: totalVotes,
            lastDistributionBlock: lastDistributionBlock,
            cycleNumber: currentCycle,
            recipients: recipients,
            votedDistributions: votedDistributions,
            fixedDistributions: new uint256[](recipients.length)
        });
    }

    /// @inheritdoc IDistributionModule
    function validateDistribution() external view override returns (bool canDistribute, string memory reason) {
        if (paused) return (false, "System is paused");
        if (block.number < lastDistributionBlock + cycleLength) return (false, "Cycle not complete");

        address[] memory recipients = recipientRegistry.getRecipients();
        if (recipients.length == 0) return (false, "No recipients");

        uint256 totalYield = token.yieldAccrued();
        if (totalYield == 0) return (false, "No yield available");
        if (totalYield < recipients.length) return (false, "Yield too small for recipients");

        return (true, "");
    }

    /// @inheritdoc IDistributionModule
    function emergencyPause() external override {
        if (msg.sender != emergencyAdmin && msg.sender != owner()) revert NotEmergencyAdmin();
        paused = true;
        emit EmergencyPause(msg.sender, block.timestamp);
    }

    /// @inheritdoc IDistributionModule
    function emergencyResume() external override onlyOwner {
        paused = false;
    }

    /// @inheritdoc IDistributionModule
    function setCycleLength(uint256 _cycleLength) external override onlyOwner {
        if (_cycleLength == 0) revert InvalidCycleLength();
        cycleLength = _cycleLength;
    }

    /// @inheritdoc IDistributionModule
    function setYieldFixedSplitDivisor(uint256 _divisor) external override onlyOwner {
        if (_divisor == 0) revert InvalidDivisor();
        distributionStrategy.updateStrategyDivisor(_divisor);
    }

    /// @notice Set the voted distributions from the voting module
    /// @param _votedDistributions Array of vote weights per recipient
    function setVotedDistributions(uint256[] calldata _votedDistributions) external onlyOwner {
        votedDistributions = _votedDistributions;
    }

    /// @notice Set the emergency admin
    /// @param _emergencyAdmin The new emergency admin address
    function setEmergencyAdmin(address _emergencyAdmin) external onlyOwner {
        emergencyAdmin = _emergencyAdmin;
    }
}
