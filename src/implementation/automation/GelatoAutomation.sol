// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AbstractAutomation} from "../../abstract/AbstractAutomation.sol";

/// @title GelatoAutomation
/// @notice Gelato Network compatible automation implementation for yield distribution
/// @dev Implements Gelato's resolver/executor interface using AutomationBase.
///      Gelato executors call checker() to decide whether to execute, and execute()
///      to run the distribution. No authentication is required on execute() because
///      executeDistribution() is safe to call from any address (the DistributionManager
///      enforces its own access controls). If executeDistribution() reverts, Gelato
///      will retry — this is safe because the DistributionManager's cycle tracking
///      prevents double-distribution within a single cycle.
contract GelatoAutomation is AbstractAutomation {
    /// @notice Constructs the GelatoAutomation contract
    /// @param _distributionManager Address of the DistributionManager to automate
    constructor(address _distributionManager) AbstractAutomation(_distributionManager) {}

    /// @notice Gelato-compatible resolver function
    /// @dev Called by Gelato executors ( Gelato bots ) off-chain to check if
    ///      performUpkeep should be called. Returns true when a distribution is ready.
    /// @return canExec Whether execution can proceed
    /// @return execPayload The bytes payload to pass to execute() if canExec is true
    function checker() external view returns (bool canExec, bytes memory execPayload) {
        canExec = isDistributionReady();
        execPayload = canExec ? getAutomationData() : new bytes(0);
    }

    /// @notice Gelato-compatible execution function
    /// @dev Called by Gelato executors when checker() returned true. The execPayload
    ///      from checker() is passed as performData by Gelato and is intentionally
    ///      unused here — the DistributionManager has no per-call parameters.
    ///      Security: No msg.sender check is needed because executeDistribution() is
    ///      safe to call from any address; the DistributionManager enforces its own
    ///      internal invariants and prevents duplicate cycles.
    /// @param execData Encoded call data from checker() (unused — see NatSpec above)
    function execute(bytes calldata execData) external {
        // execData is unused — the distribution has no per-call parameters.
        // slither-disable-next-line unused-return
        execData;
        executeDistribution();
    }
}
