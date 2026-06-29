// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IRecipientRegistry} from "./IRecipientRegistry.sol";
import {ICycleModule} from "./ICycleModule.sol";
import {IVotingModule} from "./IVotingModule.sol";

/// @title IDistributionManager
/// @notice Interface for managing distribution readiness and execution
/// @dev Handles distribution state and execution logic with error and event definitions
interface IDistributionManager {
    /// @notice Thrown when a zero address is provided where it's not allowed
    error ZeroAddress();

    /// @notice Thrown when distribution conditions are not met
    /// @dev Distribution is not ready when cycle is incomplete, there are no recipients,
    ///      or yield is insufficient. Note: MultiStrategyDistributionManager allows
    ///      zero-voter distributions for fixed-grant use cases.
    error DistributionNotReady();

    /// @notice Thrown when there is no yield available to distribute
    error NoYieldAvailable();

    /// @notice Thrown when an invalid amount (0) is provided
    error InvalidAmount();

    /// @notice Emitted when yield is claimed from the yield module
    /// @param amount The amount of yield claimed
    event YieldClaimed(uint256 amount);

    /// @notice Emitted when yield is distributed to a strategy
    /// @param strategy The address of the strategy that received the yield
    /// @param amount The amount of yield distributed
    event YieldDistributed(address indexed strategy, uint256 amount);

    /// @notice Checks if the distribution is ready to be executed
    /// @dev Contains all logic to determine if conditions are met
    /// @return ready Whether the distribution conditions are met
    function isDistributionReady() external view returns (bool ready);

    /// @notice Claims yield from the base token and distributes it
    /// @dev Implementation varies by concrete manager type
    function claimAndDistribute() external;

    /// @notice Returns the recipient registry used by this distribution manager
    function recipientRegistry() external view returns (IRecipientRegistry);

    /// @notice Returns the cycle manager used by this distribution manager
    function cycleManager() external view returns (ICycleModule);

    /// @notice Returns the voting module used by this distribution manager
    function votingModule() external view returns (IVotingModule);
}
