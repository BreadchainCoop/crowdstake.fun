// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AbstractAutomation} from "./AbstractAutomation.sol";
import {IAutomationPayment} from "../interfaces/IAutomationPayment.sol";

/// @title AbstractPaidAutomation
/// @notice Extends AbstractAutomation with payment validation for automation providers
/// @dev Adds yield sufficiency checks and fee deduction logic on top of base automation
abstract contract AbstractPaidAutomation is AbstractAutomation {
    IAutomationPayment public immutable PAYMENT_PROVIDER;

    /// @notice Emitted when an automation fee is deducted from yield
    /// @param fee The fee amount deducted
    /// @param remainingYield The yield remaining after fee deduction
    event AutomationFeeDeducted(uint256 fee, uint256 remainingYield);

    /// @notice Thrown when yield is insufficient to cover fees and minimum yield
    error InsufficientYieldForFee();

    /// @param _distributionManager The distribution manager address
    /// @param _paymentProvider The payment provider address
    constructor(address _distributionManager, address _paymentProvider) AbstractAutomation(_distributionManager) {
        require(_paymentProvider != address(0), "Invalid payment provider");
        PAYMENT_PROVIDER = IAutomationPayment(_paymentProvider);
    }

    /// @notice Checks if distribution is ready, including yield sufficiency for fees
    /// @dev Extends base readiness check with payment validation
    /// @return ready Whether the distribution is ready and yield is sufficient
    function isDistributionReady() public view virtual override returns (bool ready) {
        if (!super.isDistributionReady()) {
            return false;
        }
        // Additional check: is yield sufficient to cover automation fees?
        uint256 availableYield = _getAvailableYield();
        return PAYMENT_PROVIDER.isYieldSufficient(availableYield);
    }

    /// @notice Deducts the automation fee from the total yield
    /// @param totalYield The total yield before fee deduction
    /// @return remainingYield The yield remaining after the fee
    function _deductFee(uint256 totalYield) internal returns (uint256 remainingYield) {
        uint256 fee = PAYMENT_PROVIDER.calculateFee(totalYield);
        if (fee > totalYield) revert InsufficientYieldForFee();

        remainingYield = totalYield - fee;
        emit AutomationFeeDeducted(fee, remainingYield);
    }

    /// @notice Returns the available yield for distribution
    /// @dev Subclasses may override to query the actual yield source
    /// @return yield The available yield amount
    function _getAvailableYield() internal view virtual returns (uint256 yield);
}
