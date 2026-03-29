// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IDistributionModule} from "../../src/interfaces/IDistributionModule.sol";

/// @title MockDistributionModule
/// @notice Minimal mock implementation of IDistributionModule for testing
contract MockDistributionModule is IDistributionModule {
    bool public paused;

    function distributeYield() external override {}

    function getCurrentDistributionState() external pure override returns (DistributionState memory state) {
        return state;
    }

    function validateDistribution() external pure override returns (bool canDistribute, string memory reason) {
        return (true, "");
    }

    function emergencyPause() external override {
        paused = true;
    }

    function emergencyResume() external override {
        paused = false;
    }

    function setCycleLength(uint256) external override {}

    function setYieldFixedSplitDivisor(uint256) external override {}
}
