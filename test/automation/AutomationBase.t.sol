// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ChainlinkAutomation} from "../../src/implementation/automation/ChainlinkAutomation.sol";
import {AbstractAutomation} from "../../src/abstract/AbstractAutomation.sol";
// import "../../src/implementation/automation/GelatoAutomation.sol";
import {MockDistributionManager} from "../mocks/MockDistributionManager.sol";
import {IDistributionModule} from "../../src/interfaces/IDistributionModule.sol";
import {IRecipientRegistry} from "../../src/interfaces/IRecipientRegistry.sol";
import {ICycleModule} from "../../src/interfaces/ICycleModule.sol";

contract MockDistributionModule is IDistributionModule {
    uint256 public distributeCallCount;
    bool public isPaused;

    function recipientRegistry() external pure override returns (IRecipientRegistry) {
        return IRecipientRegistry(address(0));
    }

    function cycleManager() external pure override returns (ICycleModule) {
        return ICycleModule(address(0));
    }

    function distributeYield() external {
        distributeCallCount++;
    }

    function getCurrentDistributionState() external view returns (DistributionState memory state) {
        address[] memory recipients = new address[](3);
        uint256[] memory votedDist = new uint256[](3);
        uint256[] memory fixedDist = new uint256[](3);

        votedDist[0] = 40;
        votedDist[1] = 35;
        votedDist[2] = 25;

        state = DistributionState({
            totalYield: 100,
            fixedAmount: 20,
            votedAmount: 80,
            totalVotes: 100,
            lastDistributionBlock: block.number - 100,
            cycleNumber: 1,
            recipients: recipients,
            votedDistributions: votedDist,
            fixedDistributions: fixedDist
        });
    }

    function validateDistribution() external view returns (bool canDistribute, string memory reason) {
        if (isPaused) {
            return (false, "System is paused");
        }
        return (true, "");
    }

    function emergencyPause() external {
        isPaused = true;
    }

    function emergencyResume() external {
        isPaused = false;
    }

    function setCycleLength(uint256) external {}
    function setYieldFixedSplitDivisor(uint256) external {}
}

