pragma solidity ^0.8.22;

import {IMultiplier} from "./multipliers/IMultiplier.sol";

/// @title IVotingMultipliers
/// @notice Interface for the VotingMultipliers contract
/// @dev This interface defines the structure and functions for managing voting multipliers
interface IVotingMultipliers {
    /// @notice Thrown when attempting to add a multiplier that is already allowlisted
    error MultiplierAlreadyAllowlisted();
    /// @notice Thrown when attempting to remove a multiplier that is not allowlisted
    error MultiplierNotAllowlisted();
    /// @notice Thrown when an invalid multiplier index is provided
    error InvalidMultiplierIndex();
    /// @notice Emitted when a new multiplier is added to the allowlist
    /// @param multiplier The address of the added multiplier

    event MultiplierAdded(IMultiplier indexed multiplier);
    /// @notice Emitted when a multiplier is removed from the allowlist
    /// @param multiplier The address of the removed multiplier
    event MultiplierRemoved(IMultiplier indexed multiplier);
    /// @notice Returns the multiplier at the specified index in the allowlist
    /// @param index The index of the multiplier in the allowlist
    /// @return The multiplier contract at the specified index

    function allowlistedMultipliers(uint256 index) external view returns (IMultiplier);
    /// @notice Calculates the total multiplier for a given _user
    /// @param __user The address of the _user
    /// @return The total multiplier value for the _user
    function getTotalMultipliers(address __user) external view returns (uint256);
    /// @notice Adds a multiplier to the allowlist
    /// @param _multiplier The multiplier contract to be added
    function addMultiplier(IMultiplier _multiplier) external;
    /// @notice Removes a multiplier from the allowlist
    /// @param _multiplier The multiplier contract to be removed
    function removeMultiplier(IMultiplier _multiplier) external;
}
