// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IRecipientRegistry} from "../../../src/interfaces/IRecipientRegistry.sol";

/// @notice Minimal stub so `EqualDistributionStrategy` can read `recipientRegistry()` at init.
contract MockDistributionManagerForFuzz {
    IRecipientRegistry public immutable recipientRegistry_;

    constructor(IRecipientRegistry registry_) {
        recipientRegistry_ = registry_;
    }

    function recipientRegistry() external view returns (IRecipientRegistry) {
        return recipientRegistry_;
    }
}
