// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IVotingModule
/// @notice Interface for the voting module that manages project voting
/// @dev This module is responsible for handling voting on projects and tracking voting power
interface IVotingModule {
    /// @notice Submits a vote with points for each project
    /// @dev This function records a user's vote with points for each project
    /// @param points Array of points allocated to each project
    function vote(uint256[] calldata points) external;

    /// @notice Submits a vote with points and applies multipliers
    /// @dev This function records a user's vote with points and applies specified multipliers
    /// @param points Array of points allocated to each project
    /// @param multiplierIndices Array of indices for multipliers to apply
    function voteWithMultipliers(uint256[] calldata points, uint256[] calldata multiplierIndices) external;

    /// @notice Delegates voting power to another address
    /// @dev This function allows a user to delegate their voting power to another address
    /// @param delegatee The address to delegate voting power to
    function delegate(address delegatee) external;

    /// @notice Gets the current voting power of an account
    /// @dev Returns the total voting power an account currently has
    /// @param account The address to check voting power for
    /// @return The current voting power of the account
    function getVotingPower(address account) external view returns (uint256);

    /// @notice Gets the voting power of an account for a specific time period
    /// @dev Returns the voting power an account had during a specific time period
    /// @param account The address to check voting power for
    /// @param start The start timestamp of the period
    /// @param end The end timestamp of the period
    /// @return The voting power of the account during the specified period
    function getVotingPowerForPeriod(address account, uint256 start, uint256 end) external view returns (uint256);

    /// @notice Gets the current accumulated voting power of an account
    /// @dev Returns the total accumulated voting power an account has earned
    /// @param account The address to check accumulated voting power for
    /// @return The current accumulated voting power of the account
    function getCurrentAccumulatedVotingPower(address account) external view returns (uint256);

    /// @notice Casts a vote with points for each project
    /// @dev This function is an alias for vote() and records a user's vote with points
    /// @param points Array of points allocated to each project
    function castVote(uint256[] calldata points) external;

    /// @notice Casts a vote with points and applies multipliers
    /// @dev This function is an alias for voteWithMultipliers() and records a user's vote with points and multipliers
    /// @param points Array of points allocated to each project
    /// @param multiplierIndices Array of indices for multipliers to apply
    function castVoteWithMultipliers(uint256[] calldata points, uint256[] calldata multiplierIndices) external;

    /// @notice Gets the current distribution of votes across projects
    /// @dev Returns the current voting distribution showing how votes are allocated
    /// @return An array representing the current distribution of votes
    function getCurrentVotingDistribution() external view returns (uint256[] memory);

    /// @notice Sets the minimum required voting power to participate
    /// @dev This determines the minimum voting power needed to submit a vote
    /// @param minRequiredVotingPower The minimum voting power required
    function setMinRequiredVotingPower(uint256 minRequiredVotingPower) external;

    /// @notice Sets the maximum number of points that can be allocated
    /// @dev This determines the maximum number of points a user can allocate in a vote
    /// @param maxPoints The maximum number of points allowed
    function setMaxPoints(uint256 maxPoints) external;
}
