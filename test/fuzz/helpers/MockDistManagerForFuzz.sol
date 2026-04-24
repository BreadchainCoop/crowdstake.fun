// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IRecipientRegistry} from "../../../src/interfaces/IRecipientRegistry.sol";

/// @notice Minimal stub so `EqualDistributionStrategy` can read `recipientRegistry()` at init and act as caller.
contract MockDistManagerForFuzz {
    /// @notice Auto-generated getter matches IDistributionManager.recipientRegistry() selector.
    IRecipientRegistry public immutable recipientRegistry;

    constructor(IRecipientRegistry registry_) {
        recipientRegistry = registry_;
    }
}
