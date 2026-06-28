// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AbstractAutomation} from "./AbstractAutomation.sol";
import {IAutomationPayment} from "../interfaces/IAutomationPayment.sol";

/// @title AbstractPaidAutomation
/// @notice Extends AbstractAutomation with a yield-sufficiency gate for paid automation providers.
/// @dev This layer only *validates* that the available yield covers the configured automation fee
///      (plus the minimum yield) before allowing execution. It does NOT itself transfer or settle
///      the fee: an automation contract has no custody of the yield token — the yield is held and
///      distributed by the DistributionManager via `claimAndDistribute()`. Actual fee settlement
///      (deducting the keeper fee from claimed yield and paying the provider) must be performed by
///      the DistributionManager; that integration is tracked as follow-up work for #73.
abstract contract AbstractPaidAutomation is AbstractAutomation {
    /// @notice The payment strategy that prices the automation fee
    IAutomationPayment public immutable PAYMENT_PROVIDER;

    /// @notice Thrown when the payment provider address is the zero address
    error ZeroPaymentProvider();

    /// @param _distributionManager The distribution manager address
    /// @param _paymentProvider The payment provider address
    constructor(address _distributionManager, address _paymentProvider) AbstractAutomation(_distributionManager) {
        if (_paymentProvider == address(0)) revert ZeroPaymentProvider();
        PAYMENT_PROVIDER = IAutomationPayment(_paymentProvider);
    }

    /// @notice Checks if distribution is ready, including yield sufficiency for fees
    /// @dev Extends the base readiness check with payment validation
    /// @return ready Whether the distribution is ready and yield is sufficient to cover the fee
    function isDistributionReady() public view virtual override returns (bool ready) {
        if (!super.isDistributionReady()) {
            return false;
        }
        // Additional check: is yield sufficient to cover the automation fee?
        return PAYMENT_PROVIDER.isYieldSufficient(_getAvailableYield());
    }

    /// @notice Executes the distribution after verifying paid-automation readiness
    /// @dev Gates on this contract's isDistributionReady() (which includes yield sufficiency)
    ///      before delegating to the parent, preventing bypass of the fee check
    function executeDistribution() public virtual override {
        if (!isDistributionReady()) revert NotResolved();
        super.executeDistribution();
    }

    /// @notice Returns the available yield used to evaluate fee sufficiency
    /// @dev Subclasses must override to query the actual yield source
    /// @return yield The available yield amount
    function _getAvailableYield() internal view virtual returns (uint256 yield);
}
