// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AbstractDistributionManager} from "../abstract/AbstractDistributionManager.sol";
import {IDistributionStrategy} from "../interfaces/IDistributionStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title BaseDistributionManager
/// @notice Concrete implementation of AbstractDistributionManager that distributes to a single strategy
/// @dev Simple manager that distributes all yield to one configured strategy
contract BaseDistributionManager is AbstractDistributionManager {
    using SafeERC20 for IERC20;

    /// @notice The single strategy that receives all claimed yield
    IDistributionStrategy public distributionStrategy;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Emitted when the distribution strategy is set or changed
    event StrategySet(address indexed strategy);

    /// @notice Initializes the BaseDistributionManager with a single distribution strategy
    /// @param _cycleManager Address of the cycle manager
    /// @param _recipientRegistry Address of the recipient registry
    /// @param _baseToken Address of the base token with yield
    /// @param _votingModule Address of the voting module
    /// @param _strategy Address of the distribution strategy to use
    function initialize(
        address _cycleManager,
        address _recipientRegistry,
        address _baseToken,
        address _votingModule,
        address _strategy
    ) external initializer {
        // Initialize parent AbstractDistributionManager
        __AbstractDistributionManager_init(_cycleManager, _recipientRegistry, _baseToken, _votingModule);

        // Set the single strategy
        if (_strategy != address(0)) {
            distributionStrategy = IDistributionStrategy(_strategy);
            emit StrategySet(_strategy);
        }
    }

    /// @notice Sets the distribution strategy
    /// @param _strategy Address of the distribution strategy
    function setDistributionStrategy(address _strategy) external onlyOwner {
        if (_strategy == address(0)) revert ZeroAddress();
        distributionStrategy = IDistributionStrategy(_strategy);
        emit StrategySet(_strategy);
    }

    /// @notice Checks if distribution is ready based on cycle completion, votes, and yield
    /// @return ready True if cycle is complete, there are votes, recipients, and sufficient yield
    function isDistributionReady() public view override returns (bool ready) {
        if (!cycleManager.isCycleComplete()) return false;

        uint256 totalVotes = getTotalCurrentVotingPower();
        if (totalVotes == 0) return false;

        uint256 recipientCount = recipientRegistry.getRecipientCount();
        if (recipientCount == 0) return false;

        return yieldModule.yieldAccrued() >= recipientCount;
    }

    /// @notice Claims yield and distributes to the configured strategy
    function claimAndDistribute() external override {
        if (!isDistributionReady()) revert DistributionNotReady();
        if (address(distributionStrategy) == address(0)) revert("No strategy set");

        // Get the amount of yield available
        uint256 yieldAmount = yieldModule.yieldAccrued();
        if (yieldAmount == 0) revert NoYieldAvailable();

        // Claim yield to this contract
        yieldModule.claimYield(yieldAmount, address(this));
        emit YieldClaimed(yieldAmount);

        // Transfer tokens to strategy
        baseToken.safeTransfer(address(distributionStrategy), yieldAmount);

        // Trigger distribution in strategy
        distributionStrategy.distribute(yieldAmount);

        emit YieldDistributed(address(distributionStrategy), yieldAmount);
    }
}
