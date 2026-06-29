// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IAutomationPayment} from "../../interfaces/IAutomationPayment.sol";

/// @title PercentagePayment
/// @notice Implements IAutomationPayment with a percentage-based fee
/// @dev Fee is calculated as a percentage of total yield using basis points (10000 = 100%)
contract PercentagePayment is IAutomationPayment {
    uint256 public constant BASIS_POINTS_DENOMINATOR = 10_000;

    uint256 public immutable BASIS_POINTS;
    uint256 public immutable MINIMUM_YIELD;

    /// @notice Thrown when basis points exceed 10000 (100%)
    error InvalidBasisPoints();

    /// @param _basisPoints Fee percentage in basis points (e.g. 500 = 5%)
    /// @param _minimumYield The minimum yield required after fee deduction
    constructor(uint256 _basisPoints, uint256 _minimumYield) {
        if (_basisPoints > BASIS_POINTS_DENOMINATOR) revert InvalidBasisPoints();
        BASIS_POINTS = _basisPoints;
        MINIMUM_YIELD = _minimumYield;
    }

    /// @inheritdoc IAutomationPayment
    function calculateFee(uint256 totalYield) external view override returns (uint256 fee) {
        return _fee(totalYield);
    }

    /// @inheritdoc IAutomationPayment
    function getPaymentConfig() external view override returns (PaymentConfig memory config) {
        return PaymentConfig({
            strategy: PaymentStrategy.PERCENTAGE_BASED, feeValue: BASIS_POINTS, minimumYield: MINIMUM_YIELD
        });
    }

    /// @inheritdoc IAutomationPayment
    function isYieldSufficient(uint256 totalYield) external view override returns (bool sufficient) {
        uint256 fee = _fee(totalYield);
        if (fee > totalYield) return false;
        return totalYield - fee >= MINIMUM_YIELD;
    }

    /// @notice Computes the basis-points fee for a yield amount
    /// @dev Division-first to avoid overflow on large values:
    ///      fee = (totalYield / DENOMINATOR) * BASIS_POINTS + (totalYield % DENOMINATOR) * BASIS_POINTS / DENOMINATOR
    ///      Single source of truth shared by calculateFee() and isYieldSufficient().
    function _fee(uint256 totalYield) internal view returns (uint256) {
        return (totalYield / BASIS_POINTS_DENOMINATOR) * BASIS_POINTS + (totalYield % BASIS_POINTS_DENOMINATOR)
            * BASIS_POINTS / BASIS_POINTS_DENOMINATOR;
    }
}
