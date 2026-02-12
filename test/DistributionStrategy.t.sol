// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/modules/DistributionStrategy.sol";

contract DistributionStrategyTest is Test {
    DistributionStrategy public strategy;

    event DistributionCalculated(uint256 indexed distributionId, uint256 totalYield, uint256 fixedAmount, uint256 votedAmount);
    event StrategyDivisorUpdated(uint256 oldDivisor, uint256 newDivisor);

    function setUp() public {
        strategy = new DistributionStrategy();
        strategy.initialize(address(this), 2); // 50/50 split
    }

    function test_Initialize() public view {
        assertEq(strategy.getStrategyDivisor(), 2);
        assertEq(strategy.getDistributionCount(), 0);
        assertEq(strategy.owner(), address(this));
    }

    function test_PreviewDistribution() public view {
        (uint256 fixedAmount, uint256 votedAmount) = strategy.previewDistribution(1000 ether);
        assertEq(fixedAmount, 500 ether);
        assertEq(votedAmount, 500 ether);
    }

    function test_PreviewDistribution_OddAmount() public view {
        (uint256 fixedAmount, uint256 votedAmount) = strategy.previewDistribution(1001);
        assertEq(fixedAmount, 500);
        assertEq(votedAmount, 501); // remainder goes to voted
    }

    function test_CalculateDistribution_EmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit DistributionCalculated(1, 1000 ether, 500 ether, 500 ether);

        strategy.calculateDistribution(1000 ether);
        assertEq(strategy.getDistributionCount(), 1);
    }

    function test_CalculateDistribution_IncrementsId() public {
        strategy.calculateDistribution(1000 ether);
        strategy.calculateDistribution(2000 ether);
        assertEq(strategy.getDistributionCount(), 2);
    }

    function test_UpdateDivisor() public {
        vm.expectEmit(false, false, false, true);
        emit StrategyDivisorUpdated(2, 4);

        strategy.updateStrategyDivisor(4);
        assertEq(strategy.getStrategyDivisor(), 4);

        (uint256 fixedAmount, uint256 votedAmount) = strategy.previewDistribution(1000 ether);
        assertEq(fixedAmount, 250 ether);
        assertEq(votedAmount, 750 ether);
    }

    function test_RevertOnZeroDivisor() public {
        vm.expectRevert(DistributionStrategy.InvalidDivisor.selector);
        strategy.updateStrategyDivisor(0);
    }

    function test_RevertOnZeroDivisorInit() public {
        DistributionStrategy s = new DistributionStrategy();
        vm.expectRevert(DistributionStrategy.InvalidDivisor.selector);
        s.initialize(address(this), 0);
    }

    function test_OnlyOwnerCanUpdateDivisor() public {
        vm.prank(address(0xdead));
        vm.expectRevert();
        strategy.updateStrategyDivisor(3);
    }

    function test_DivisorOfOne() public {
        strategy.updateStrategyDivisor(1);
        (uint256 fixedAmount, uint256 votedAmount) = strategy.previewDistribution(1000 ether);
        assertEq(fixedAmount, 1000 ether);
        assertEq(votedAmount, 0);
    }
}
