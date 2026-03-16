// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ICycleModule
/// @notice Interface for the cycle module
/// @dev Simplified interface focusing only on cycle timing without distribution logic
interface ICycleModule {
    /// @notice Gets the current cycle number
    /// @return The current cycle number
    function getCurrentCycle() external view returns (uint256);

    /// @notice Checks if the current cycle has completed
    /// @return Whether the cycle timing allows for transition
    function isCycleComplete() external view returns (bool);

    /// @notice Starts a new cycle
    /// @dev Only callable by authorized contracts
    function startNewCycle() external;

    /// @notice Gets the number of blocks until the next cycle
    /// @return The number of blocks remaining in the current cycle
    function getBlocksUntilNextCycle() external view returns (uint256);

    /// @notice Gets the progress of the current cycle as a percentage
    /// @return The cycle progress (0-100)
    function getCycleProgress() external view returns (uint256);

    /// @notice Updates the cycle length for future cycles
    /// @param newCycleLength The new cycle length in blocks
    function updateCycleLength(uint256 newCycleLength) external;

    /// @notice Gets the block number when the current cycle started
    /// @return The block number when the current cycle started
    function lastCycleStartBlock() external view returns (uint256);

    /// @notice Gets the length of each cycle in blocks
    /// @return The cycle length in blocks
    function cycleLength() external view returns (uint256);
}
