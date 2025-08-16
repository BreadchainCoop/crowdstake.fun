// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IAutomationModule
/// @notice Interface for the automation module that handles yield distribution automation
/// @dev This module is responsible for automating the yield distribution process
interface IAutomationModule {
    /// @notice Resolves the yield distribution based on the provided data
    /// @dev This function processes the yield distribution data and prepares it for distribution
    /// @param data The encoded data containing yield distribution information
    function resolveYieldDistribution(bytes calldata data) external;

    /// @notice Distributes the yield to the appropriate recipients
    /// @dev This function handles the actual distribution of yield to the recipients based on the resolved distribution
    function distributeYield() external;
}
