// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {EqualDistributionStrategy} from "../../src/implementation/strategies/EqualDistributionStrategy.sol";
import {AbstractDistributionStrategy} from "../../src/abstract/AbstractDistributionStrategy.sol";
import {AdminRecipientRegistry} from "../../src/implementation/registries/AdminRecipientRegistry.sol";
import {IRecipientRegistry} from "../../src/interfaces/IRecipientRegistry.sol";
import {MockERC20} from "./helpers/MockERC20.sol";
import {MockDistManagerForFuzz} from "./helpers/MockDistManagerForFuzz.sol";

/// @notice Fuzz tests for EqualDistributionStrategy — equal split math, dust retention, and revert paths (no fork).
contract EqualDistributionStrategy_FuzzTest is Test {
    uint256 internal constant MAX_RECIPIENTS = 48;

    /// @notice Happy-path invariants:
    ///         - each recipient receives exactly `amount / n`
    ///         - total paid out equals `(amount / n) * n`
    ///         - dust (`amount % n`) remains on the strategy
    ///         - `distributionId` increments by exactly 1
    function testFuzz_distribute_equalSplitAndDust(uint8 recipientCountRaw, uint256 amountRaw) public {
        uint256 n = bound(uint256(recipientCountRaw), 1, MAX_RECIPIENTS);
        // Lower bound = n so the strategy has enough yield for 1 wei per recipient.
        uint256 amount = bound(amountRaw, n, n * 1e24);

        (
            MockERC20 token,
            AdminRecipientRegistry registry,
            MockDistManagerForFuzz distManager,
            EqualDistributionStrategy strategy
        ) = _deploySystem(n);

        // Pre-fund the strategy. In production the manager calls `safeTransfer` before `distribute`;
        // we shortcut by minting directly since `distribute` is what we are fuzzing.
        token.mint(address(strategy), amount);
        uint256 idBefore = strategy.distributionId();

        // Act
        vm.prank(address(distManager));
        strategy.distribute(amount);

        // Invariant: distributionId incremented by 1
        assertEq(strategy.distributionId(), idBefore + 1, "distributionId must increment");

        uint256 per = amount / n;
        uint256 dust = amount % n;
        address[] memory recipients = registry.getRecipients();
        assertEq(recipients.length, n);

        // Invariant: each recipient got `per`; sum equals `per * n`
        uint256 paidOut;
        for (uint256 i; i < n; i++) {
            assertEq(token.balanceOf(recipients[i]), per, "recipient share must be amount / n");
            paidOut += token.balanceOf(recipients[i]);
        }
        assertEq(paidOut, per * n, "sum of shares must equal per * n");

        // Invariant: leftover dust stays on the strategy
        assertEq(token.balanceOf(address(strategy)), dust, "dust must remain on strategy");
    }

    /// @notice Revert when `amount < n` — cannot fund at least 1 wei per recipient.
    function testFuzz_distribute_reverts_insufficientYield(uint256 nRaw, uint256 amountRaw) public {
        uint256 n = bound(nRaw, 2, MAX_RECIPIENTS);
        uint256 amount = bound(amountRaw, 1, n - 1);

        (,, MockDistManagerForFuzz distManager, EqualDistributionStrategy strategy) = _deploySystem(n);

        // Revert fires before any transfer, so no pre-fund needed.
        vm.prank(address(distManager));
        vm.expectRevert(AbstractDistributionStrategy.InsufficientYieldForRecipients.selector);
        strategy.distribute(amount);
    }

    /// @notice Revert on zero amount regardless of recipient count.
    function test_distribute_reverts_zeroAmount() public {
        (,, MockDistManagerForFuzz distManager, EqualDistributionStrategy strategy) = _deploySystem(1);

        vm.prank(address(distManager));
        vm.expectRevert(AbstractDistributionStrategy.ZeroAmount.selector);
        strategy.distribute(0);
    }

    /// @notice Only the configured distribution manager can call `distribute`.
    function testFuzz_distribute_reverts_notDistributionManager(address caller, uint256 amountRaw) public {
        uint256 amount = bound(amountRaw, 1, 1e24);

        (,, MockDistManagerForFuzz distManager, EqualDistributionStrategy strategy) = _deploySystem(2);
        vm.assume(caller != address(distManager));

        vm.prank(caller);
        vm.expectRevert(AbstractDistributionStrategy.OnlyDistributionManager.selector);
        strategy.distribute(amount);
    }

    function _deploySystem(uint256 n)
        internal
        returns (
            MockERC20 token,
            AdminRecipientRegistry registry,
            MockDistManagerForFuzz distManager,
            EqualDistributionStrategy strategy
        )
    {
        address admin = address(this);
        token = new MockERC20();

        // Deploy registry behind ERC1967 proxy (matches production tests).
        AdminRecipientRegistry regImpl = new AdminRecipientRegistry();
        bytes memory regInit = abi.encodeWithSelector(AdminRecipientRegistry.initialize.selector, admin);
        registry = AdminRecipientRegistry(address(new ERC1967Proxy(address(regImpl), regInit)));

        // Labeled, deterministic recipient addresses — avoids duplicate-queue reverts and reads nicely in traces.
        address[] memory batch = new address[](n);
        for (uint256 i; i < n; i++) {
            batch[i] = makeAddr(string.concat("recipient-", vm.toString(i)));
        }
        registry.queueRecipientsAddition(batch);
        registry.processQueue();

        // Mock manager exists only to satisfy `initialize()` and be the `onlyDistributionManager` caller.
        distManager = new MockDistManagerForFuzz(IRecipientRegistry(address(registry)));

        // Deploy strategy behind ERC1967 proxy (matches production tests).
        EqualDistributionStrategy stratImpl = new EqualDistributionStrategy();
        bytes memory stratInit = abi.encodeWithSelector(
            EqualDistributionStrategy.initialize.selector, address(token), address(distManager), admin
        );
        strategy = EqualDistributionStrategy(address(new ERC1967Proxy(address(stratImpl), stratInit)));

        // Sanity-check wiring before test body runs.
        assertEq(registry.getRecipientCount(), n);
        assertEq(address(strategy.recipientRegistry()), address(registry));
        assertEq(strategy.distributionManager(), address(distManager));
        assertEq(address(strategy.yieldToken()), address(token));
    }
}
