// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IAutomationPayment
/// @notice Interface for automation payment strategies
/// @dev Implementations define how automation provider fees are calculated and validated
interface IAutomationPayment {
    /// @notice Payment strategy type
    enum PaymentStrategy {
        FIXED_FEE,
        PERCENTAGE_BASED
    }

    /// @notice Configuration for automation payments
    /// @dev `feeValue` is strategy-dependent — read it together with `strategy`:
    ///      for FIXED_FEE it is an absolute token amount; for PERCENTAGE_BASED it is basis points.
    /// @param strategy The payment strategy to use
    /// @param feeValue Absolute fee amount (FIXED_FEE) or fee in basis points (PERCENTAGE_BASED)
    /// @param minimumYield Minimum yield required after fee deduction
    struct PaymentConfig {
        PaymentStrategy strategy;
        uint256 feeValue;
        uint256 minimumYield;
    }

    /// @notice Calculates the automation fee for a given yield amount
    /// @param totalYield The total yield available for distribution
    /// @return fee The fee amount to deduct
    function calculateFee(uint256 totalYield) external view returns (uint256 fee);

    /// @notice Returns the current payment configuration
    /// @return config The payment configuration
    function getPaymentConfig() external view returns (PaymentConfig memory config);

    /// @notice Checks whether the yield is sufficient to cover fees and minimum yield
    /// @param totalYield The total yield available
    /// @return sufficient Whether the yield meets the minimum threshold after fees
    function isYieldSufficient(uint256 totalYield) external view returns (bool sufficient);
}
