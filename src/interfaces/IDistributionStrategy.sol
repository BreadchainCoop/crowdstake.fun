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

    /// @notice Distributes the received yield
    /// @param amount Amount of yield to distribute
    function distribute(uint256 amount) external;
}
