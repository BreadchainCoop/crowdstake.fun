// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AbstractRecipientRegistry} from "../../abstract/AbstractRecipientRegistry.sol";

/// @title AdminRecipientRegistry
/// @notice Admin-controlled registry for managing yield recipients with queue-based updates
/// @dev Admin can queue recipients for addition/removal, distributor manager processes the queue
/// @dev This implementation provides centralized control where only the admin can modify recipients
/// @author BreadKit Protocol
contract AdminRecipientRegistry is AbstractRecipientRegistry {
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

    /// @notice Queue multiple recipients for addition in a single transaction
    /// @dev Only the admin (owner) can call this function
    /// @dev More gas efficient than calling queueRecipientAddition multiple times
    /// @dev Each recipient is validated individually, failure of one stops the entire transaction
    /// @dev Emits a RecipientQueued event for each successfully queued recipient
    /// @param _recipients Array of addresses to queue for addition to the recipient list
    function queueRecipientsAddition(address[] calldata _recipients) external onlyOwner {
        for (uint256 i = 0; i < _recipients.length; i++) {
            _queueForAddition(_recipients[i]);
        }
    }

    /// @notice Queue multiple recipients for removal in a single transaction
    /// @dev Only the admin (owner) can call this function
    /// @dev More gas efficient than calling queueRecipientRemoval multiple times
    /// @dev Each recipient is validated individually, failure of one stops the entire transaction
    /// @dev Emits a RecipientQueued event for each successfully queued recipient
    /// @param _recipients Array of addresses to queue for removal from the recipient list
    function queueRecipientsRemoval(address[] calldata _recipients) external onlyOwner {
        for (uint256 i = 0; i < _recipients.length; i++) {
            _queueForRemoval(_recipients[i]);
        }
    }

    /// @notice Transfer administrative control to a new address
    /// @dev Only the current admin (owner) can call this function
    /// @dev The new admin will have full control over queuing recipients
    /// @dev This action is irreversible, the current admin loses all control
    /// @dev Uses OpenZeppelin's transferOwnership which includes zero address validation
    /// @param newAdmin The address that will become the new admin of the registry
    function transferAdmin(address newAdmin) external onlyOwner {
        transferOwnership(newAdmin);
    }
}
