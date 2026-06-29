// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IVotingPowerStrategy
/// @notice Interface for voting power calculation strategies
/// @dev Defines the contract for different voting power calculation approaches that can be combined
interface IVotingPowerStrategy {
    /// @notice Gets the current voting power of an account
    /// @dev Returns the voting power an account currently has
    /// @param account The address to check voting power for
    /// @return The current voting power of the account
    function getCurrentVotingPower(address account) external view returns (uint256);
}
