// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AbstractAutomation} from "../../abstract/AbstractAutomation.sol";

/// @title GelatoAutomation
/// @notice Gelato Network compatible automation implementation
/// @dev Implements Gelato automation interface for yield distribution.
///      No auth is required on execute() — the DistributionManager enforces
///      its own access controls and condition checks, so any caller
///      (including Gelato executors) can safely trigger execution.
contract GelatoAutomation is AbstractAutomation {
    constructor(address _distributionManager) AbstractAutomation(_distributionManager) {}

    /// @notice Gelato-compatible resolver function
    /// @dev Called by Gelato executors to check if work needs to be performed
    /// @return canExec Whether execution can proceed
    /// @return execPayload The calldata to execute
    function checker() external view returns (bool canExec, bytes memory execPayload) {
        canExec = isDistributionReady();
        execPayload = canExec ? abi.encodeCall(this.execute, ("")) : new bytes(0);
    }

    /// @notice Gelato-compatible execution function
    /// @dev Called by Gelato executors when checker returns true.
    ///      No auth guard is needed here — DistributionManager.claimAndDistribute()
    ///      enforces its own readiness checks via isDistributionReady().
    function execute(
        bytes calldata /* execData */
    )
        external
    {
        executeDistribution();
    }
}
