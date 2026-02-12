// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title YieldDistributionValidator
/// @notice Library for validating yield distribution parameters
/// @dev Ensures yield amounts are sufficient and divisible for fair distribution (issue #38)
/// @author BreadKit Protocol
library YieldDistributionValidator {
    /// @notice Thrown when yield amount is less than the number of recipients
    error InsufficientYieldForRecipients(uint256 yieldAmount, uint256 recipientCount);

    /// @notice Thrown when recipients array is empty
    error NoRecipientsForDistribution();

    /// @notice Thrown when yield per recipient would underflow in voting power calculation
    error YieldUnderflowInVotingPower(uint256 yieldPerRecipient, uint256 votingPowerBase);

    /// @notice The base for voting power representation (1e18)
    uint256 internal constant VOTING_POWER_BASE = 1e18;

    /// @notice Validates that yield amount can be fairly distributed among recipients
    /// @param yieldAmount The total yield amount in wei
    /// @param recipientCount The number of recipients
    function validateYieldDistribution(uint256 yieldAmount, uint256 recipientCount) internal pure {
        if (recipientCount == 0) revert NoRecipientsForDistribution();
        if (yieldAmount < recipientCount) {
            revert InsufficientYieldForRecipients(yieldAmount, recipientCount);
        }
    }

    /// @notice Validates yield amount is sufficient for voting power calculations
    /// @dev Ensures (yieldAmount / recipientCount) won't cause precision loss in 1e18 math
    /// @param yieldAmount The total yield amount in wei
    /// @param recipientCount The number of recipients
    function validateYieldForVotingPower(uint256 yieldAmount, uint256 recipientCount) internal pure {
        if (recipientCount == 0) revert NoRecipientsForDistribution();
        if (yieldAmount < recipientCount) {
            revert InsufficientYieldForRecipients(yieldAmount, recipientCount);
        }

        uint256 yieldPerRecipient = yieldAmount / recipientCount;
        // Ensure yield per recipient is meaningful when used with 1e18 voting power
        if (yieldPerRecipient == 0) {
            revert YieldUnderflowInVotingPower(yieldPerRecipient, VOTING_POWER_BASE);
        }
    }

    /// @notice Calculate the remainder that would be lost in equal distribution
    /// @param yieldAmount The total yield amount in wei
    /// @param recipientCount The number of recipients
    /// @return remainder The undistributable dust amount
    function calculateDistributionRemainder(uint256 yieldAmount, uint256 recipientCount)
        internal
        pure
        returns (uint256 remainder)
    {
        if (recipientCount == 0) revert NoRecipientsForDistribution();
        return yieldAmount % recipientCount;
    }
}
