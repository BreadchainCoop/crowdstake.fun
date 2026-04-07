// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ICycleModule} from "../../src/interfaces/ICycleModule.sol";

/// @title MockCycleModule
/// @notice Mock implementation of ICycleModule for testing
/// @dev Allows advancing cycles manually for test scenarios
contract MockCycleModule is ICycleModule {
    uint256 private _currentCycle = 1;

    function getCurrentCycle() external view override returns (uint256) {
        return _currentCycle;
    }

    function advanceCycle() external {
        _currentCycle++;
    }

    function isCycleComplete() external view override returns (bool) {
        return true;
    }

    function startNewCycle() external override {}

    function getBlocksUntilNextCycle() external view override returns (uint256) {
        return 0;
    }

    function getCycleProgress() external view override returns (uint256) {
        return 100;
    }

    function updateCycleLength(uint256) external override {}

    function lastCycleStartBlock() external view override returns (uint256) {
        return block.number;
    }

    function cycleLength() external view override returns (uint256) {
        return 1;
    }

    function distributionManager() external view override returns (address) {
        return address(0);
    }

    function setDistributionManager(address) external override {}
}