contract AutomationBaseTest is Test {
    ChainlinkAutomation public chainlinkAutomation;
    // GelatoAutomation public gelatoAutomation;
    MockDistributionManager public distributionManager;
    MockDistributionModule public distributionModule;

    address public chainlinkKeeper = address(0x1);
    // address public gelatoExecutor = address(0x2);

    event AutomationExecuted(address indexed executor, uint256 blockNumber);
    event DistributionExecuted(uint256 blockNumber, uint256 yield, uint256 votes);

    function setUp() public {
        // Deploy mock distribution module
        distributionModule = new MockDistributionModule();

        // Deploy distribution manager
        distributionManager = new MockDistributionManager(address(distributionModule), 100);

        // Deploy automation implementations
        chainlinkAutomation = new ChainlinkAutomation(address(distributionManager));
        // gelatoAutomation = new GelatoAutomation(address(distributionManager));

        // Setup initial state
        distributionManager.setCurrentVotes(100);
        distributionManager.setAvailableYield(2000);
    }

    function testChainlinkCheckUpkeep() public {
        // Initially should not need upkeep (too soon)
        (bool upkeepNeeded,) = chainlinkAutomation.checkUpkeep("");
        assertFalse(upkeepNeeded);

        // Advance blocks
        vm.roll(block.number + 101);

        // Now should need upkeep
        (upkeepNeeded,) = chainlinkAutomation.checkUpkeep("");
        assertTrue(upkeepNeeded);
    }

    function testChainlinkPerformUpkeep() public {
        // Advance blocks to make distribution ready
        vm.roll(block.number + 101);

        // Check upkeep
        (bool upkeepNeeded,) = chainlinkAutomation.checkUpkeep("");
        assertTrue(upkeepNeeded);

        // Perform upkeep
        vm.expectEmit(true, false, false, true);
        emit AutomationExecuted(chainlinkKeeper, block.number);

        vm.prank(chainlinkKeeper);
        chainlinkAutomation.performUpkeep("");

        // Verify distribution was called
        assertEq(distributionModule.distributeCallCount(), 1);
        assertEq(distributionManager.currentCycleNumber(), 2);
    }

    // function testGelatoChecker() public {
    //     // Initially should not be executable (too soon)
    //     (bool canExec, bytes memory execPayload) = gelatoAutomation.checker();
    //     assertFalse(canExec);

    //     // Advance blocks
    //     vm.roll(block.number + 101);

    //     // Now should be executable
    //     (canExec, execPayload) = gelatoAutomation.checker();
    //     assertTrue(canExec);
    //     assertGt(execPayload.length, 0);
    // }

    // function testGelatoExecute() public {
    //     // Advance blocks to make distribution ready
    //     vm.roll(block.number + 101);

    //     // Check if executable
    //     (bool canExec,) = gelatoAutomation.checker();
    //     assertTrue(canExec);

    //     // Execute
    //     vm.expectEmit(true, false, false, true);
    //     emit AutomationExecuted(gelatoExecutor, block.number);

    //     vm.prank(gelatoExecutor);
    //     gelatoAutomation.execute("");

    //     // Verify distribution was called
    //     assertEq(distributionModule.distributeCallCount(), 1);
    //     assertEq(distributionManager.currentCycleNumber(), 2);
    // }

    function testResolveDistributionConditions() public {
        // Test: Not enough blocks passed
        bool isReady = chainlinkAutomation.isDistributionReady();
        assertFalse(isReady);

        vm.roll(block.number + 101);

        // Test: No votes
        distributionManager.setCurrentVotes(0);
        isReady = chainlinkAutomation.isDistributionReady();
        assertFalse(isReady);

        // Test: Insufficient yield
        distributionManager.setCurrentVotes(100);
        distributionManager.setAvailableYield(500);
        isReady = chainlinkAutomation.isDistributionReady();
        assertFalse(isReady);

        // Test: System disabled
        distributionManager.setAvailableYield(2000);
        distributionManager.setEnabled(false);
        isReady = chainlinkAutomation.isDistributionReady();
        assertFalse(isReady);

        // Test: All conditions met
        distributionManager.setEnabled(true);
        isReady = chainlinkAutomation.isDistributionReady();
        assertTrue(isReady);

        // Test automation data is returned when ready
        bytes memory data = chainlinkAutomation.getAutomationData();
        assertGt(data.length, 0);
    }

    function testExecutionRevertsWhenNotResolved() public {
        // Try to execute when conditions not met
        vm.expectRevert(AbstractAutomation.NotResolved.selector);
        chainlinkAutomation.executeDistribution();
    }

    function testCycleManagerIntegration() public {
        // Check initial state
        assertEq(distributionManager.currentCycleNumber(), 1);
        assertEq(distributionManager.currentVotes(), 100);
        assertEq(distributionManager.availableYield(), 2000);

        // Advance and execute
        vm.roll(block.number + 101);
        chainlinkAutomation.executeDistribution();

        // Check state after execution
        assertEq(distributionManager.currentCycleNumber(), 2);
        assertEq(distributionManager.currentVotes(), 0); // Reset after distribution
        assertEq(distributionManager.availableYield(), 0); // Reset after distribution
        assertEq(distributionManager.getLastDistributionBlock(), block.number);
    }

    function testCycleInfo() public {
        (uint256 cycleNum, uint256 startBlock, uint256 endBlock) = distributionManager.getCycleInfo();
        assertEq(cycleNum, 1);
        assertEq(startBlock, block.number);
        assertEq(endBlock, block.number + 100);

        // Execute distribution
        vm.roll(block.number + 101);
        chainlinkAutomation.executeDistribution();

        // Check updated cycle info
        (cycleNum, startBlock, endBlock) = distributionManager.getCycleInfo();
        assertEq(cycleNum, 2);
        assertEq(startBlock, block.number);
        assertEq(endBlock, block.number + 100);
    }

    // function testBothAutomationTypesWork() public {
    //     // Test Chainlink automation
    //     vm.roll(block.number + 101);
    //     distributionManager.setCurrentVotes(100);
    //     distributionManager.setAvailableYield(2000);

    //     vm.prank(chainlinkKeeper);
    //     chainlinkAutomation.performUpkeep("");
    //     assertEq(distributionModule.distributeCallCount(), 1);

    //     // // Test Gelato automation
    //     // vm.roll(block.number + 101);
    //     // distributionManager.setCurrentVotes(100);
    //     // distributionManager.setAvailableYield(2000);

    //     // vm.prank(gelatoExecutor);
    //     // gelatoAutomation.execute("");
    //     // assertEq(distributionModule.distributeCallCount(), 2);
    // }

    function testMinYieldRequired() public {
        vm.roll(block.number + 101);

        // Set yield below minimum
        distributionManager.setAvailableYield(999);
        bool isReady = chainlinkAutomation.isDistributionReady();
        assertFalse(isReady);

        // Set yield at minimum
        distributionManager.setAvailableYield(1000);
        isReady = chainlinkAutomation.isDistributionReady();
        assertTrue(isReady);
    }
}
