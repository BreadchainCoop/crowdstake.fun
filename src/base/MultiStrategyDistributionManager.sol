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

    // ============ EIP-7201 Namespaced Storage ============

    /// @custom:storage-location erc7201:crowdstake.storage.MultiStrategyDistributionManager
    struct MultiStrategyDistributionManagerStorage {
        /// @notice Ordered list of strategies that receive yield
        IDistributionStrategy[] strategies;
    }

    // keccak256(abi.encode(uint256(keccak256("crowdstake.storage.MultiStrategyDistributionManager")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant MULTI_STRATEGY_DISTRIBUTION_MANAGER_STORAGE =
        0x49aaa156beb08cce780905870501d6964412ea46737a1bda3d65f47d87aee000;

    function _getMultiStrategyDistributionManagerStorage()
        private
        pure
        returns (MultiStrategyDistributionManagerStorage storage $)
    {
        assembly {
            $.slot := MULTI_STRATEGY_DISTRIBUTION_MANAGER_STORAGE
        }
    }

    // ============ Public Getters ============

    /// @notice Ordered list of strategies that receive yield
    function strategies(uint256 index) public view returns (IDistributionStrategy) {
        return _getMultiStrategyDistributionManagerStorage().strategies[index];
    }

    // ============ Events ============

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
        MultiStrategyDistributionManagerStorage storage $ = _getMultiStrategyDistributionManagerStorage();
        for (uint256 i = 0; i < _strategies.length; i++) {
            if (address(_strategies[i]) == address(0)) revert ZeroAddress();
            $.strategies.push(_strategies[i]);
        }
        emit StrategiesInitialized(_strategies);
    }

    /// @notice Checks if distribution is ready based on cycle completion, votes, recipients, strategies, and yield
    /// @return ready True if cycle is complete, there are votes, recipients, configured strategies, and sufficient yield
    function isDistributionReady() public view override returns (bool ready) {
        if (!cycleManager().isCycleComplete()) return false;

        uint256 totalVotes = getTotalCurrentVotingPower();
        if (totalVotes == 0) return false;

        uint256 recipientCount = recipientRegistry().getRecipientCount();
        if (recipientCount == 0) return false;

        MultiStrategyDistributionManagerStorage storage $ = _getMultiStrategyDistributionManagerStorage();
        uint256 strategyCount = $.strategies.length;
        if (strategyCount == 0) return false;

        uint256 yieldAmount = yieldModule().yieldAccrued();
        if (yieldAmount == 0) return false;

        // Require enough yield so that, after equal split across strategies,
        // each strategy can distribute at least one unit per recipient.
        uint256 minRequiredYield = recipientCount * strategyCount;
        return yieldAmount >= minRequiredYield;
    }

    /// @notice Claims yield and distributes equally to all strategies
    function claimAndDistribute() external override {
        if (!isDistributionReady()) revert DistributionNotReady();
        MultiStrategyDistributionManagerStorage storage $ = _getMultiStrategyDistributionManagerStorage();
        require($.strategies.length > 0, "No strategies configured");

        // Get the amount of yield available
        uint256 yieldAmount = yieldModule().yieldAccrued();
        if (yieldAmount == 0) revert NoYieldAvailable();

        // Claim yield to this contract
        yieldModule().claimYield(yieldAmount, address(this));
        emit YieldClaimed(yieldAmount);

        // Calculate amount per strategy (equal distribution)
        uint256 amountPerStrategy = yieldAmount / $.strategies.length;

        // Cache storage getter before loop
        IERC20 baseToken_ = baseToken();

        // Distribute to each strategy
        for (uint256 i = 0; i < $.strategies.length; i++) {
            IDistributionStrategy strategy = $.strategies[i];

            // Transfer tokens to strategy
            baseToken_.safeTransfer(address(strategy), amountPerStrategy);

            // Trigger distribution in strategy
            strategy.distribute(amountPerStrategy);

            emit YieldDistributed(address(strategy), amountPerStrategy);
        }
    }

    /// @notice Gets all configured strategies
    /// @return Array of distribution strategies
    function getStrategies() external view returns (IDistributionStrategy[] memory) {
        return _getMultiStrategyDistributionManagerStorage().strategies;
    }

    /// @notice Gets the number of configured strategies
    /// @return The number of strategies
    function getStrategyCount() external view returns (uint256) {
        return _getMultiStrategyDistributionManagerStorage().strategies.length;
    }
}
