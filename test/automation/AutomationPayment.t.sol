// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IAutomationPayment} from "../../src/interfaces/IAutomationPayment.sol";
import {FixedFeePayment} from "../../src/implementation/automation/FixedFeePayment.sol";
import {PercentagePayment} from "../../src/implementation/automation/PercentagePayment.sol";
import {AbstractPaidAutomation} from "../../src/abstract/AbstractPaidAutomation.sol";
import {MockDistributionManager} from "../mocks/MockDistributionManager.sol";
import {IDistributionModule} from "../../src/interfaces/IDistributionModule.sol";
import {IRecipientRegistry} from "../../src/interfaces/IRecipientRegistry.sol";
import {ICycleModule} from "../../src/interfaces/ICycleModule.sol";

/// @notice Minimal mock distribution module for testing
contract MockDistModule is IDistributionModule {
    uint256 public distributeCallCount;

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
        address[] memory recipients = new address[](0);
        uint256[] memory empty = new uint256[](0);
        state = DistributionState({
            totalYield: 100,
            fixedAmount: 0,
            votedAmount: 100,
            totalVotes: 100,
            lastDistributionBlock: block.number - 100,
            cycleNumber: 1,
            recipients: recipients,
            votedDistributions: empty,
            fixedDistributions: empty
        });
    }

    function validateDistribution() external pure returns (bool canDistribute, string memory reason) {
        return (true, "");
    }

    function emergencyPause() external {}
    function emergencyResume() external {}
    function setCycleLength(uint256) external {}
    function setYieldFixedSplitDivisor(uint256) external {}
}

/// @notice Concrete implementation of AbstractPaidAutomation for testing
contract MockPaidAutomation is AbstractPaidAutomation {
    uint256 private _availableYield;

    constructor(address _distributionManager, address _paymentProvider)
        AbstractPaidAutomation(_distributionManager, _paymentProvider)
    {}

    function setAvailableYield(uint256 yield_) external {
        _availableYield = yield_;
    }

    function _getAvailableYield() internal view override returns (uint256) {
        return _availableYield;
    }
}

// ============================================================
// FixedFeePayment Tests
// ============================================================

contract FixedFeePayment_CalculateFee_Test is Test {
    FixedFeePayment public payment;

    function setUp() public {
        payment = new FixedFeePayment(100, 500);
    }

    function test_WhenCalculatingFee_ShouldReturnConstantFeeAmount() public view {
        assertEq(payment.calculateFee(10_000), 100);
    }

    function test_WhenCalculatingFee_ShouldReturnSameFeeRegardlessOfYield() public view {
        assertEq(payment.calculateFee(0), 100);
        assertEq(payment.calculateFee(1), 100);
        assertEq(payment.calculateFee(type(uint256).max), 100);
    }
}

contract FixedFeePayment_IsYieldSufficient_Test is Test {
    FixedFeePayment public payment;

    function setUp() public {
        payment = new FixedFeePayment(100, 500);
    }

    function test_WhenYieldIsBelowFeeAndMinimum_ShouldReturnFalse() public view {
        assertFalse(payment.isYieldSufficient(0));
        assertFalse(payment.isYieldSufficient(99));
        assertFalse(payment.isYieldSufficient(500));
        assertFalse(payment.isYieldSufficient(599));
    }

    function test_WhenYieldEqualsFeePlusMinimum_ShouldReturnTrue() public view {
        assertTrue(payment.isYieldSufficient(600));
    }

    function test_WhenYieldExceedsFeePlusMinimum_ShouldReturnTrue() public view {
        assertTrue(payment.isYieldSufficient(1000));
        assertTrue(payment.isYieldSufficient(10_000));
    }
}

contract FixedFeePayment_GetPaymentConfig_Test is Test {
    FixedFeePayment public payment;

    function setUp() public {
        payment = new FixedFeePayment(100, 500);
    }

    function test_WhenGettingPaymentConfig_ShouldReturnCorrectValues() public view {
        IAutomationPayment.PaymentConfig memory config = payment.getPaymentConfig();
        assertEq(uint256(config.strategy), uint256(IAutomationPayment.PaymentStrategy.FIXED_FEE));
        assertEq(config.feeValue, 100);
        assertEq(config.minimumYield, 500);
    }
}

