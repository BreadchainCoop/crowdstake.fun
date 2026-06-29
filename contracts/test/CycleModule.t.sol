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

    // ============ when initializing ============

    function test_WhenInitializing_ItShouldSetInitialStateCorrectly() public view {
        assertEq(cycleModule.getCurrentCycle(), 1);
        assertEq(cycleModule.cycleLength(), CYCLE_LENGTH);
        assertEq(cycleModule.lastCycleStartBlock(), START_BLOCK);
        assertEq(cycleModule.owner(), owner);
    }

    function test_RevertWhen_Initializing_Reinitialize() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        cycleModule.initialize(200, owner);
    }

    function test_RevertWhen_Initializing_ZeroAddressOwner() public {
        CycleModule impl = new CycleModule();
        CycleModule newModule = CycleModule(address(new ERC1967Proxy(address(impl), "")));
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableInvalidOwner.selector, address(0)));
        newModule.initialize(100, address(0));
    }

    function test_RevertWhen_Initializing_ImplementationInitialization() public {
        CycleModule impl = new CycleModule();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        impl.initialize(100, owner);
    }

    // ============ when not initialized ============

    function test_RevertWhen_NotInitialized_AllStateQueries() public {
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

    // ============ when checking cycle completion before end ============

    function test_WhenCheckingCycleCompletionBeforeEnd_ItShouldReturnFalse() public view {
        assertFalse(cycleModule.isCycleComplete());
    }

    // ============ when checking cycle completion at end ============

    function test_WhenCheckingCycleCompletionAtEnd_ItShouldReturnTrue() public {
        // Move to end of cycle
        vm.roll(START_BLOCK + CYCLE_LENGTH);
        assertTrue(cycleModule.isCycleComplete());
    }

    // ============ when starting a new cycle as distribution manager ============

    function test_WhenStartingNewCycleAsDistributionManager_ItShouldAdvanceToNextCycle() public {
        // Move to end of cycle
        vm.roll(START_BLOCK + CYCLE_LENGTH);

        uint256 currentBlock = block.number;
        vm.prank(distManager);
        cycleModule.startNewCycle();

        assertEq(cycleModule.getCurrentCycle(), 2);
        assertEq(cycleModule.lastCycleStartBlock(), currentBlock);
        assertFalse(cycleModule.isCycleComplete());
    }

    // ============ when starting a new cycle before completion ============

    function test_RevertWhen_StartingNewCycleBeforeCompletion_InvalidCycleTransition() public {
        // Try to start new cycle before current one is complete
        vm.roll(START_BLOCK + CYCLE_LENGTH - 1);

        vm.prank(distManager);
        vm.expectRevert(AbstractCycleModule.InvalidCycleTransition.selector);
        cycleModule.startNewCycle();
    }

    // ============ when starting a new cycle as non distribution manager ============

    function test_RevertWhen_StartingNewCycleAsNonDistributionManager_OnlyDistributionManager() public {
        vm.roll(START_BLOCK + CYCLE_LENGTH);

        vm.prank(user);
        vm.expectRevert(AbstractCycleModule.OnlyDistributionManager.selector);
        cycleModule.startNewCycle();
    }

    // ============ when starting a new cycle without distribution manager set ============

    function test_RevertWhen_StartingNewCycleWithoutDistributionManagerSet_DistributionManagerNotSet() public {
        // Deploy a fresh cycle module without setting distribution manager
        CycleModule impl = new CycleModule();
        bytes memory initData = abi.encodeWithSelector(AbstractCycleModule.initialize.selector, CYCLE_LENGTH, owner);
        CycleModule freshModule = CycleModule(address(new ERC1967Proxy(address(impl), initData)));

        vm.roll(START_BLOCK + CYCLE_LENGTH);
        vm.expectRevert(AbstractCycleModule.DistributionManagerNotSet.selector);
        freshModule.startNewCycle();
    }

    // ============ when querying blocks until next cycle ============

    function test_WhenQueryingBlocksUntilNextCycle_ItShouldReturnFullCycleLengthAtStart() public view {
        assertEq(cycleModule.getBlocksUntilNextCycle(), CYCLE_LENGTH);
    }

    function test_WhenQueryingBlocksUntilNextCycle_ItShouldReturnRemainingBlocksPartway() public {
        vm.roll(START_BLOCK + 25);
        assertEq(cycleModule.getBlocksUntilNextCycle(), 75);
    }

    function test_WhenQueryingBlocksUntilNextCycle_ItShouldReturnZeroWhenComplete() public {
        vm.roll(START_BLOCK + CYCLE_LENGTH);
        assertEq(cycleModule.getBlocksUntilNextCycle(), 0);
    }

    // ============ when querying cycle progress ============

    function test_WhenQueryingCycleProgress_ItShouldReturnZeroAtStart() public view {
        assertEq(cycleModule.getCycleProgress(), 0);
    }

    function test_WhenQueryingCycleProgress_ItShouldReturn50Halfway() public {
        vm.roll(START_BLOCK + 50);
        assertEq(cycleModule.getCycleProgress(), 50);
    }

    function test_WhenQueryingCycleProgress_ItShouldReturn100WhenComplete() public {
        vm.roll(START_BLOCK + CYCLE_LENGTH);
        assertEq(cycleModule.getCycleProgress(), 100);
    }

    // ============ when updating cycle length as owner ============

    function test_WhenUpdatingCycleLengthAsOwner_ItShouldUpdateTheCycleLength() public {
        uint256 newLength = 200;
        cycleModule.updateCycleLength(newLength);
        assertEq(cycleModule.cycleLength(), newLength);
    }

    // ============ when updating cycle length to zero ============

    function test_RevertWhen_UpdatingCycleLengthToZero_InvalidCycleLength() public {
        vm.expectRevert(AbstractCycleModule.InvalidCycleLength.selector);
        cycleModule.updateCycleLength(0);
    }

    // ============ when updating cycle length as non owner ============

    function test_RevertWhen_UpdatingCycleLengthAsNonOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user));
        cycleModule.updateCycleLength(200);
    }

    // ============ when setting distribution manager as owner ============

    function test_WhenSettingDistributionManagerAsOwner_ItShouldUpdateDistributionManager() public {
        address newManager = address(0x99);
        cycleModule.setDistributionManager(newManager);
        assertEq(cycleModule.distributionManager(), newManager);
    }

    // ============ when setting zero distribution manager ============

    function test_RevertWhen_SettingZeroDistributionManager_ZeroAddress() public {
        vm.expectRevert(AbstractCycleModule.ZeroAddress.selector);
        cycleModule.setDistributionManager(address(0));
    }

    // ============ when setting distribution manager as non owner ============

    function test_RevertWhen_SettingDistributionManagerAsNonOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user));
        cycleModule.setDistributionManager(address(0x99));
    }

    // ============ when running multiple cycles ============

    function test_WhenRunningMultipleCycles_ItShouldCorrectlyTrackCycleNumberAndStartBlock() public {
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

    // ============ when managing ownership ============

    function test_WhenManagingOwnership_ItShouldTransferOwnershipCorrectly() public {
        assertEq(cycleModule.owner(), owner);

        cycleModule.transferOwnership(user);
        assertEq(cycleModule.owner(), user);
    }

    // ============ when anyone initializes ============

    function test_WhenAnyoneInitializes_ItShouldAllowFirstCallerToBecomeOwner() public {
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
}
