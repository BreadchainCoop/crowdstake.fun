// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TestWrapper} from "./TestWrapper.sol";
import {AdminRecipientRegistry} from "../src/implementation/registries/AdminRecipientRegistry.sol";

contract AdminRecipientRegistryTest is TestWrapper {
    AdminRecipientRegistry public registry;

    address public constant ADMIN = address(0xAD);
    address public constant RECIPIENT_1 = address(0x1);
    address public constant RECIPIENT_2 = address(0x2);
    address public constant RECIPIENT_3 = address(0x3);
    address public constant RECIPIENT_4 = address(0x4);

    event RecipientAdded(address indexed recipient);
    event RecipientRemoved(address indexed recipient);
    event RecipientQueued(address indexed recipient, bool isAddition);
    event QueueProcessed(address[] added, address[] removed, address[] newRecipients);

    function setUp() public {
        registry = new AdminRecipientRegistry();
        registry.initialize(ADMIN);
    }

    function test_Initialize() public view {
        assertEq(registry.owner(), ADMIN);
        assertEq(registry.getRecipientCount(), 0);
    }

    function test_QueueAndUpdateRecipient() public {
        vm.prank(ADMIN);
        vm.expectEmit(true, false, false, false);
        emit RecipientQueued(RECIPIENT_1, true);
        registry.queueRecipientAddition(RECIPIENT_1);

        assertTrue(registry.isQueuedForAddition(RECIPIENT_1));
        assertFalse(registry.isRecipient(RECIPIENT_1));

        address[] memory expectedAdded = new address[](1);
        expectedAdded[0] = RECIPIENT_1;
        address[] memory expectedRemoved = new address[](0);
        address[] memory expectedNew = new address[](1);
        expectedNew[0] = RECIPIENT_1;

        vm.expectEmit(true, false, false, false);
        emit RecipientAdded(RECIPIENT_1);
        vm.expectEmit(false, false, false, true);
        emit QueueProcessed(expectedAdded, expectedRemoved, expectedNew);
        registry.processQueue();

        assertTrue(registry.isRecipient(RECIPIENT_1));
        assertEq(registry.getRecipientCount(), 1);
        assertFalse(registry.isQueuedForAddition(RECIPIENT_1));

        address[] memory recipients = registry.getRecipients();
        assertEq(recipients.length, 1);
        assertEq(recipients[0], RECIPIENT_1);
    }

    function test_QueueMultipleRecipients() public {
        address[] memory toAdd = new address[](3);
        toAdd[0] = RECIPIENT_1;
        toAdd[1] = RECIPIENT_2;
        toAdd[2] = RECIPIENT_3;

        vm.prank(ADMIN);
        registry.queueRecipientsAddition(toAdd);

        assertTrue(registry.isQueuedForAddition(RECIPIENT_1));
        assertTrue(registry.isQueuedForAddition(RECIPIENT_2));
        assertTrue(registry.isQueuedForAddition(RECIPIENT_3));

        registry.processQueue();

        assertEq(registry.getRecipientCount(), 3);
        assertTrue(registry.isRecipient(RECIPIENT_1));
        assertTrue(registry.isRecipient(RECIPIENT_2));
        assertTrue(registry.isRecipient(RECIPIENT_3));
    }

    function test_QueueAndRemoveRecipient() public {
        vm.startPrank(ADMIN);
        registry.queueRecipientAddition(RECIPIENT_1);
        registry.queueRecipientAddition(RECIPIENT_2);
        registry.processQueue();

        vm.expectEmit(true, false, false, false);
        emit RecipientQueued(RECIPIENT_1, false);
        registry.queueRecipientRemoval(RECIPIENT_1);

        address[] memory expectedAdded = new address[](0);
        address[] memory expectedRemoved = new address[](1);
        expectedRemoved[0] = RECIPIENT_1;
        address[] memory expectedNew = new address[](1);
        expectedNew[0] = RECIPIENT_2;

        vm.expectEmit(true, false, false, false);
        emit RecipientRemoved(RECIPIENT_1);
        vm.expectEmit(false, false, false, true);
        emit QueueProcessed(expectedAdded, expectedRemoved, expectedNew);
        registry.processQueue();
        vm.stopPrank();

        assertFalse(registry.isRecipient(RECIPIENT_1));
        assertTrue(registry.isRecipient(RECIPIENT_2));
        assertEq(registry.getRecipientCount(), 1);
    }

    function test_QueueMultipleRemoval() public {
        vm.startPrank(ADMIN);

        // Add recipients
        address[] memory toAdd = new address[](4);
        toAdd[0] = RECIPIENT_1;
        toAdd[1] = RECIPIENT_2;
        toAdd[2] = RECIPIENT_3;
        toAdd[3] = RECIPIENT_4;
        registry.queueRecipientsAddition(toAdd);
        registry.processQueue();

        // Remove some
        address[] memory toRemove = new address[](2);
        toRemove[0] = RECIPIENT_1;
        toRemove[1] = RECIPIENT_3;
        registry.queueRecipientsRemoval(toRemove);
        registry.processQueue();

        vm.stopPrank();

        assertFalse(registry.isRecipient(RECIPIENT_1));
        assertTrue(registry.isRecipient(RECIPIENT_2));
        assertFalse(registry.isRecipient(RECIPIENT_3));
        assertTrue(registry.isRecipient(RECIPIENT_4));
        assertEq(registry.getRecipientCount(), 2);
    }

    function test_RevertOnInvalidRecipient() public {
        vm.prank(ADMIN);
        vm.expectRevert();
        registry.queueRecipientAddition(address(0));
    }

    function test_RevertOnDuplicateRecipient() public {
        vm.startPrank(ADMIN);
        registry.queueRecipientAddition(RECIPIENT_1);
        registry.processQueue();

        vm.expectRevert();
        registry.queueRecipientAddition(RECIPIENT_1);
        vm.stopPrank();
    }

    function test_RevertOnRemovingNonExistent() public {
        vm.prank(ADMIN);
        vm.expectRevert();
        registry.queueRecipientRemoval(RECIPIENT_1);
    }

    function test_OnlyAdminCanQueue() public {
        vm.prank(address(0xdead));
        vm.expectRevert();
        registry.queueRecipientAddition(RECIPIENT_1);
    }

    function test_OnlyAdminCanQueueRemoval() public {
        vm.prank(ADMIN);
        registry.queueRecipientAddition(RECIPIENT_1);
        registry.processQueue();

        vm.prank(address(0xdead));
        vm.expectRevert();
        registry.queueRecipientRemoval(RECIPIENT_1);
    }

    function test_TransferAdmin() public {
        address newAdmin = address(0xBEEF);

        vm.prank(ADMIN);
        registry.transferAdmin(newAdmin);

        assertEq(registry.owner(), newAdmin);

        // New admin can queue
        vm.prank(newAdmin);
        registry.queueRecipientAddition(RECIPIENT_1);
        registry.processQueue();
        assertTrue(registry.isRecipient(RECIPIENT_1));

        // Old admin cannot
        vm.prank(ADMIN);
        vm.expectRevert();
        registry.queueRecipientAddition(RECIPIENT_2);
    }

    function test_LargeScaleOperations() public {
        vm.startPrank(ADMIN);

        // Queue many recipients
        uint256 count = 100;
        for (uint256 i = 1; i <= count; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            registry.queueRecipientAddition(address(uint160(i)));
        }

        registry.processQueue();
        assertEq(registry.getRecipientCount(), count);

        // Queue half for removal
        for (uint256 i = 1; i <= 50; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            registry.queueRecipientRemoval(address(uint160(i)));
        }

        registry.processQueue();
        assertEq(registry.getRecipientCount(), 50);

        vm.stopPrank();
    }
}