contract FixedFeePayment_EdgeCases_Test is Test {
    function test_WhenFeeIsZero_ShouldWorkCorrectly() public {
        FixedFeePayment payment = new FixedFeePayment(0, 100);
        assertEq(payment.calculateFee(1000), 0);
        assertTrue(payment.isYieldSufficient(100));
        assertFalse(payment.isYieldSufficient(99));
    }

    function test_WhenMinimumYieldIsZero_ShouldWorkCorrectly() public {
        FixedFeePayment payment = new FixedFeePayment(50, 0);
        assertTrue(payment.isYieldSufficient(50));
        assertFalse(payment.isYieldSufficient(49));
    }

    function test_WhenBothAreZero_ShouldAlwaysBeSufficient() public {
        FixedFeePayment payment = new FixedFeePayment(0, 0);
        assertTrue(payment.isYieldSufficient(0));
    }
}

// ============================================================
// PercentagePayment Tests
// ============================================================

contract PercentagePayment_CalculateFee_Test is Test {
    PercentagePayment public payment;

    function setUp() public {
        // 5% fee (500 basis points), 100 minimum yield
        payment = new PercentagePayment(500, 100);
    }

    function test_WhenCalculatingFee_ShouldReturnCorrectPercentage() public view {
        // 5% of 10000 = 500
        assertEq(payment.calculateFee(10_000), 500);
    }

    function test_WhenCalculatingFee_ShouldHandleSmallYields() public view {
        // 5% of 100 = 5
        assertEq(payment.calculateFee(100), 5);
    }

    function test_WhenCalculatingFee_ShouldHandleZeroYield() public view {
        assertEq(payment.calculateFee(0), 0);
    }

    function test_WhenCalculatingFee_ShouldRoundDown() public view {
        // 5% of 99 = 4.95, should round down to 4
        assertEq(payment.calculateFee(99), 4);
    }
}

contract PercentagePayment_IsYieldSufficient_Test is Test {
    PercentagePayment public payment;

    function setUp() public {
        // 10% fee (1000 basis points), 100 minimum yield
        payment = new PercentagePayment(1000, 100);
    }

    function test_WhenRemainingYieldBelowMinimum_ShouldReturnFalse() public view {
        // yield=100, fee=10, remaining=90 < 100 minimum
        assertFalse(payment.isYieldSufficient(100));
    }

    function test_WhenRemainingYieldEqualsMinimum_ShouldReturnTrue() public view {
        // yield ~= 112, fee = 11, remaining = 101; try exact: yield=112 -> fee=11, rem=101
        // We need remaining >= 100. yield - yield*10% >= 100 => yield*90% >= 100 => yield >= 112
        // yield=112, fee=11, remaining=101
        assertTrue(payment.isYieldSufficient(112));
    }

    function test_WhenRemainingYieldAboveMinimum_ShouldReturnTrue() public view {
        // yield=1000, fee=100, remaining=900
        assertTrue(payment.isYieldSufficient(1000));
    }

    function test_WhenYieldIsZero_ShouldReturnFalse() public view {
        assertFalse(payment.isYieldSufficient(0));
    }
}

contract PercentagePayment_BasisPointsValidation_Test is Test {
    function test_WhenBasisPointsExceed10000_ShouldRevert() public {
        vm.expectRevert(PercentagePayment.InvalidBasisPoints.selector);
        new PercentagePayment(10_001, 100);
    }

    function test_WhenBasisPointsEqual10000_ShouldNotRevert() public {
        PercentagePayment payment = new PercentagePayment(10_000, 0);
        assertEq(payment.calculateFee(1000), 1000);
    }

    function test_WhenBasisPointsAreZero_ShouldNotRevert() public {
        PercentagePayment payment = new PercentagePayment(0, 100);
        assertEq(payment.calculateFee(1000), 0);
        assertTrue(payment.isYieldSufficient(100));
    }
}

contract PercentagePayment_GetPaymentConfig_Test is Test {
    function test_WhenGettingPaymentConfig_ShouldReturnCorrectValues() public {
        PercentagePayment payment = new PercentagePayment(500, 200);
        IAutomationPayment.PaymentConfig memory config = payment.getPaymentConfig();
        assertEq(uint256(config.strategy), uint256(IAutomationPayment.PaymentStrategy.PERCENTAGE_BASED));
        assertEq(config.feeValue, 500);
        assertEq(config.minimumYield, 200);
    }
}

// ============================================================
// AbstractPaidAutomation Tests
// ============================================================

