// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AbstractDistributionManager} from "../abstract/AbstractDistributionManager.sol";
import {IDistributionStrategy} from "../interfaces/IDistributionStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title MultiStrategyDistributionManager
/// @notice Concrete implementation of AbstractDistributionManager that distributes to multiple strategies equally
/// @dev Distributes yield equally across all configured strategies
contract MultiStrategyDistributionManager is AbstractDistributionManager {
    using SafeERC20 for IERC20;

    /// @notice Ordered list of strategies that receive yield
    IDistributionStrategy[] public strategies;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Emitted when the strategy set is configured during initialization
    event StrategiesInitialized(IDistributionStrategy[] strategies);

    /// @notice Initializes the MultiStrategyDistributionManager with multiple strategies
    /// @param _cycleManager Address of the cycle manager
    /// @param _recipientRegistry Address of the recipient registry
    /// @param _baseToken Address of the base token with yield
    /// @param _votingModule Address of the voting module
    /// @param _strategies Array of distribution strategies to distribute to
    function initialize(
        address _cycleManager,
        address _recipientRegistry,
        address _baseToken,
        address _votingModule,
        IDistributionStrategy[] calldata _strategies
    ) external initializer {
        // Initialize parent AbstractDistributionManager
        __AbstractDistributionManager_init(_cycleManager, _recipientRegistry, _baseToken, _votingModule);

        // Store strategies
        require(_strategies.length > 0, "No strategies provided");
        strategies = _strategies;
        emit StrategiesInitialized(_strategies);
    }

    /// @notice Checks if distribution is ready based on cycle completion, votes, recipients, strategies, and yield
    /// @return ready True if cycle is complete, there are votes, recipients, configured strategies, and sufficient yield
    function isDistributionReady() public view override returns (bool ready) {
        if (!cycleManager.isCycleComplete()) return false;

        uint256 totalVotes = getTotalCurrentVotingPower();
        if (totalVotes == 0) return false;

        uint256 recipientCount = recipientRegistry.getRecipientCount();
        if (recipientCount == 0) return false;

        uint256 strategyCount = strategies.length;
        if (strategyCount == 0) return false;

        uint256 yieldAmount = yieldModule.yieldAccrued();
        if (yieldAmount == 0) return false;

        // Require enough yield so that, after equal split across strategies,
        // each strategy can distribute at least one unit per recipient.
        uint256 minRequiredYield = recipientCount * strategyCount;
        return yieldAmount >= minRequiredYield;
    }

    /// @notice Claims yield and distributes equally to all strategies
    function claimAndDistribute() external override {
        if (!isDistributionReady()) revert DistributionNotReady();
        require(strategies.length > 0, "No strategies configured");

        // Get the amount of yield available
        uint256 yieldAmount = yieldModule.yieldAccrued();
        if (yieldAmount == 0) revert NoYieldAvailable();

        // Claim yield to this contract
        yieldModule.claimYield(yieldAmount, address(this));
        emit YieldClaimed(yieldAmount);

        // Calculate amount per strategy (equal distribution)
        uint256 amountPerStrategy = yieldAmount / strategies.length;

        // Distribute to each strategy
        for (uint256 i = 0; i < strategies.length; i++) {
            IDistributionStrategy strategy = strategies[i];

            // Transfer tokens to strategy
            baseToken.safeTransfer(address(strategy), amountPerStrategy);

            // Trigger distribution in strategy
            strategy.distribute(amountPerStrategy);

            emit YieldDistributed(address(strategy), amountPerStrategy);
        }
    }

    /// @notice Gets all configured strategies
    /// @return Array of distribution strategies
    function getStrategies() external view returns (IDistributionStrategy[] memory) {
        return strategies;
    }

    /// @notice Gets the number of configured strategies
    /// @return The number of strategies
    function getStrategyCount() external view returns (uint256) {
        return strategies.length;
    }
}
