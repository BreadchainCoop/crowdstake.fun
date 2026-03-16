// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IRecipientRegistry} from "../../src/interfaces/IRecipientRegistry.sol";

/// @title MockRecipientRegistry
/// @notice Mock implementation of IRecipientRegistry for testing
contract MockRecipientRegistry is IRecipientRegistry {
    address[] public activeRecipients;
    address[] public _queuedAdditions;
    address[] public _queuedRemovals;

    mapping(address => bool) public _isRecipient;
    mapping(address => RecipientInfo) public recipientInfo;

    struct RecipientInfo {
        string name;
        string description;
        uint256 addedAt;
    }

    constructor(address[] memory _initialRecipients) {
        for (uint256 i = 0; i < _initialRecipients.length; i++) {
            activeRecipients.push(_initialRecipients[i]);
            _isRecipient[_initialRecipients[i]] = true;
            recipientInfo[_initialRecipients[i]] =
                RecipientInfo({name: "Test Recipient", description: "Test Description", addedAt: block.number});
        }
    }

    function getRecipients() external view override returns (address[] memory) {
        return activeRecipients;
    }

    function getRecipientCount() external view override returns (uint256) {
        return activeRecipients.length;
    }

    function isRecipient(address recipient) external view override returns (bool) {
        return _isRecipient[recipient];
    }

    function queueRecipientAddition(address recipient) external override {
        _queuedAdditions.push(recipient);
        emit RecipientQueued(recipient, true);
    }

    function queueRecipientRemoval(address recipient) external override {
        require(_isRecipient[recipient], "Not a recipient");
        _queuedRemovals.push(recipient);
        emit RecipientQueued(recipient, false);
    }

    function processQueue() external override {
        uint256 addedCount = 0;
        uint256 removedCount = 0;
        address[] memory addedList = new address[](_queuedAdditions.length);
        address[] memory removedList = new address[](_queuedRemovals.length);

        // Process additions
        for (uint256 i = 0; i < _queuedAdditions.length; i++) {
            address recipient = _queuedAdditions[i];
            if (!_isRecipient[recipient]) {
                activeRecipients.push(recipient);
                _isRecipient[recipient] = true;
                recipientInfo[recipient] =
                    RecipientInfo({name: "New Recipient", description: "New Description", addedAt: block.number});
                addedList[addedCount] = recipient;
                addedCount++;
                emit RecipientAdded(recipient);
            }
        }

        // Process removals
        for (uint256 i = 0; i < _queuedRemovals.length; i++) {
            address recipient = _queuedRemovals[i];
            if (_isRecipient[recipient]) {
                _isRecipient[recipient] = false;
                for (uint256 j = 0; j < activeRecipients.length; j++) {
                    if (activeRecipients[j] == recipient) {
                        activeRecipients[j] = activeRecipients[activeRecipients.length - 1];
                        activeRecipients.pop();
                        break;
                    }
                }
                removedList[removedCount] = recipient;
                removedCount++;
                emit RecipientRemoved(recipient);
            }
        }

        // Trim arrays to actual counts
        address[] memory finalAdded = new address[](addedCount);
        for (uint256 i = 0; i < addedCount; i++) {
            finalAdded[i] = addedList[i];
        }
        address[] memory finalRemoved = new address[](removedCount);
        for (uint256 i = 0; i < removedCount; i++) {
            finalRemoved[i] = removedList[i];
        }

        // Clear queues
        delete _queuedAdditions;
        delete _queuedRemovals;

        emit QueueProcessed(finalAdded, finalRemoved, activeRecipients);
    }

    function clearAdditionQueue() external override {
        delete _queuedAdditions;
    }

    function clearRemovalQueue() external override {
        delete _queuedRemovals;
    }

    function getQueuedAdditions() external view override returns (address[] memory) {
        return _queuedAdditions;
    }

    function getQueuedRemovals() external view override returns (address[] memory) {
        return _queuedRemovals;
    }

    function isQueuedForAddition(address recipient) external view override returns (bool) {
        for (uint256 i = 0; i < _queuedAdditions.length; i++) {
            if (_queuedAdditions[i] == recipient) return true;
        }
        return false;
    }

    function isQueuedForRemoval(address recipient) external view override returns (bool) {
        for (uint256 i = 0; i < _queuedRemovals.length; i++) {
            if (_queuedRemovals[i] == recipient) return true;
        }
        return false;
    }

    // Helper function for testing
    function setActiveRecipients(address[] memory _recipients) external {
        for (uint256 i = 0; i < activeRecipients.length; i++) {
            _isRecipient[activeRecipients[i]] = false;
        }
        delete activeRecipients;
        for (uint256 i = 0; i < _recipients.length; i++) {
            activeRecipients.push(_recipients[i]);
            _isRecipient[_recipients[i]] = true;
        }
    }
}
