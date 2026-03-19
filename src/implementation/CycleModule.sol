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

    /// @notice Initializes the cycle module
    /// @param _cycleLength The length of each cycle in blocks
    /// @param _owner The owner/admin of this module
    function initialize(uint256 _cycleLength, address _owner) external initializer {
        __AbstractCycleModule_init(_cycleLength, _owner);
    }
}
