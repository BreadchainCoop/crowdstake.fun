// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {CycleModule} from "../src/implementation/CycleModule.sol";
import {AbstractCycleModule} from "../src/abstract/AbstractCycleModule.sol";

contract CycleModuleTest is Test {
    CycleModule public cycleModule;
    address public owner = address(this);
    address public user = address(0x1);

    uint256 constant CYCLE_LENGTH = 100; // 100 blocks per cycle
    uint256 constant START_BLOCK = 1000;

    function setUp() public {
        vm.roll(START_BLOCK);
        cycleModule = new CycleModule();
        cycleModule.initialize(CYCLE_LENGTH, owner);
    }

    function testInitialState() public view {
        assertEq(cycleModule.getCurrentCycle(), 1);
        assertEq(cycleModule.cycleLength(), CYCLE_LENGTH);
        assertEq(cycleModule.lastCycleStartBlock(), START_BLOCK);
        assertTrue(cycleModule.authorized(owner));
        assertTrue(cycleModule.initialized());
    }

    function testCannotReinitialize() public {
        vm.expectRevert(AbstractCycleModule.AlreadyInitialized.selector);
        cycleModule.initialize(200, owner);
    }

    function testNotInitializedFunctions() public {
        CycleModule uninitializedModule = new CycleModule();

        vm.expectRevert(AbstractCycleModule.NotInitialized.selector);
        uninitializedModule.getCurrentCycle();

        vm.expectRevert(AbstractCycleModule.NotInitialized.selector);
        uninitializedModule.isCycleComplete();

        vm.expectRevert(AbstractCycleModule.NotInitialized.selector);
        uninitializedModule.startNewCycle();

        vm.expectRevert(AbstractCycleModule.NotInitialized.selector);
        uninitializedModule.getBlocksUntilNextCycle();

        vm.expectRevert(AbstractCycleModule.NotInitialized.selector);
        uninitializedModule.getCycleProgress();

        vm.expectRevert(AbstractCycleModule.NotInitialized.selector);
        uninitializedModule.updateCycleLength(200);
    }

    function testCycleCompletion() public {
        assertFalse(cycleModule.isCycleComplete());

        // Move to end of cycle
        vm.roll(START_BLOCK + CYCLE_LENGTH);
        assertTrue(cycleModule.isCycleComplete());
    }

    function testStartNewCycle() public {
        // Move to end of cycle
        vm.roll(START_BLOCK + CYCLE_LENGTH);

        uint256 currentBlock = block.number;
        cycleModule.startNewCycle();

        assertEq(cycleModule.getCurrentCycle(), 2);
        assertEq(cycleModule.lastCycleStartBlock(), currentBlock);
        assertFalse(cycleModule.isCycleComplete());
    }

    function testCannotStartNewCycleEarly() public {
        // Try to start new cycle before current one is complete
        vm.roll(START_BLOCK + CYCLE_LENGTH - 1);

        vm.expectRevert(AbstractCycleModule.InvalidCycleTransition.selector);
        cycleModule.startNewCycle();
    }

    function testUnauthorizedCannotStartCycle() public {
        vm.roll(START_BLOCK + CYCLE_LENGTH);

        vm.prank(user);
        vm.expectRevert(AbstractCycleModule.NotAuthorized.selector);
        cycleModule.startNewCycle();
    }

    function testAuthorization() public {
        assertFalse(cycleModule.authorized(user));

        cycleModule.setAuthorization(user, true);
        assertTrue(cycleModule.authorized(user));

        cycleModule.setAuthorization(user, false);
        assertFalse(cycleModule.authorized(user));
    }

    function testGetBlocksUntilNextCycle() public view {
        assertEq(cycleModule.getBlocksUntilNextCycle(), CYCLE_LENGTH);
    }

    function testGetBlocksUntilNextCyclePartway() public {
        vm.roll(START_BLOCK + 25);
        assertEq(cycleModule.getBlocksUntilNextCycle(), 75);
    }

    function testGetBlocksUntilNextCycleComplete() public {
        vm.roll(START_BLOCK + CYCLE_LENGTH);
        assertEq(cycleModule.getBlocksUntilNextCycle(), 0);
    }

    function testGetCycleProgress() public view {
        assertEq(cycleModule.getCycleProgress(), 0);
    }

    function testGetCycleProgressPartway() public {
        vm.roll(START_BLOCK + 50);
        assertEq(cycleModule.getCycleProgress(), 50);
    }

    function testGetCycleProgressComplete() public {
        vm.roll(START_BLOCK + CYCLE_LENGTH);
        assertEq(cycleModule.getCycleProgress(), 100);
    }

    function testUpdateCycleLength() public {
        uint256 newLength = 200;
        cycleModule.updateCycleLength(newLength);
        assertEq(cycleModule.cycleLength(), newLength);
    }

    function testCannotUpdateCycleLengthToZero() public {
        vm.expectRevert(AbstractCycleModule.InvalidCycleLength.selector);
        cycleModule.updateCycleLength(0);
    }

    function testUnauthorizedCannotUpdateCycleLength() public {
        vm.prank(user);
        vm.expectRevert(AbstractCycleModule.NotAuthorized.selector);
        cycleModule.updateCycleLength(200);
    }

    function testAnyoneCanInitializeOnce() public {
        CycleModule newModule = new CycleModule();

        vm.prank(user);
        newModule.initialize(100, user);

        // User is now authorized as the initializer
        assertTrue(newModule.authorized(user));
        assertEq(newModule.cycleLength(), 100);
        assertTrue(newModule.initialized());

        // Cannot reinitialize
        vm.expectRevert(AbstractCycleModule.AlreadyInitialized.selector);
        newModule.initialize(200, user);
    }

    function testCannotInitializeWithZeroAddress() public {
        CycleModule newModule = new CycleModule();
        vm.expectRevert(AbstractCycleModule.NotAuthorized.selector);
        newModule.initialize(100, address(0));
    }

    function testMultipleCycles() public {
        // Complete first cycle
        vm.roll(START_BLOCK + CYCLE_LENGTH);
        cycleModule.startNewCycle();
        assertEq(cycleModule.getCurrentCycle(), 2);

        // Complete second cycle
        vm.roll(START_BLOCK + CYCLE_LENGTH + CYCLE_LENGTH);
        cycleModule.startNewCycle();
        assertEq(cycleModule.getCurrentCycle(), 3);
        assertEq(cycleModule.lastCycleStartBlock(), START_BLOCK + CYCLE_LENGTH + CYCLE_LENGTH);
    }
}
