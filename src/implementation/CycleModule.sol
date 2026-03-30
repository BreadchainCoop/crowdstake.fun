// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AbstractCycleModule} from "../abstract/AbstractCycleModule.sol";

/// @title CycleModule
/// @notice Concrete implementation of the cycle module
/// @dev Extends AbstractCycleModule. Deploy via CrowdStakeFactory using BeaconProxy pattern.
contract CycleModule is AbstractCycleModule {}
