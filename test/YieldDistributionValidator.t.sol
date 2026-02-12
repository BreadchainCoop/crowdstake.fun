// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/libraries/YieldDistributionValidator.sol";

/// @dev Wrapper to make library calls external (so vm.expectRevert works)
contract ValidatorWrapper {
    function validateYieldDistribution(uint256 yieldAmount, uint256 recipientCount) external pure {
        YieldDistributionValidator.validateYieldDistribution(yieldAmount, recipientCount);
    }

    function validateYieldForVotingPower(uint256 yieldAmount, uint256 recipientCount) external pure {
        YieldDistributionValidator.validateYieldForVotingPower(yieldAmount, recipientCount);
    }

    function calculateDistributionRemainder(uint256 yieldAmount, uint256 recipientCount) external pure returns (uint256) {
        return YieldDistributionValidator.calculateDistributionRemainder(yieldAmount, recipientCount);
    }
}

contract YieldDistributionValidatorTest is Test {
    ValidatorWrapper public wrapper;

    function setUp() public {
        wrapper = new ValidatorWrapper();
    }

    function test_ValidateYieldDistribution_Valid() public view {
        wrapper.validateYieldDistribution(100, 10);
        wrapper.validateYieldDistribution(1, 1);
    }

    function test_ValidateYieldDistribution_RevertNoRecipients() public {
        vm.expectRevert(YieldDistributionValidator.NoRecipientsForDistribution.selector);
        wrapper.validateYieldDistribution(100, 0);
    }

    function test_ValidateYieldDistribution_RevertInsufficientYield() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                YieldDistributionValidator.InsufficientYieldForRecipients.selector,
                5,
                10
            )
        );
        wrapper.validateYieldDistribution(5, 10);
    }

    function test_ValidateYieldForVotingPower() public view {
        wrapper.validateYieldForVotingPower(1000, 10);
    }

    function test_CalculateDistributionRemainder() public view {
        assertEq(wrapper.calculateDistributionRemainder(100, 3), 1);
        assertEq(wrapper.calculateDistributionRemainder(100, 10), 0);
        assertEq(wrapper.calculateDistributionRemainder(7, 3), 1);
    }

    function test_CalculateDistributionRemainder_RevertZero() public {
        vm.expectRevert(YieldDistributionValidator.NoRecipientsForDistribution.selector);
        wrapper.calculateDistributionRemainder(100, 0);
    }
}
