// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IAutomationPayment} from "../../interfaces/IAutomationPayment.sol";

/// @title FixedFeePayment
/// @notice Implements IAutomationPayment with a fixed fee per execution
/// @dev The fee is a constant amount regardless of total yield
contract FixedFeePayment is IAutomationPayment {
    uint256 public immutable FEE_AMOUNT;
    uint256 public immutable MINIMUM_YIELD;

    /// @param _feeAmount The fixed fee amount charged per execution
    /// @param _minimumYield The minimum yield required after fee deduction
    constructor(uint256 _feeAmount, uint256 _minimumYield) {
        FEE_AMOUNT = _feeAmount;
        MINIMUM_YIELD = _minimumYield;
    }

    /// @inheritdoc IAutomationPayment
    function calculateFee(
        uint256 /* totalYield */
    )
        external
        view
        override
        returns (uint256 fee)
    {
        return FEE_AMOUNT;
    }

    /// @inheritdoc IAutomationPayment
    function getPaymentConfig() external view override returns (PaymentConfig memory config) {
        return PaymentConfig({strategy: PaymentStrategy.FIXED_FEE, feeValue: FEE_AMOUNT, minimumYield: MINIMUM_YIELD});
    }

    /// @inheritdoc IAutomationPayment
    function isYieldSufficient(uint256 totalYield) external view override returns (bool sufficient) {
        return totalYield >= FEE_AMOUNT && totalYield - FEE_AMOUNT >= MINIMUM_YIELD;
    }
}
