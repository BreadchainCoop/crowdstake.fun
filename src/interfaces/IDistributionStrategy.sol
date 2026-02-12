// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IDistributionStrategy
/// @notice Interface for distribution strategy modules that determine yield split
/// @dev Defines how yield is split between fixed and voted portions
/// @author BreadKit Protocol
interface IDistributionStrategy {
    /// @notice Emitted when a distribution is calculated
    /// @param distributionId Auto-incrementing identifier for tracking (issue #47)
    /// @param totalYield Total yield being distributed
    /// @param fixedAmount Amount allocated to fixed distribution
    /// @param votedAmount Amount allocated to voted distribution
    event DistributionCalculated(
        uint256 indexed distributionId, uint256 totalYield, uint256 fixedAmount, uint256 votedAmount
    );

    /// @notice Emitted when the strategy divisor is updated
    /// @param oldDivisor Previous divisor value
    /// @param newDivisor New divisor value
    event StrategyDivisorUpdated(uint256 oldDivisor, uint256 newDivisor);

    /// @notice Calculate the distribution split for a given yield amount
    /// @param totalYield The total yield to distribute
    /// @return fixedAmount Amount for fixed (equal) distribution
    /// @return votedAmount Amount for voted distribution
    function calculateDistribution(uint256 totalYield) external returns (uint256 fixedAmount, uint256 votedAmount);

    /// @notice View version of calculateDistribution without state changes
    /// @param totalYield The total yield to distribute
    /// @return fixedAmount Amount for fixed (equal) distribution
    /// @return votedAmount Amount for voted distribution
    function previewDistribution(uint256 totalYield) external view returns (uint256 fixedAmount, uint256 votedAmount);

    /// @notice Update the distribution strategy divisor
    /// @param newDivisor The new divisor (fixedAmount = totalYield / divisor)
    function updateStrategyDivisor(uint256 newDivisor) external;

    /// @notice Get the current strategy divisor
    /// @return The current divisor
    function getStrategyDivisor() external view returns (uint256);

    /// @notice Get the current distribution identifier counter
    /// @return The current distribution ID
    function getDistributionCount() external view returns (uint256);
}
