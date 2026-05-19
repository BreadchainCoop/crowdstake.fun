// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {RecipientRegistry} from "../../src/implementation/registries/RecipientRegistry.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract RecipientRegistryFuzz is Test {
    RecipientRegistry registry;
    address admin = address(0xA1);

    function setUp() public {
        RecipientRegistry impl = new RecipientRegistry();
        bytes memory initData = abi.encodeCall(RecipientRegistry.initialize, (admin));
        registry = RecipientRegistry(address(new ERC1967Proxy(address(impl), initData)));
    }

    /// @notice Fuzz queueRecipientAddition with random addresses -- no duplicates allowed
    function testFuzz_QueueAdditionNoDuplicates(address recipient) public {
        vm.assume(recipient != address(0));

        vm.startPrank(admin);
        registry.queueRecipientAddition(recipient);

        // Second queue of same address must revert
        vm.expectRevert();
        registry.queueRecipientAddition(recipient);
        vm.stopPrank();
    }

    /// @notice Fuzz that zero address always reverts
    function testFuzz_QueueAdditionRejectsZeroAddress(
        uint256 /* salt */
    )
        public
    {
        vm.prank(admin);
        vm.expectRevert();
        registry.queueRecipientAddition(address(0));
    }

    /// @notice Fuzz MAX_QUEUE_SIZE enforcement (100)
    function testFuzz_MaxQueueSizeEnforced(uint8 extra) public {
        uint256 extraCount = bound(extra, 1, 50);

        vm.startPrank(admin);
        // Fill the queue to 100
        for (uint256 i = 1; i <= 100; i++) {
            registry.queueRecipientAddition(address(uint160(i)));
        }

        // Any further addition must revert
        for (uint256 i = 0; i < extraCount; i++) {
            vm.expectRevert();
            registry.queueRecipientAddition(address(uint160(200 + i)));
        }
        vm.stopPrank();
    }

    /// @notice Fuzz queue -> process -> re-queue cycle
    function testFuzz_QueueProcessRequeue(address recipient) public {
        vm.assume(recipient != address(0));

        vm.prank(admin);
        registry.queueRecipientAddition(recipient);

        registry.processQueue();

        // Recipient should now be active
        assertTrue(registry.isRecipientMapping(recipient));
        assertEq(registry.recipientsLength(), 1);

        // Can't add again while active
        vm.prank(admin);
        vm.expectRevert();
        registry.queueRecipientAddition(recipient);

        // Queue removal
        vm.prank(admin);
        registry.queueRecipientRemoval(recipient);
        registry.processQueue();

        // Recipient should be gone
        assertFalse(registry.isRecipientMapping(recipient));
        assertEq(registry.recipientsLength(), 0);

        // Can re-queue for addition now
        vm.prank(admin);
        registry.queueRecipientAddition(recipient);
        registry.processQueue();
        assertTrue(registry.isRecipientMapping(recipient));
        assertEq(registry.recipientsLength(), 1);
    }

    /// @notice Fuzz mixed add/remove operations -- recipient count invariant
    function testFuzz_MixedAddRemoveCountInvariant(uint8 addCount, uint8 removeCount) public {
        uint256 numToAdd = bound(addCount, 1, 50);
        uint256 numToRemove = bound(removeCount, 0, numToAdd);

        vm.startPrank(admin);

        // Queue additions
        for (uint256 i = 1; i <= numToAdd; i++) {
            registry.queueRecipientAddition(address(uint160(i)));
        }
        vm.stopPrank();

        registry.processQueue();
        assertEq(registry.recipientsLength(), numToAdd);

        // Queue removals
        vm.startPrank(admin);
        for (uint256 i = 1; i <= numToRemove; i++) {
            registry.queueRecipientRemoval(address(uint160(i)));
        }
        vm.stopPrank();

        registry.processQueue();

        // Invariant: recipientsLength == numToAdd - numToRemove
        assertEq(registry.recipientsLength(), numToAdd - numToRemove);

        // All removed addresses are no longer recipients
        for (uint256 i = 1; i <= numToRemove; i++) {
            assertFalse(registry.isRecipientMapping(address(uint160(i))));
        }

        // All kept addresses are still recipients
        for (uint256 i = numToRemove + 1; i <= numToAdd; i++) {
            assertTrue(registry.isRecipientMapping(address(uint160(i))));
        }
    }

    /// @notice Fuzz that queues are cleared after processing
    function testFuzz_QueuesEmptyAfterProcess(uint8 count) public {
        uint256 n = bound(count, 1, 30);

        vm.startPrank(admin);
        for (uint256 i = 1; i <= n; i++) {
            registry.queueRecipientAddition(address(uint160(i)));
        }
        vm.stopPrank();

        registry.processQueue();

        assertEq(registry.queuedRecipientsForAdditionLength(), 0);
        assertEq(registry.queuedRecipientsForRemovalLength(), 0);
    }
}