contract AbstractPaidAutomation_IsDistributionReady_Test is Test {
    MockPaidAutomation public automation;
    MockDistributionManager public distributionManager;
    FixedFeePayment public fixedPayment;
    MockDistModule public distModule;

    function setUp() public {
        distModule = new MockDistModule();
        distributionManager = new MockDistributionManager(address(distModule), 100);
        fixedPayment = new FixedFeePayment(100, 500);
        automation = new MockPaidAutomation(address(distributionManager), address(fixedPayment));

        // Set up distribution manager to be ready
        distributionManager.setCurrentVotes(100);
        distributionManager.setAvailableYield(2000);

        // Set available yield for the automation
        automation.setAvailableYield(2000);
    }

    function test_WhenBaseNotReady_ShouldReturnFalse() public view {
        // Not enough blocks passed
        assertFalse(automation.isDistributionReady());
    }

    function test_WhenBaseReadyButYieldInsufficient_ShouldReturnFalse() public {
        vm.roll(block.number + 101);
        automation.setAvailableYield(500); // Below 100 fee + 500 minimum = 600
        assertFalse(automation.isDistributionReady());
    }

    function test_WhenBaseReadyAndYieldSufficient_ShouldReturnTrue() public {
        vm.roll(block.number + 101);
        automation.setAvailableYield(1000); // Above 100 fee + 500 minimum = 600
        assertTrue(automation.isDistributionReady());
    }
}

contract AbstractPaidAutomation_Constructor_Test is Test {
    MockDistModule public distModule;
    MockDistributionManager public distributionManager;
    FixedFeePayment public fixedPayment;

    function setUp() public {
        distModule = new MockDistModule();
        distributionManager = new MockDistributionManager(address(distModule), 100);
        fixedPayment = new FixedFeePayment(100, 500);
    }

    function test_RevertWhen_PaymentProviderIsZeroAddress() public {
        vm.expectRevert(AbstractPaidAutomation.ZeroPaymentProvider.selector);
        new MockPaidAutomation(address(distributionManager), address(0));
    }

    function test_RevertWhen_DistributionManagerIsZeroAddress() public {
        vm.expectRevert("Invalid distribution manager");
        new MockPaidAutomation(address(0), address(fixedPayment));
    }

    function test_WhenConstructedWithValidArgs_ShouldSetImmutables() public {
        MockPaidAutomation auto_ = new MockPaidAutomation(address(distributionManager), address(fixedPayment));
        assertEq(address(auto_.DISTRIBUTION_MANAGER()), address(distributionManager));
        assertEq(address(auto_.PAYMENT_PROVIDER()), address(fixedPayment));
    }
}

// ============================================================
// Integration: PaidAutomation with PercentagePayment
// ============================================================

contract PaidAutomation_Integration_Test is Test {
    MockPaidAutomation public automation;
    MockDistributionManager public distributionManager;
    PercentagePayment public percentagePayment;
    MockDistModule public distModule;

    function setUp() public {
        distModule = new MockDistModule();
        distributionManager = new MockDistributionManager(address(distModule), 100);
        // 5% fee, 100 minimum yield
        percentagePayment = new PercentagePayment(500, 100);
        automation = new MockPaidAutomation(address(distributionManager), address(percentagePayment));

        distributionManager.setCurrentVotes(50);
        distributionManager.setAvailableYield(2000);
    }

    function test_WhenYieldBarelySufficient_ShouldBeReady() public {
        vm.roll(block.number + 101);
        // Need remaining >= 100. yield * 95% >= 100 => yield >= 106
        automation.setAvailableYield(106);
        assertTrue(automation.isDistributionReady());
    }

    function test_WhenYieldBarelyInsufficient_ShouldNotBeReady() public {
        vm.roll(block.number + 101);
        // yield=105 -> fee=5, remaining=100 >= 100 -> sufficient
        // yield=104 -> fee=5, remaining=99 < 100 -> insufficient
        automation.setAvailableYield(104);
        assertFalse(automation.isDistributionReady());
    }

    function test_WhenExecutingFullFlow_ShouldGateOnYieldAndDistribute() public {
        vm.roll(block.number + 101);
        automation.setAvailableYield(10_000);

        // Yield (10000) covers the 5% fee + 100 minimum, so the gate passes
        assertTrue(automation.isDistributionReady());

        // Execute distribution through the base contract
        automation.executeDistribution();

        // Verify distribution happened and the cycle advanced.
        // NOTE: this layer only gates on fee sufficiency; it does not itself settle the
        // fee (the DistributionManager owns the yield). See AbstractPaidAutomation NatSpec.
        assertEq(distModule.distributeCallCount(), 1);
        assertEq(distributionManager.currentCycleNumber(), 2);
    }
}
