// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IRecipientRegistry} from "./IRecipientRegistry.sol";
import {ICycleModule} from "./ICycleModule.sol";

/// @title IDistributionModule
/// @notice Interface for the distribution module that manages yield distribution
/// @dev This module is responsible for orchestrating the entire distribution process across all modules
/// @author BreadKit Team
interface IDistributionModule {
    /// @notice Struct representing the current state of the distribution system
    /// @dev Contains all relevant information about the current distribution cycle
    struct DistributionState {
        /// @notice Total yield available for distribution in the current cycle
        uint256 totalYield;
        /// @notice Amount allocated to fixed distributions
        uint256 fixedAmount;
        /// @notice Amount allocated to voted distributions
        uint256 votedAmount;
        /// @notice Total number of votes cast in the current cycle
        uint256 totalVotes;
        /// @notice Block number of the last distribution
        uint256 lastDistributionBlock;
        /// @notice Current cycle number
        uint256 cycleNumber;
        /// @notice Array of recipient addresses for this distribution
        address[] recipients;
        /// @notice Array of voted distribution amounts corresponding to recipients
        uint256[] votedDistributions;
        /// @notice Array of fixed distribution amounts corresponding to recipients
        uint256[] fixedDistributions;
    }

    /// @notice Emitted when yield is distributed to recipients
    /// @param totalYield Total amount of yield distributed
    /// @param totalVotes Total number of votes cast in the distribution cycle
    /// @param recipients Array of addresses that received distributions
    /// @param votedDistributions Array of amounts distributed based on voting
    /// @param fixedDistributions Array of amounts distributed as fixed allocations
    event YieldDistributed(
        uint256 totalYield,
        uint256 totalVotes,
        address[] recipients,
        uint256[] votedDistributions,
        uint256[] fixedDistributions
    );

    /// @notice Emitted when tokens are minted for distribution purposes
    /// @param amount Number of tokens minted
    event TokensMintedForDistribution(uint256 amount);

    /// @notice Emitted when the distribution system is emergency paused
    /// @param admin Address of the admin who triggered the pause
    /// @param timestamp Block timestamp when the pause was triggered
    event EmergencyPause(address admin, uint256 timestamp);

    /// @notice Emitted when tokens are emergency withdrawn from the system
    /// @param token Address of the token being withdrawn
    /// @param to Address receiving the withdrawn tokens
    /// @param amount Amount of tokens withdrawn
    /// @param admin Address of the admin who triggered the withdrawal
    event EmergencyWithdraw(address token, address to, uint256 amount, address admin);

    /// @notice Emitted when a distribution cycle is completed
    /// @param cycleNumber The cycle number that was completed
    /// @param blockNumber Block number when the cycle was completed
    event CycleCompleted(uint256 cycleNumber, uint256 blockNumber);

    /// @notice Emitted when distribution parameters are validated
    /// @param totalYield Total yield amount that was validated
    /// @param recipientCount Number of recipients in the distribution
    event DistributionValidated(uint256 totalYield, uint256 recipientCount);

    /// @notice Distributes yield to recipients based on voting and fixed allocations
    /// @dev Orchestrates the entire distribution process including yield collection, calculation, and transfer
    /// @dev This function can only be called when distribution conditions are met (validated via validateDistribution)
    /// @dev Emits YieldDistributed and CycleCompleted events upon successful execution
    function distributeYield() external;

    /// @notice Gets the current state of the distribution system
    /// @dev Returns comprehensive information about the current distribution state
    /// @dev This is a view function that doesn't modify state
    /// @return state The current distribution state including all relevant parameters
    function getCurrentDistributionState() external view returns (DistributionState memory state);

    /// @notice Validates if distribution conditions are met
    /// @dev Checks if all prerequisites for distribution are satisfied including:
    /// @dev - Sufficient cycle time has passed
    /// @dev - There is yield available to distribute
    /// @dev - System is not paused
    /// @return canDistribute Whether distribution can proceed
    /// @return reason If cannot distribute, the reason why (empty string if can distribute)
    function validateDistribution() external view returns (bool canDistribute, string memory reason);

    /// @notice Emergency pause function to halt distributions
    /// @dev Can only be called by emergency admin
    /// @dev Prevents any new distributions from occurring until resumed
    /// @dev Emits EmergencyPause event
    function emergencyPause() external;

    /// @notice Resume distributions after emergency pause
    /// @dev Can only be called by owner
    /// @dev Re-enables distribution functionality after emergency pause
    /// @dev Should only be called after the emergency condition has been resolved
    function emergencyResume() external;

    /// @notice Sets the cycle length for distributions
    /// @dev Determines the minimum blocks between distributions
    /// @dev Can only be called by authorized admin
    /// @param _cycleLength The cycle length in blocks (must be greater than 0)
    function setCycleLength(uint256 _cycleLength) external;

    /// @notice Sets the fixed split divisor
    /// @dev Determines the portion allocated to fixed distribution vs voted distribution
    /// @dev A higher divisor means a smaller fixed allocation (fixedAmount = totalYield / divisor)
    /// @dev Can only be called by authorized admin
    /// @param _divisor The divisor for fixed split calculation (must be greater than 0)
    function setYieldFixedSplitDivisor(uint256 _divisor) external;

    /// @notice Returns the recipient registry used by this distribution module
    function recipientRegistry() external view returns (IRecipientRegistry);

    /// @notice Returns the cycle manager used by this distribution module
    function cycleManager() external view returns (ICycleModule);
}
