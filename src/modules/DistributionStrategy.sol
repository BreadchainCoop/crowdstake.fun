// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../interfaces/IDistributionStrategy.sol";
import "../libraries/YieldDistributionValidator.sol";

/// @title DistributionStrategy
/// @notice Configurable yield distribution strategy that splits yield between fixed and voted portions
/// @dev The fixed portion (totalYield / divisor) is distributed equally among recipients.
///      The remainder is distributed according to voting results.
///      A divisor of 2 means 50/50 split (recommended for game-theoretical security).
/// @author BreadKit Protocol
contract DistributionStrategy is IDistributionStrategy, OwnableUpgradeable {
    using YieldDistributionValidator for uint256;

    /// @notice The divisor used to calculate the fixed portion of distribution
    /// @dev fixedAmount = totalYield / strategyDivisor
    uint256 public strategyDivisor;

    /// @notice Auto-incrementing distribution identifier (issue #47)
    uint256 public distributionCount;

    /// @notice Error thrown when divisor is zero
    error InvalidDivisor();

    /// @notice Initialize the distribution strategy
    /// @param admin The admin address
    /// @param _strategyDivisor The initial divisor (e.g., 2 for 50/50 split)
    function initialize(address admin, uint256 _strategyDivisor) public initializer {
        __Ownable_init(admin);
        if (_strategyDivisor == 0) revert InvalidDivisor();
        strategyDivisor = _strategyDivisor;
    }

    /// @inheritdoc IDistributionStrategy
    function calculateDistribution(uint256 totalYield)
        external
        override
        returns (uint256 fixedAmount, uint256 votedAmount)
    {
        (fixedAmount, votedAmount) = _calculateSplit(totalYield);

        distributionCount++;
        emit DistributionCalculated(distributionCount, totalYield, fixedAmount, votedAmount);
    }

    /// @inheritdoc IDistributionStrategy
    function previewDistribution(uint256 totalYield)
        external
        view
        override
        returns (uint256 fixedAmount, uint256 votedAmount)
    {
        return _calculateSplit(totalYield);
    }

    /// @inheritdoc IDistributionStrategy
    function updateStrategyDivisor(uint256 newDivisor) external override onlyOwner {
        if (newDivisor == 0) revert InvalidDivisor();

        uint256 oldDivisor = strategyDivisor;
        strategyDivisor = newDivisor;

        emit StrategyDivisorUpdated(oldDivisor, newDivisor);
    }

    /// @inheritdoc IDistributionStrategy
    function getStrategyDivisor() external view override returns (uint256) {
        return strategyDivisor;
    }

    /// @inheritdoc IDistributionStrategy
    function getDistributionCount() external view override returns (uint256) {
        return distributionCount;
    }

    /// @notice Internal calculation of yield split
    /// @param totalYield The total yield to split
    /// @return fixedAmount The fixed portion
    /// @return votedAmount The voted portion
    function _calculateSplit(uint256 totalYield) internal view returns (uint256 fixedAmount, uint256 votedAmount) {
        fixedAmount = totalYield / strategyDivisor;
        votedAmount = totalYield - fixedAmount;
    }
}
