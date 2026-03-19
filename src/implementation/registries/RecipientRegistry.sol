// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AbstractRecipientRegistry} from "../../abstract/AbstractRecipientRegistry.sol";

/// @title RecipientRegistry
/// @notice Simple admin-controlled registry for managing yield recipients with queued changes
/// @dev Simple implementation of AbstractRecipientRegistry with admin-only queueing
/// @author BreadKit Protocol
contract RecipientRegistry is AbstractRecipientRegistry {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the registry with an admin
    /// @dev This function replaces the constructor for upgradeable contracts
    /// @dev Sets the admin as the owner who can queue recipient changes
    /// @dev Can only be called once due to the initializer modifier
    /// @param admin The address that will have administrative control over the registry
    function initialize(address admin) public initializer {
        __Ownable_init(admin);
    }

    /// @notice Queue a single recipient for addition to the registry
    /// @dev Only the admin (owner) can call this function
    /// @dev The recipient will be added when processQueue() is called
    /// @dev Validates that the recipient is not the zero address and not already active
    /// @dev Emits RecipientQueued event upon successful queuing
    /// @param recipient The address to queue for addition to the recipient list
    function queueRecipientAddition(address recipient) external onlyOwner {
        _queueForAddition(recipient);
    }

    /// @notice Queue a single recipient for removal from the registry
    /// @dev Only the admin (owner) can call this function
    /// @dev The recipient will be removed when processQueue() is called
    /// @dev Validates that the recipient is currently active and not already queued for removal
    /// @dev Emits RecipientQueued event upon successful queuing
    /// @param recipient The address to queue for removal from the recipient list
    function queueRecipientRemoval(address recipient) external onlyOwner {
        _queueForRemoval(recipient);
    }
}
