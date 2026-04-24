// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {EqualDistributionStrategy} from "../../src/implementation/strategies/EqualDistributionStrategy.sol";
import {AbstractDistributionStrategy} from "../../src/abstract/AbstractDistributionStrategy.sol";
import {AdminRecipientRegistry} from "../../src/implementation/registries/AdminRecipientRegistry.sol";
import {IRecipientRegistry} from "../../src/interfaces/IRecipientRegistry.sol";
import {MockERC20} from "./helpers/MockERC20.sol";
import {MockDistributionManagerForFuzz} from "./helpers/MockDistributionManager.sol";

/// @notice Phase 1 smoke fuzzing: equal split math, dust retention, and revert conditions (no RPC fork).
contract EqualDistributionStrategy_FuzzTest is Test {
    function testFuzz_distribute_equalSplitAndDust(uint8 recipientCountRaw, uint256 amountRaw) public {
        uint256 n = bound(uint256(recipientCountRaw), 1, 48);
        uint256 amount = bound(amountRaw, n, n * 1e24);

        (
            MockERC20 token,
            AdminRecipientRegistry registry,
            MockDistributionManagerForFuzz distManager,
            EqualDistributionStrategy strategy
        ) = _deploySystem(n);

        token.mint(address(strategy), amount);
        uint256 idBefore = strategy.distributionId();

        vm.prank(address(distManager));
        strategy.distribute(amount);

        assertEq(strategy.distributionId(), idBefore + 1);

        uint256 per = amount / n;
        uint256 dust = amount % n;
        address[] memory recipients = registry.getRecipients();
        assertEq(recipients.length, n);

        uint256 paidOut;
        for (uint256 i; i < n; i++) {
            uint256 b = token.balanceOf(recipients[i]);
            assertEq(b, per);
            paidOut += b;
        }
        assertEq(paidOut, per * n);
        assertEq(token.balanceOf(address(strategy)), dust);
    }

    function testFuzz_distribute_reverts_insufficientYield(uint256 nRaw, uint256 amountRaw) public {
        uint256 n = bound(nRaw, 2, 48);
        uint256 amount = bound(amountRaw, 1, n - 1);

        (MockERC20 token,, MockDistributionManagerForFuzz distManager, EqualDistributionStrategy strategy) =
            _deploySystem(n);

        token.mint(address(strategy), amount);

        vm.prank(address(distManager));
        vm.expectRevert(AbstractDistributionStrategy.InsufficientYieldForRecipients.selector);
        strategy.distribute(amount);
    }

    function testFuzz_distribute_reverts_zeroAmount(uint256 nRaw) public {
        uint256 n = bound(nRaw, 1, 48);

        (,, MockDistributionManagerForFuzz distManager, EqualDistributionStrategy strategy) = _deploySystem(n);

        vm.prank(address(distManager));
        vm.expectRevert(AbstractDistributionStrategy.ZeroAmount.selector);
        strategy.distribute(0);
    }

    function _deploySystem(uint256 n)
        internal
        returns (
            MockERC20 token,
            AdminRecipientRegistry registry,
            MockDistributionManagerForFuzz distManager,
            EqualDistributionStrategy strategy
        )
    {
        address admin = address(this);
        token = new MockERC20();

        AdminRecipientRegistry regImpl = new AdminRecipientRegistry();
        bytes memory regInit = abi.encodeWithSelector(AdminRecipientRegistry.initialize.selector, admin);
        registry = AdminRecipientRegistry(address(new ERC1967Proxy(address(regImpl), regInit)));

        address[] memory batch = new address[](n);
        for (uint256 i; i < n; i++) {
            // Deterministic unique EOAs for this deployment (avoids duplicate queue reverts).
            batch[i] = address(uint160(uint256(0x100000 + i + 1)));
        }

        registry.queueRecipientsAddition(batch);
        registry.processQueue();

        distManager = new MockDistributionManagerForFuzz(IRecipientRegistry(address(registry)));

        EqualDistributionStrategy stratImpl = new EqualDistributionStrategy();
        bytes memory stratInit = abi.encodeWithSelector(
            EqualDistributionStrategy.initialize.selector, address(token), address(distManager), admin
        );
        strategy = EqualDistributionStrategy(address(new ERC1967Proxy(address(stratImpl), stratInit)));

        assertEq(registry.getRecipientCount(), n);
        assertEq(address(strategy.recipientRegistry()), address(registry));
        assertEq(strategy.distributionManager(), address(distManager));
        assertEq(address(strategy.yieldToken()), address(token));
    }
}
