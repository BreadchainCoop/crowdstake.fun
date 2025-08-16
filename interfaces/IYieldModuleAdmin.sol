// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IYieldModule.sol";

/// @title IYieldModuleAdmin
/// @notice Interface for the admin functions of the yield module
/// @dev This interface contains only the admin functions that should be separated from the main yield module
interface IYieldModuleAdmin is IYieldModule {
    /// @notice Sets the address authorized to claim yield
    /// @dev This function updates the yield claimer address
    /// @param yieldClaimer The address authorized to claim yield
    function setYieldClaimer(address yieldClaimer) external;

    /// @notice Rescues tokens that were accidentally sent to the contract
    /// @dev This function allows the owner to recover tokens that were sent to the contract by mistake
    /// @param token The address of the token to rescue
    /// @param amount The amount of tokens to rescue
    function rescueToken(address token, uint256 amount) external;
}
