// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AbstractAutomation} from "../../abstract/AbstractAutomation.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";

/// @title ChainlinkAutomation
/// @notice Chainlink Keeper compatible automation implementation
/// @dev Implements Chainlink automation interface for yield distribution
contract ChainlinkAutomation is AbstractAutomation, AutomationCompatibleInterface {
    constructor(address _distributionManager) AbstractAutomation(_distributionManager) {}

    /// @notice Chainlink-compatible upkeep check
    /// @dev Called by Chainlink nodes to check if work needs to be performed
    /// @dev checkData is not used but required by Chainlink interface
    /// @return upkeepNeeded Whether upkeep is needed
    /// @return performData The data to pass to performUpkeep
    function checkUpkeep(
        bytes calldata /* checkData */
    )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        upkeepNeeded = isDistributionReady();
        performData = upkeepNeeded ? getAutomationData() : new bytes(0);
    }

    /// @notice Chainlink-compatible upkeep execution
    /// @dev Called by Chainlink nodes when checkUpkeep returns true
    /// @dev performData is not used
    function performUpkeep(
        bytes calldata /* performData */
    )
        external
        override
    {
        executeDistribution();
    }
}
