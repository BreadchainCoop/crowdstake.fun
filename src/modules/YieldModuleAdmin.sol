// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "../interfaces/IYieldModuleAdmin.sol";

/// @title YieldModuleAdmin
/// @notice Admin extension of the yield module that adds administrative functions
/// @dev This module inherits from YieldModule and adds admin-only functions
abstract contract YieldModuleAdmin is IYieldModuleAdmin, OwnableUpgradeable {
    /// @notice The address authorized to claim yield
    address public yieldClaimer;

    /// @notice Initializes the contract
    /// @dev Sets up the initial state of the contract
    function initialize() public initializer {
        __Ownable_init(msg.sender);
    }

    /// @notice Sets the address authorized to claim yield
    /// @dev This function can only be called by the owner
    /// @param _yieldClaimer The address authorized to claim yield
    function setYieldClaimer(address _yieldClaimer) external onlyOwner {
        require(_yieldClaimer != address(0), "YieldModuleAdmin: zero address");
        yieldClaimer = _yieldClaimer;
        emit YieldClaimerUpdated(_yieldClaimer);
    }

    /// @notice Rescues tokens that were accidentally sent to the contract
    /// @dev This function can only be called by the owner
    /// @param token The address of the token to rescue
    /// @param amount The amount of tokens to rescue
    function rescueToken(address token, uint256 amount) external onlyOwner {
        require(token != address(0), "YieldModuleAdmin: zero address");
        require(amount > 0, "YieldModuleAdmin: zero amount");
        IERC20(token).transfer(owner(), amount);
        emit TokenRescued(token, amount);
    }

    /// @notice Event emitted when the yield claimer is updated
    /// @param newYieldClaimer The new yield claimer address
    event YieldClaimerUpdated(address indexed newYieldClaimer);

    /// @notice Event emitted when tokens are rescued
    /// @param token The address of the rescued token
    /// @param amount The amount of tokens rescued
    event TokenRescued(address indexed token, uint256 amount);
}
