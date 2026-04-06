// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AbstractCycleModule} from "../abstract/AbstractCycleModule.sol";

/// @title CycleModule
/// @notice Concrete implementation of the cycle module
/// @dev Extends AbstractCycleModule with any protocol-specific logic
contract CycleModule is AbstractCycleModule {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
}
