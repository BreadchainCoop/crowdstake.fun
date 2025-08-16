// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IYieldModule
/// @notice Interface for the yield module that manages yield generation and distribution
/// @dev This module is responsible for handling yield accrual, minting, burning, and claiming
interface IYieldModule {
    /// @notice Mints new tokens to a specified address
    /// @dev This function creates new tokens and assigns them to the recipient
    /// @param amount The amount of tokens to mint
    /// @param receiver The address to receive the minted tokens
    function mint(uint256 amount, address receiver) external;

    /// @notice Burns tokens from the sender and sends the underlying asset to a receiver
    /// @dev This function destroys tokens and returns the equivalent amount of the underlying asset
    /// @param amount The amount of tokens to burn
    /// @param receiver The address to receive the underlying asset
    function burn(uint256 amount, address receiver) external;

    /// @notice Claims accrued yield and sends it to a specified address
    /// @dev This function allows authorized users to claim accumulated yield
    /// @param amount The amount of yield to claim
    /// @param receiver The address to receive the claimed yield
    function claimYield(uint256 amount, address receiver) external;

    /// @notice Gets the total amount of yield that has accrued
    /// @dev Returns the current amount of yield available for claiming
    /// @return The total amount of accrued yield
    function yieldAccrued() external view returns (uint256);
}
