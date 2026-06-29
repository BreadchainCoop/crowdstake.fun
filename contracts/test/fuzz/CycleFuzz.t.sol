// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {CycleModule} from "../../src/implementation/CycleModule.sol";
import {AbstractCycleModule} from "../../src/abstract/AbstractCycleModule.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract CycleFuzz is Test {
    address owner = address(0xA1);
    address distManager = address(0xD1);

    function _deployCycle(uint256 cycleLen) internal returns (CycleModule) {
        CycleModule impl = new CycleModule();
        bytes memory initData = abi.encodeWithSelector(AbstractCycleModule.initialize.selector, cycleLen, owner);
        CycleModule cm = CycleModule(address(new ERC1967Proxy(address(impl), initData)));
        vm.prank(owner);
        cm.setDistributionManager(distManager);
        return cm;
    }

    /// @notice Fuzz that cycle number monotonically increases after startNewCycle
    function testFuzz_CycleMonotonicallyIncreases(uint256 cycleLen, uint8 advances) public {
        cycleLen = bound(cycleLen, 1, 1e6);
        uint256 numAdvances = bound(advances, 1, 20);

        CycleModule cycleModule = _deployCycle(cycleLen);

        uint256 previousCycle = cycleModule.currentCycle();
        assertEq(previousCycle, 1);

        for (uint256 i = 0; i < numAdvances; i++) {
            // Advance enough blocks to complete the cycle
            vm.roll(block.number + cycleLen);

            vm.prank(distManager);
            cycleModule.startNewCycle();

            uint256 currentCycle = cycleModule.currentCycle();
            assertGt(currentCycle, previousCycle);
            assertEq(currentCycle, previousCycle + 1);
            previousCycle = currentCycle;
        }
    }

    /// @notice Fuzz isCycleComplete consistency with block advancement
    function testFuzz_IsCycleCompleteConsistency(uint256 cycleLen, uint256 blocksAdvanced) public {
        cycleLen = bound(cycleLen, 1, 1e6);
        blocksAdvanced = bound(blocksAdvanced, 0, 2e6);

        CycleModule cycleModule = _deployCycle(cycleLen);

        uint256 startBlock = block.number;
        vm.roll(startBlock + blocksAdvanced);

        bool complete = cycleModule.isCycleComplete();
        if (blocksAdvanced >= cycleLen) {
            assertTrue(complete);
        } else {
            assertFalse(complete);
        }
    }

    /// @notice Fuzz that progress is always 0-100
    function testFuzz_ProgressAlwaysBounded(uint256 cycleLen, uint256 blocksAdvanced) public {
        cycleLen = bound(cycleLen, 1, 1e6);
        blocksAdvanced = bound(blocksAdvanced, 0, 2e6);

        CycleModule cycleModule = _deployCycle(cycleLen);

        uint256 startBlock = block.number;
        vm.roll(startBlock + blocksAdvanced);

        uint256 progress = cycleModule.getCycleProgress();
        assertLe(progress, 100);
    }

    /// @notice Fuzz that getBlocksUntilNextCycle is consistent
    function testFuzz_BlocksUntilNextCycleConsistency(uint256 cycleLen, uint256 blocksAdvanced) public {
        cycleLen = bound(cycleLen, 1, 1e6);
        blocksAdvanced = bound(blocksAdvanced, 0, 2e6);

        CycleModule cycleModule = _deployCycle(cycleLen);

        uint256 startBlock = block.number;
        vm.roll(startBlock + blocksAdvanced);

        uint256 blocksUntil = cycleModule.getBlocksUntilNextCycle();

        if (blocksAdvanced >= cycleLen) {
            assertEq(blocksUntil, 0);
        } else {
            assertEq(blocksUntil, cycleLen - blocksAdvanced);
        }
    }

    /// @notice Fuzz that startNewCycle reverts when cycle is not complete
    function testFuzz_StartNewCycleRevertsIfNotComplete(uint256 cycleLen, uint256 blocksAdvanced) public {
        cycleLen = bound(cycleLen, 2, 1e6);
        blocksAdvanced = bound(blocksAdvanced, 0, cycleLen - 1);

        CycleModule cycleModule = _deployCycle(cycleLen);

        vm.roll(block.number + blocksAdvanced);

        vm.prank(distManager);
        vm.expectRevert();
        cycleModule.startNewCycle();
    }

    /// @notice Fuzz that updateCycleLength works and zero reverts
    function testFuzz_UpdateCycleLengthValidation(uint256 newLen) public {
        CycleModule cycleModule = _deployCycle(100);

        if (newLen == 0) {
            vm.prank(owner);
            vm.expectRevert();
            cycleModule.updateCycleLength(newLen);
        } else {
            vm.prank(owner);
            cycleModule.updateCycleLength(newLen);
            assertEq(cycleModule.cycleLength(), newLen);
        }
    }

    /// @notice Fuzz that progress at cycle start is 0 and at cycle end is 100
    function testFuzz_ProgressBoundaryValues(uint256 cycleLen) public {
        cycleLen = bound(cycleLen, 1, 1e6);
        CycleModule cycleModule = _deployCycle(cycleLen);

        // At start: progress should be 0
        uint256 progressAtStart = cycleModule.getCycleProgress();
        assertEq(progressAtStart, 0);

        // At end: progress should be 100
        vm.roll(block.number + cycleLen);
        uint256 progressAtEnd = cycleModule.getCycleProgress();
        assertEq(progressAtEnd, 100);
    }

    /// @notice Fuzz that lastCycleStartBlock updates on cycle transition
    function testFuzz_LastCycleStartBlockUpdates(uint256 cycleLen, uint256 extraBlocks) public {
        cycleLen = bound(cycleLen, 1, 1e5);
        extraBlocks = bound(extraBlocks, 0, 1e5);

        CycleModule cycleModule = _deployCycle(cycleLen);

        uint256 initialStartBlock = cycleModule.lastCycleStartBlock();

        // Advance past cycle end (possibly with extra blocks)
        vm.roll(block.number + cycleLen + extraBlocks);

        vm.prank(distManager);
        cycleModule.startNewCycle();

        uint256 newStartBlock = cycleModule.lastCycleStartBlock();
        assertEq(newStartBlock, block.number);
        assertGe(newStartBlock, initialStartBlock + cycleLen);
    }
}
