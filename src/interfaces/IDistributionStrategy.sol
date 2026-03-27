// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IDistributionStrategy
/// @notice Interface for distribution strategy contracts
/// @dev Strategies receive yield and distribute it according to their logic
interface IDistributionStrategy {
    /// @notice Emitted when yield is distributed to a recipient
    /// @param recipient Address receiving the distribution
    /// @param amount Amount distributed
    event Distributed(address indexed recipient, uint256 amount);

    /// @notice Emitted once per distribute() call with a unique sequential identifier
    /// @param distributionId Auto-incrementing identifier for this distribution
    event DistributionExecuted(uint256 indexed distributionId);

    /// @notice Distributes the received yield
    /// @param amount Amount of yield to distribute
    function distribute(uint256 amount) external;
}
