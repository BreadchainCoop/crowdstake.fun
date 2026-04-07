// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {CycleModule} from "../src/implementation/CycleModule.sol";
import {AbstractCycleModule} from "../src/abstract/AbstractCycleModule.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract CycleModuleTest is Test {
    CycleModule public cycleModule;
    address public owner = address(this);
    address public user = address(0x1);
    address public distManager = address(0x2);

    uint256 constant CYCLE_LENGTH = 100; // 100 blocks per cycle
    uint256 constant START_BLOCK = 1000;

    function setUp() public {
        vm.roll(START_BLOCK);
        CycleModule impl = new CycleModule();
        bytes memory initData = abi.encodeWithSelector(AbstractCycleModule.initialize.selector, CYCLE_LENGTH, owner);
        cycleModule = CycleModule(address(new ERC1967Proxy(address(impl), initData)));
        cycleModule.setDistributionManager(distManager);
    }

    function testInitialState() public view {
        assertEq(cycleModule.getCurrentCycle(), 1);
        assertEq(cycleModule.cycleLength(), CYCLE_LENGTH);
        assertEq(cycleModule.lastCycleStartBlock(), START_BLOCK);
        assertEq(cycleModule.owner(), owner);
    }

    function testCannotReinitialize() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        cycleModule.initialize(200, owner);
    }

    function testNotInitializedFunctions() public {
        // Deploy a proxy without initialization data to get an uninitialized module
        CycleModule impl = new CycleModule();
        CycleModule uninitializedModule = CycleModule(address(new ERC1967Proxy(address(impl), "")));

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
        vm.prank(distManager);
        cycleModule.startNewCycle();

        assertEq(cycleModule.getCurrentCycle(), 2);
        assertEq(cycleModule.lastCycleStartBlock(), currentBlock);
        assertFalse(cycleModule.isCycleComplete());
    }

    function testCannotStartNewCycleEarly() public {
        // Try to start new cycle before current one is complete
        vm.roll(START_BLOCK + CYCLE_LENGTH - 1);

        vm.prank(distManager);
        vm.expectRevert(AbstractCycleModule.InvalidCycleTransition.selector);
        cycleModule.startNewCycle();
    }

    function testNonDistributionManagerCannotStartCycle() public {
        vm.roll(START_BLOCK + CYCLE_LENGTH);

        vm.prank(user);
        vm.expectRevert(AbstractCycleModule.OnlyDistributionManager.selector);
        cycleModule.startNewCycle();
    }

    function testOwnerCannotStartCycle() public {
        vm.roll(START_BLOCK + CYCLE_LENGTH);

        vm.expectRevert(AbstractCycleModule.OnlyDistributionManager.selector);
        cycleModule.startNewCycle();
    }

    function testOwnership() public {
        assertEq(cycleModule.owner(), owner);

        cycleModule.transferOwnership(user);
        assertEq(cycleModule.owner(), user);
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

    function testNonOwnerCannotUpdateCycleLength() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user));
        cycleModule.updateCycleLength(200);
    }

    function testAnyoneCanInitializeOnce() public {
        CycleModule impl = new CycleModule();
        CycleModule newModule = CycleModule(address(new ERC1967Proxy(address(impl), "")));

        vm.prank(user);
        newModule.initialize(100, user);

        // User is now the owner
        assertEq(newModule.owner(), user);
        assertEq(newModule.cycleLength(), 100);

        // Cannot reinitialize
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        newModule.initialize(200, user);
    }

    function testCannotInitializeWithZeroAddress() public {
        CycleModule impl = new CycleModule();
        CycleModule newModule = CycleModule(address(new ERC1967Proxy(address(impl), "")));
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableInvalidOwner.selector, address(0)));
        newModule.initialize(100, address(0));
    }

    function testImplementationCannotBeInitialized() public {
        CycleModule impl = new CycleModule();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        impl.initialize(100, owner);
    }

    function testMultipleCycles() public {
        vm.startPrank(distManager);

        // Complete first cycle
        vm.roll(START_BLOCK + CYCLE_LENGTH);
        cycleModule.startNewCycle();
        assertEq(cycleModule.getCurrentCycle(), 2);

        // Complete second cycle
        vm.roll(START_BLOCK + CYCLE_LENGTH + CYCLE_LENGTH);
        cycleModule.startNewCycle();
        assertEq(cycleModule.getCurrentCycle(), 3);
        assertEq(cycleModule.lastCycleStartBlock(), START_BLOCK + CYCLE_LENGTH + CYCLE_LENGTH);

        vm.stopPrank();
    }

    function testSetDistributionManager() public {
        address newManager = address(0x99);
        cycleModule.setDistributionManager(newManager);
        assertEq(cycleModule.distributionManager(), newManager);
    }

    function testNonOwnerCannotSetDistributionManager() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user));
        cycleModule.setDistributionManager(address(0x99));
    }

    function testCannotSetZeroDistributionManager() public {
        vm.expectRevert(AbstractCycleModule.ZeroAddress.selector);
        cycleModule.setDistributionManager(address(0));
    }

    function testStartNewCycleRevertsWhenDistributionManagerNotSet() public {
        // Deploy a fresh cycle module without setting distribution manager
        CycleModule impl = new CycleModule();
        bytes memory initData = abi.encodeWithSelector(AbstractCycleModule.initialize.selector, CYCLE_LENGTH, owner);
        CycleModule freshModule = CycleModule(address(new ERC1967Proxy(address(impl), initData)));

        vm.roll(START_BLOCK + CYCLE_LENGTH);
        vm.expectRevert(AbstractCycleModule.DistributionManagerNotSet.selector);
        freshModule.startNewCycle();
    }
}
