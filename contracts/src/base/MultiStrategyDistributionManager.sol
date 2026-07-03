// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AbstractDistributionManager} from "../abstract/AbstractDistributionManager.sol";
import {IDistributionStrategy} from "../interfaces/IDistributionStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

/// @title MultiStrategyDistributionManager
/// @notice Concrete implementation of AbstractDistributionManager that distributes to multiple strategies equally
/// @dev Distributes yield equally across all configured strategies
contract MultiStrategyDistributionManager is AbstractDistributionManager, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

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

    /// @notice Emitted when the strategy set is (re)configured via setStrategies
    event StrategiesSet(IDistributionStrategy[] strategies);

    /// @notice Thrown when configuring an empty strategy set via setStrategies
    error NoStrategies();

    /// @notice Initializes the MultiStrategyDistributionManager with multiple strategies
    /// @param _cycleManager Address of the cycle manager
    /// @param _recipientRegistry Address of the recipient registry
    /// @param _baseToken Address of the base token with yield
    /// @param _votingModule Address of the voting module
    /// @param _strategies Array of distribution strategies to distribute to. May be empty
    ///        when the caller wires strategies afterwards via {setStrategies} — this breaks
    ///        the manager<->strategy circular dependency during one-tx deploys, since a
    ///        strategy needs this manager's address at its own init.
    /// @param _owner Address that will own this contract (receives onlyOwner privileges)
    function initialize(
        address _cycleManager,
        address _recipientRegistry,
        address _baseToken,
        address _votingModule,
        IDistributionStrategy[] calldata _strategies,
        address _owner
    ) external initializer {
        // Initialize parent AbstractDistributionManager
        __AbstractDistributionManager_init(_cycleManager, _recipientRegistry, _baseToken, _votingModule, _owner);
        __ReentrancyGuard_init();

        // Store strategies (may be empty; isDistributionReady() guards a zero-strategy manager).
        MultiStrategyDistributionManagerStorage storage $ = _getMultiStrategyDistributionManagerStorage();
        for (uint256 i = 0; i < _strategies.length; i++) {
            if (address(_strategies[i]) == address(0)) revert ZeroAddress();
            $.strategies.push(_strategies[i]);
        }
        emit StrategiesInitialized(_strategies);
    }

    /// @notice Replaces the configured strategy set. Owner-only.
    /// @dev Mirrors {BaseDistributionManager-setDistributionStrategy}: lets a deployer wire
    ///      strategies after both this manager and its strategies exist (the strategies
    ///      reference this manager at their own init, so they must be deployed afterwards).
    /// @param _strategies The new, non-empty strategy set (no zero addresses).
    function setStrategies(IDistributionStrategy[] calldata _strategies) external onlyOwner {
        if (_strategies.length == 0) revert NoStrategies();
        MultiStrategyDistributionManagerStorage storage $ = _getMultiStrategyDistributionManagerStorage();
        delete $.strategies;
        for (uint256 i = 0; i < _strategies.length; i++) {
            if (address(_strategies[i]) == address(0)) revert ZeroAddress();
            $.strategies.push(_strategies[i]);
        }
        emit StrategiesSet(_strategies);
    }

    /// @notice Checks if conditions are met for distribution (cycle complete, recipients configured, sufficient yield)
    /// @return ready True if cycle is complete, there are recipients, configured strategies, and sufficient yield
    /// @dev Allows zero-voter distributions for small communities (matches breadchain contracts)
    function isDistributionReady() public view override returns (bool ready) {
        if (cycleManager().distributionManager() != address(this)) return false;
        if (!cycleManager().isCycleComplete()) return false;

        // Allow zero-voter distributions — small communities may legitimately have no votes
        // but still want to distribute to recipients (e.g., fixed grants).
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
    function claimAndDistribute() external override nonReentrant {
        if (!isDistributionReady()) revert DistributionNotReady();
        MultiStrategyDistributionManagerStorage storage $ = _getMultiStrategyDistributionManagerStorage();

        // Get the amount of yield available
        uint256 yieldAmount = yieldModule().yieldAccrued();
        if (yieldAmount == 0) revert NoYieldAvailable();

        // Claim yield to this contract
        yieldModule().claimYield(yieldAmount, address(this));
        emit YieldClaimed(yieldAmount);

        // Calculate amount per strategy (equal distribution); last strategy absorbs dust
        uint256 amountPerStrategy = yieldAmount / $.strategies.length;
        uint256 remainder = yieldAmount - (amountPerStrategy * ($.strategies.length - 1));

        // Cache storage getter before loop
        IERC20 baseToken_ = baseToken();

        // Distribute to each strategy; last one gets the remainder
        for (uint256 i = 0; i < $.strategies.length - 1; i++) {
            IDistributionStrategy strategy = $.strategies[i];

            // Transfer tokens to strategy
            baseToken_.safeTransfer(address(strategy), amountPerStrategy);

            // Trigger distribution in strategy
            strategy.distribute(amountPerStrategy);

            emit YieldDistributed(address(strategy), amountPerStrategy);
        }
        // Last strategy absorbs rounding dust
        IDistributionStrategy lastStrategy = $.strategies[$.strategies.length - 1];
        baseToken_.safeTransfer(address(lastStrategy), remainder);
        lastStrategy.distribute(remainder);
        emit YieldDistributed(address(lastStrategy), remainder);

        // Advance cycle atomically with distribution
        cycleManager().startNewCycle();
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
