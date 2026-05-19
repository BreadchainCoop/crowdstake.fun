// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MockDistributionManagerSimple} from "./mocks/MockDistributionManagerSimple.sol";

contract MockDistributionManagerTest is Test {
    MockDistributionManagerSimple public manager;

    event MockDistributionExecuted(uint256 blockNumber);

    function setUp() public {
        manager = new MockDistributionManagerSimple();
    }

    // ============ when checking initial state ============

    function test_WhenCheckingInitialState_ShouldHaveCorrectDefaults() public view {
        assertEq(manager.BLOCKS_PER_CYCLE(), 200, "Blocks per cycle should be 200");
        assertEq(manager.getLastDistributionBlock(), block.number, "Last distribution should be deployment block");
        assertFalse(manager.isDistributionReady(), "Should not be ready immediately after deployment");
    }

    // ============ when checking distribution readiness ============

    function test_WhenCheckingDistributionReadiness_ShouldReturnFalseBefore200Blocks() public {
        // Fast forward 199 blocks
        vm.roll(block.number + 199);
        assertFalse(manager.isDistributionReady(), "Should not be ready at 199 blocks");
    }

    function test_WhenCheckingDistributionReadiness_ShouldReturnTrueAt200Blocks() public {
        // Fast forward to exactly 200 blocks
        vm.roll(block.number + 200);
        assertTrue(manager.isDistributionReady(), "Should be ready at 200 blocks");

        // Fast forward more
        vm.roll(block.number + 100);
        assertTrue(manager.isDistributionReady(), "Should still be ready after 200 blocks");
    }

    // ============ when querying blocks until distribution ============

    function test_WhenQueryingBlocksUntilDistribution_ShouldReturn200AtStart() public view {
        assertEq(manager.blocksUntilDistribution(), 200, "Should be 200 blocks until distribution");
    }

    function test_WhenQueryingBlocksUntilDistribution_ShouldReturn100AtHalfway() public {
        vm.roll(block.number + 100);
        assertEq(manager.blocksUntilDistribution(), 100, "Should be 100 blocks until distribution");
    }

    function test_WhenQueryingBlocksUntilDistribution_ShouldReturn0WhenReady() public {
        vm.roll(block.number + 200);
        assertEq(manager.blocksUntilDistribution(), 0, "Should be 0 blocks until distribution");

        vm.roll(block.number + 50);
        assertEq(manager.blocksUntilDistribution(), 0, "Should still be 0 when overdue");
    }

    // ============ when executing claimAndDistribute ============

    function test_RevertWhen_ExecutingClaimAndDistribute_WhenNotReady() public {
        // Try to execute too early
        vm.expectRevert("Not ready");
        manager.claimAndDistribute();
    }

    function test_WhenExecutingClaimAndDistribute_ShouldExecuteAndResetTimer() public {
        // Fast forward 200 blocks
        vm.roll(block.number + 200);

        // Execute distribution
        vm.expectEmit(true, true, true, true);
        emit MockDistributionExecuted(block.number);
        manager.claimAndDistribute();

        // Check state after execution
        assertEq(manager.getLastDistributionBlock(), block.number, "Last distribution should be updated");
        assertFalse(manager.isDistributionReady(), "Should not be ready immediately after execution");

        // Check blocks until next distribution
        assertEq(manager.blocksUntilDistribution(), 200, "Should be 200 blocks until next distribution");
    }

    // ============ when running multiple distributions ============

    function test_WhenRunningMultipleDistributions_ShouldTrackCycleProgression() public {
        uint256 startBlock = block.number;

        // First distribution
        vm.roll(startBlock + 200);
        assertTrue(manager.isDistributionReady());
        manager.claimAndDistribute();

        // Second distribution
        vm.roll(block.number + 200);
        assertTrue(manager.isDistributionReady());
        manager.claimAndDistribute();

        // Third distribution
        vm.roll(block.number + 200);
        assertTrue(manager.isDistributionReady());
        manager.claimAndDistribute();

        // Should have executed 3 distributions
        assertEq(manager.getLastDistributionBlock(), startBlock + 600);
    }
}
