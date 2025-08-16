// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IDistributionModule
/// @notice Interface for the distribution module that manages yield distribution
/// @dev This module is responsible for distributing yield to projects based on voting results
interface IDistributionModule {
    /// @notice Distributes yield to projects based on current voting distribution
    /// @dev This function calculates and executes the distribution of yield to projects
    function distribute() external;

    /// @notice Gets the current distribution of votes across projects
    /// @dev Returns the current voting distribution that will be used for yield distribution
    /// @return An array representing the current distribution of votes
    function getCurrentDistribution() external view returns (uint256[] memory);

    /// @notice Sets the length of a distribution cycle
    /// @dev This determines how long each distribution cycle lasts
    /// @param cycleLength The length of the cycle in seconds
    function setCycleLength(uint256 cycleLength) external;

    /// @notice Sets the divisor used for fixed yield splits
    /// @dev This determines how much of the yield is allocated to fixed distribution vs. voting-based
    /// @param yieldFixedSplitDivisor The divisor value for fixed yield splits
    function setYieldFixedSplitDivisor(uint256 yieldFixedSplitDivisor) external;

    /// @notice Sets the AMM voting power module address
    /// @dev This connects the distribution module to the AMM voting power module
    /// @param ammVotingPower The address of the AMM voting power module
    function setAMMVotingPower(address ammVotingPower) external;
}
