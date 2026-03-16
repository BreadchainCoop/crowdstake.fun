// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IRecipientRegistry
/// @notice Interface for managing yield recipients with queue-based updates
/// @dev Defines the standard interface for recipient registries used in yield distribution
/// @dev Implementations may vary in access control (admin vs voting) but must support queueing
/// @author BreadKit Protocol
interface IRecipientRegistry {
    // Events
    /// @notice Emitted when a recipient is queued for addition or removal
    /// @param recipient The address being queued
    /// @param isAddition True if queued for addition, false for removal
    event RecipientQueued(address indexed recipient, bool isAddition);

    /// @notice Emitted when a recipient is successfully added to the active list
    /// @param recipient The address of the newly added recipient
    event RecipientAdded(address indexed recipient);

    /// @notice Emitted when a recipient is successfully removed from the active list
    /// @param recipient The address of the removed recipient
    event RecipientRemoved(address indexed recipient);

    /// @notice Emitted when the queue is processed and recipients are updated
    /// @param added Array of addresses that were added
    /// @param removed Array of addresses that were removed
    /// @param newRecipients Array of all active recipients after processing
    event QueueProcessed(address[] added, address[] removed, address[] newRecipients);

    // Errors
    /// @notice Thrown when attempting to use the zero address as a recipient
    error InvalidRecipient();

    /// @notice Thrown when attempting to add a recipient that already exists
    error RecipientAlreadyExists();

    /// @notice Thrown when attempting to remove a recipient that doesn't exist
    error RecipientNotFound();

    /// @notice Thrown when attempting to queue a recipient that is already queued
    error RecipientAlreadyQueued();

    /// @notice Queue a recipient for addition to the registry
    /// @dev Access control varies by implementation (admin-only vs recipient voting)
    /// @dev The recipient will be added when the queue is processed
    /// @dev Must validate that recipient is not zero address and not already active
    /// @param recipient The address to queue for addition
    function queueRecipientAddition(address recipient) external;

    /// @notice Queue a recipient for removal from the registry
    /// @dev Access control varies by implementation (admin-only vs recipient voting)
    /// @dev The recipient will be removed when the queue is processed
    /// @dev Must validate that recipient is currently active
    /// @param recipient The address to queue for removal
    function queueRecipientRemoval(address recipient) external;

    /// @notice Process all queued changes and update the active recipient list
    /// @dev Can typically be called by anyone, especially the distributor manager
    /// @dev Applies all pending additions and removals in a single transaction
    /// @dev Clears both queues after processing
    /// @dev Emits RecipientAdded/RecipientRemoved for each change and QueueProcessed at the end
    function processQueue() external;

    /// @notice Clear the addition queue without processing the changes
    /// @dev Typically restricted to admin/owner for emergency use
    /// @dev Removes all pending additions without applying them
    function clearAdditionQueue() external;

    /// @notice Clear the removal queue without processing the changes
    /// @dev Typically restricted to admin/owner for emergency use
    /// @dev Removes all pending removals without applying them
    function clearRemovalQueue() external;

    /// @notice Get all currently active recipients
    /// @dev Returns addresses that are eligible to receive yield distributions
    /// @dev This list is updated when processQueue() is called
    /// @return recipients Array of active recipient addresses
    function getRecipients() external view returns (address[] memory recipients);

    /// @notice Get all addresses currently queued for addition
    /// @dev These addresses will be added when processQueue() is called
    /// @dev Useful for frontends to show pending changes
    /// @return queuedAdditions Array of addresses queued for addition
    function getQueuedAdditions() external view returns (address[] memory queuedAdditions);

    /// @notice Get all addresses currently queued for removal
    /// @dev These addresses will be removed when processQueue() is called
    /// @dev Useful for frontends to show pending changes
    /// @return queuedRemovals Array of addresses queued for removal
    function getQueuedRemovals() external view returns (address[] memory queuedRemovals);

    /// @notice Get the total number of active recipients
    /// @dev More gas efficient than calling getRecipients().length
    /// @dev Count reflects current active recipients, not including queued changes
    /// @return count Number of currently active recipients
    function getRecipientCount() external view returns (uint256 count);

    /// @notice Check if an address is currently an active recipient
    /// @dev Returns true only for addresses in the active recipients list
    /// @dev Does not include addresses that are only queued for addition
    /// @param recipient The address to check
    /// @return isActive True if the address is an active recipient, false otherwise
    function isRecipient(address recipient) external view returns (bool isActive);

    /// @notice Check if an address is queued for addition
    /// @dev Returns true if the address will be added when processQueue() is called
    /// @dev Returns false if the address is already active or not queued
    /// @param recipient The address to check
    /// @return isQueued True if queued for addition, false otherwise
    function isQueuedForAddition(address recipient) external view returns (bool isQueued);

    /// @notice Check if an address is queued for removal
    /// @dev Returns true if the address will be removed when processQueue() is called
    /// @dev Returns false if the address is not active or not queued for removal
    /// @param recipient The address to check
    /// @return isQueued True if queued for removal, false otherwise
    function isQueuedForRemoval(address recipient) external view returns (bool isQueued);
}
