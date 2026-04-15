// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TestWrapper} from "./TestWrapper.sol";
import {RecipientRegistry} from "../src/implementation/registries/RecipientRegistry.sol";
import {IRecipientRegistry} from "../src/interfaces/IRecipientRegistry.sol";

contract RecipientRegistryTest is TestWrapper {
    RecipientRegistry public registry;

    address public constant RECIPIENT_1 = address(0x1);
    address public constant RECIPIENT_2 = address(0x2);
    address public constant RECIPIENT_3 = address(0x3);
    address public constant RECIPIENT_4 = address(0x4);

    function setUp() public {
        registry = new RecipientRegistry();
        registry.initialize(address(this));
    }

    function test_WhenInitializing() external view {
        // it should set owner and zero recipients
        assertEq(registry.owner(), address(this));
        assertEq(registry.getRecipientCount(), 0);
    }

    // ── when queuing a recipient for addition ──

    function test_GivenTheRecipientIsValid() external {
        // it should add to queue and emit RecipientQueued
        vm.expectEmit(true, true, false, true);
        emit IRecipientRegistry.RecipientQueued(RECIPIENT_1, true);

        registry.queueRecipientAddition(RECIPIENT_1);

        address[] memory queued = registry.getQueuedAdditions();
        assertEq(queued.length, 1);
        assertEq(queued[0], RECIPIENT_1);
        assertTrue(registry.isQueuedForAddition(RECIPIENT_1));
    }

    function test_GivenTheRecipientIsValid_ShouldSupportMultipleAdditions() external {
        // it should support multiple additions
        registry.queueRecipientAddition(RECIPIENT_1);
        registry.queueRecipientAddition(RECIPIENT_2);
        registry.queueRecipientAddition(RECIPIENT_3);

        address[] memory queued = registry.getQueuedAdditions();
        assertEq(queued.length, 3);
        assertEq(queued[0], RECIPIENT_1);
        assertEq(queued[1], RECIPIENT_2);
        assertEq(queued[2], RECIPIENT_3);
    }

    function test_RevertGiven_TheRecipientIsAddressZero() external {
        // it should revert
        vm.expectRevert();
        registry.queueRecipientAddition(address(0));
    }

    function test_RevertGiven_TheRecipientIsAlreadyActive() external {
        // it should revert
        registry.queueRecipientAddition(RECIPIENT_1);
        registry.processQueue();

        vm.expectRevert();
        registry.queueRecipientAddition(RECIPIENT_1);
    }

    function test_GivenTheRecipientIsAlreadyQueued() external {
        // it should revert with RecipientAlreadyQueued
        registry.queueRecipientAddition(RECIPIENT_1);

        vm.expectRevert(IRecipientRegistry.RecipientAlreadyQueued.selector);
        registry.queueRecipientAddition(RECIPIENT_1);
    }

    // ── when queuing a recipient for removal ──

    function test_GivenTheRecipientIsActive() external {
        // it should add to removal queue and emit RecipientQueued
        // First add a recipient
        registry.queueRecipientAddition(RECIPIENT_1);
        registry.processQueue();

        // Queue removal
        vm.expectEmit(true, true, false, true);
        emit IRecipientRegistry.RecipientQueued(RECIPIENT_1, false);

        registry.queueRecipientRemoval(RECIPIENT_1);

        address[] memory queued = registry.getQueuedRemovals();
        assertEq(queued.length, 1);
        assertEq(queued[0], RECIPIENT_1);
        assertTrue(registry.isQueuedForRemoval(RECIPIENT_1));
    }

    function test_RevertGiven_TheRecipientIsNotActive() external {
        // it should revert
        vm.expectRevert();
        registry.queueRecipientRemoval(RECIPIENT_1);
    }

    function test_GivenTheRecipientIsAlreadyQueuedForRemoval() external {
        // it should revert with RecipientAlreadyQueued
        registry.queueRecipientAddition(RECIPIENT_1);
        registry.processQueue();

        registry.queueRecipientRemoval(RECIPIENT_1);

        vm.expectRevert(IRecipientRegistry.RecipientAlreadyQueued.selector);
        registry.queueRecipientRemoval(RECIPIENT_1);
    }

    // ── when processing the queue ──

    function test_GivenTheQueueHasAdditions() external {
        // it should add recipients and emit events
        registry.queueRecipientAddition(RECIPIENT_1);
        registry.queueRecipientAddition(RECIPIENT_2);

        address[] memory expectedAdded = new address[](2);
        expectedAdded[0] = RECIPIENT_1;
        expectedAdded[1] = RECIPIENT_2;
        address[] memory expectedRemoved = new address[](0);
        address[] memory expectedNew = new address[](2);
        expectedNew[0] = RECIPIENT_1;
        expectedNew[1] = RECIPIENT_2;

        vm.expectEmit(true, false, false, true);
        emit IRecipientRegistry.RecipientAdded(RECIPIENT_1);
        vm.expectEmit(true, false, false, true);
        emit IRecipientRegistry.RecipientAdded(RECIPIENT_2);
        vm.expectEmit(false, false, false, true);
        emit IRecipientRegistry.QueueProcessed(expectedAdded, expectedRemoved, expectedNew);

        registry.processQueue();

        assertEq(registry.getRecipientCount(), 2);
        assertTrue(registry.isRecipient(RECIPIENT_1));
        assertTrue(registry.isRecipient(RECIPIENT_2));

        // Queue should be cleared
        assertEq(registry.getQueuedAdditions().length, 0);
    }

    function test_GivenTheQueueHasRemovals() external {
        // it should remove recipients and emit events
        // Add recipients
        registry.queueRecipientAddition(RECIPIENT_1);
        registry.queueRecipientAddition(RECIPIENT_2);
        registry.queueRecipientAddition(RECIPIENT_3);
        registry.processQueue();

        // Queue removals
        registry.queueRecipientRemoval(RECIPIENT_1);
        registry.queueRecipientRemoval(RECIPIENT_3);

        address[] memory expectedAdded = new address[](0);
        address[] memory expectedRemoved = new address[](2);
        expectedRemoved[0] = RECIPIENT_1;
        expectedRemoved[1] = RECIPIENT_3;
        address[] memory expectedNew = new address[](1);
        expectedNew[0] = RECIPIENT_2;

        vm.expectEmit(true, false, false, true);
        emit IRecipientRegistry.RecipientRemoved(RECIPIENT_1);
        vm.expectEmit(true, false, false, true);
        emit IRecipientRegistry.RecipientRemoved(RECIPIENT_3);
        vm.expectEmit(false, false, false, true);
        emit IRecipientRegistry.QueueProcessed(expectedAdded, expectedRemoved, expectedNew);

        registry.processQueue();

        // Only RECIPIENT_2 should remain
        assertEq(registry.getRecipientCount(), 1);
        assertFalse(registry.isRecipient(RECIPIENT_1));
        assertTrue(registry.isRecipient(RECIPIENT_2));
        assertFalse(registry.isRecipient(RECIPIENT_3));

        // Queues should be cleared
        assertEq(registry.getQueuedRemovals().length, 0);
    }

    function test_GivenTheQueueHasMixedOperations() external {
        // it should process additions and removals together
        // Add initial recipients
        registry.queueRecipientAddition(RECIPIENT_1);
        registry.queueRecipientAddition(RECIPIENT_2);
        registry.processQueue();

        // Queue mixed operations
        registry.queueRecipientAddition(RECIPIENT_3);
        registry.queueRecipientAddition(RECIPIENT_4);
        registry.queueRecipientRemoval(RECIPIENT_1);

        address[] memory expectedAdded = new address[](2);
        expectedAdded[0] = RECIPIENT_3;
        expectedAdded[1] = RECIPIENT_4;
        address[] memory expectedRemoved = new address[](1);
        expectedRemoved[0] = RECIPIENT_1;
        address[] memory expectedNew = new address[](3);
        expectedNew[0] = RECIPIENT_2;
        expectedNew[1] = RECIPIENT_3;
        expectedNew[2] = RECIPIENT_4;

        vm.expectEmit(false, false, false, true);
        emit IRecipientRegistry.QueueProcessed(expectedAdded, expectedRemoved, expectedNew);

        registry.processQueue();

        // Should have RECIPIENT_2, RECIPIENT_3, RECIPIENT_4
        assertEq(registry.getRecipientCount(), 3);
        assertFalse(registry.isRecipient(RECIPIENT_1));
        assertTrue(registry.isRecipient(RECIPIENT_2));
        assertTrue(registry.isRecipient(RECIPIENT_3));
        assertTrue(registry.isRecipient(RECIPIENT_4));
    }

    function test_GivenTheQueueIsEmpty() external {
        // it should not revert
        registry.processQueue();
        assertEq(registry.getRecipientCount(), 0);
    }

    // ── when clearing queues ──

    function test_WhenClearingTheAdditionQueue() external {
        // it should remove all queued additions
        registry.queueRecipientAddition(RECIPIENT_1);
        registry.queueRecipientAddition(RECIPIENT_2);

        assertEq(registry.getQueuedAdditions().length, 2);

        registry.clearAdditionQueue();

        assertEq(registry.getQueuedAdditions().length, 0);
    }

    function test_WhenClearingTheRemovalQueue() external {
        // it should remove all queued removals
        // Add recipients first
        registry.queueRecipientAddition(RECIPIENT_1);
        registry.queueRecipientAddition(RECIPIENT_2);
        registry.processQueue();

        // Queue removals
        registry.queueRecipientRemoval(RECIPIENT_1);
        registry.queueRecipientRemoval(RECIPIENT_2);

        assertEq(registry.getQueuedRemovals().length, 2);

        registry.clearRemovalQueue();

        assertEq(registry.getQueuedRemovals().length, 0);
    }

    // ── when re-queuing ──

    function test_WhenRe_queuingAfterRemoval() external {
        // it should allow re-adding a previously removed recipient
        registry.queueRecipientAddition(RECIPIENT_1);
        registry.processQueue();

        registry.queueRecipientRemoval(RECIPIENT_1);
        registry.processQueue();

        assertFalse(registry.isRecipient(RECIPIENT_1));
        assertFalse(registry.isQueuedForRemoval(RECIPIENT_1));

        registry.queueRecipientAddition(RECIPIENT_1);

        assertTrue(registry.isQueuedForAddition(RECIPIENT_1));
        assertEq(registry.getQueuedAdditions().length, 1);

        registry.processQueue();

        assertTrue(registry.isRecipient(RECIPIENT_1));
        assertFalse(registry.isQueuedForAddition(RECIPIENT_1));
        assertEq(registry.getRecipientCount(), 1);
    }

    function test_WhenRe_queuingAfterClearing() external {
        // it should allow re-adding after clearing addition queue
        registry.queueRecipientAddition(RECIPIENT_1);

        registry.clearAdditionQueue();

        assertEq(registry.getQueuedAdditions().length, 0);
        assertFalse(registry.isQueuedForAddition(RECIPIENT_1));

        registry.queueRecipientAddition(RECIPIENT_1);
        assertTrue(registry.isQueuedForAddition(RECIPIENT_1));

        registry.processQueue();

        assertTrue(registry.isRecipient(RECIPIENT_1));
        assertFalse(registry.isQueuedForAddition(RECIPIENT_1));
        assertEq(registry.getRecipientCount(), 1);
    }

    // ── when checking queue independence ──

    function test_WhenCheckingQueueIndependence() external {
        // it should keep addition and removal queues independent
        registry.queueRecipientAddition(RECIPIENT_1);
        registry.processQueue();

        registry.queueRecipientAddition(RECIPIENT_2);
        registry.queueRecipientRemoval(RECIPIENT_1);

        assertTrue(registry.isQueuedForAddition(RECIPIENT_2));
        assertTrue(registry.isQueuedForRemoval(RECIPIENT_1));
        assertFalse(registry.isQueuedForAddition(RECIPIENT_1));
        assertFalse(registry.isQueuedForRemoval(RECIPIENT_2));

        registry.processQueue();

        assertFalse(registry.isRecipient(RECIPIENT_1));
        assertTrue(registry.isRecipient(RECIPIENT_2));
        assertEq(registry.getRecipientCount(), 1);
    }

    // ── when getting recipients ──

    function test_WhenGettingRecipients() external {
        // it should return all active recipients
        registry.queueRecipientAddition(RECIPIENT_1);
        registry.queueRecipientAddition(RECIPIENT_2);
        registry.queueRecipientAddition(RECIPIENT_3);
        registry.processQueue();

        address[] memory recipients = registry.getRecipients();
        assertEq(recipients.length, 3);
        assertEq(recipients[0], RECIPIENT_1);
        assertEq(recipients[1], RECIPIENT_2);
        assertEq(recipients[2], RECIPIENT_3);
    }

    // ── when checking access control ──

    function test_WhenCheckingAccessControl_ShouldOnlyAllowOwnerToQueue() external {
        // it should only allow owner to queue
        vm.prank(address(0xdead));
        vm.expectRevert();
        registry.queueRecipientAddition(RECIPIENT_1);

        vm.prank(address(0xdead));
        vm.expectRevert();
        registry.queueRecipientRemoval(RECIPIENT_1);
    }

    function test_WhenCheckingAccessControl_ShouldOnlyAllowOwnerToClearQueues() external {
        // it should only allow owner to clear queues
        registry.queueRecipientAddition(RECIPIENT_1);

        vm.prank(address(0xdead));
        vm.expectRevert();
        registry.clearAdditionQueue();

        vm.prank(address(0xdead));
        vm.expectRevert();
        registry.clearRemovalQueue();
    }

    function test_WhenCheckingAccessControl_ShouldAllowAnyoneToProcessQueue() external {
        // it should allow anyone to process queue
        registry.queueRecipientAddition(RECIPIENT_1);

        vm.prank(address(0xdead));
        registry.processQueue();

        assertTrue(registry.isRecipient(RECIPIENT_1));
    }

    // ── when performing large scale operations ──

    function test_WhenPerformingLargeScaleOperations() external {
        // it should handle 100 additions and 50 removals
        // Add many recipients
        uint256 count = 100;
        for (uint256 i = 1; i <= count; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            registry.queueRecipientAddition(address(uint160(i)));
        }

        registry.processQueue();
        assertEq(registry.getRecipientCount(), count);

        // Remove half
        for (uint256 i = 1; i <= 50; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            registry.queueRecipientRemoval(address(uint160(i)));
        }

        registry.processQueue();
        assertEq(registry.getRecipientCount(), 50);
    }

    // ── MAX_QUEUE_SIZE boundary tests ──

    function test_MaxQueueSizeAdditionBoundary() public {
        // Queue exactly MAX_QUEUE_SIZE (100) additions — should succeed
        for (uint256 i = 1; i <= 100; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            registry.queueRecipientAddition(address(uint160(i)));
        }
        assertEq(registry.getQueuedAdditions().length, 100);

        // Queue one more — should revert with MaxQueueSizeReached
        vm.expectRevert(IRecipientRegistry.MaxQueueSizeReached.selector);
        registry.queueRecipientAddition(address(uint160(101)));
    }

    function test_MaxQueueSizeRemovalBoundary() public {
        // First add 100 recipients
        for (uint256 i = 1; i <= 100; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            registry.queueRecipientAddition(address(uint160(i)));
        }
        registry.processQueue();

        // Queue exactly MAX_QUEUE_SIZE (100) removals — should succeed
        for (uint256 i = 1; i <= 100; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            registry.queueRecipientRemoval(address(uint160(i)));
        }
        assertEq(registry.getQueuedRemovals().length, 100);
    }
}
