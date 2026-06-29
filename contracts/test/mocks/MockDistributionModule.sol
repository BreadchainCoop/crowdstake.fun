// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IDistributionModule} from "../../src/interfaces/IDistributionModule.sol";
import {IRecipientRegistry} from "../../src/interfaces/IRecipientRegistry.sol";
import {ICycleModule} from "../../src/interfaces/ICycleModule.sol";

/// @title MockDistributionModule
/// @notice Minimal mock implementation of IDistributionModule for testing
contract MockDistributionModule is IDistributionModule {
    bool public paused;
    IRecipientRegistry private _recipientRegistry;
    ICycleModule private _cycleManager;

    constructor(address recipientRegistry_, address cycleManager_) {
        _recipientRegistry = IRecipientRegistry(recipientRegistry_);
        _cycleManager = ICycleModule(cycleManager_);
    }

    function recipientRegistry() external view override returns (IRecipientRegistry) {
        return _recipientRegistry;
    }

    function cycleManager() external view override returns (ICycleModule) {
        return _cycleManager;
    }

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
