// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import {CrowdStakeFactory} from "../src/CrowdStakeFactory.sol";
import {CrowdStakeDeployer} from "../src/CrowdStakeDeployer.sol";
import {CycleModule} from "../src/implementation/CycleModule.sol";
import {AbstractCycleModule} from "../src/abstract/AbstractCycleModule.sol";
import {BasisPointsVotingModule} from "../src/base/BasisPointsVotingModule.sol";
import {BaseDistributionManager} from "../src/base/BaseDistributionManager.sol";
import {MultiStrategyDistributionManager} from "../src/base/MultiStrategyDistributionManager.sol";
import {AbstractDistributionManager} from "../src/abstract/AbstractDistributionManager.sol";
import {VotingDistributionStrategy} from "../src/implementation/strategies/VotingDistributionStrategy.sol";
import {EqualDistributionStrategy} from "../src/implementation/strategies/EqualDistributionStrategy.sol";
import {AdminRecipientRegistry} from "../src/implementation/registries/AdminRecipientRegistry.sol";
import {VotingRecipientRegistry} from "../src/implementation/registries/VotingRecipientRegistry.sol";
import {StableYield} from "../src/implementation/token/StableYield.sol";
import {PoolStableYield} from "../src/implementation/pool/PoolStableYield.sol";
import {AbstractToken} from "../src/abstract/AbstractToken.sol";
import {IStakePool} from "../src/interfaces/IStakePool.sol";

import {MockUSDC, MockStableVault} from "./StableYield.t.sol";

/// @notice Full-instance integration for BOTH modes deployed through CrowdStakeDeployer:
///         deposit → vault appreciation → vote (real BasisPointsVotingModule +
///         TimeWeightedVotingPower strategy) → claimAndDistribute → recipients paid per
///         allocations, Distributed events emitted, cycle advanced.
///         - Pool mode (issueToken=false): recipients receive the UNDERLYING (USDC).
///         - Token mode (issueToken=true): unchanged classic behavior.
contract PoolModeIntegrationTest is Test {
    CrowdStakeDeployer internal deployer;
    MockUSDC internal usdc;
    MockStableVault internal vault;

    address internal constant OWNER = address(0xABCD);
    address internal recipientA = address(0xA1);
    address internal recipientB = address(0xB2);

    uint256 internal aliceKey = 0xA11CE;
    uint256 internal bobKey = 0xB0B;
    address internal alice;
    address internal bob;

    uint256 internal constant ONE = 1e6; // 1 USDC
    uint256 internal constant CYCLE = 100;
    uint256 internal constant MAX_POINTS = 100;

    function setUp() public {
        alice = vm.addr(aliceKey);
        bob = vm.addr(bobKey);

        usdc = new MockUSDC();
        vault = new MockStableVault(address(usdc));

        CrowdStakeFactory factory = new CrowdStakeFactory(address(this));

        // Both TOKEN and POOL beacons use the STABLE (USDC + 4626) impls so one deployer can build
        // both modes over the same underlying for an apples-to-apples comparison.
        address[] memory beacons = new address[](10);
        beacons[0] = address(new UpgradeableBeacon(address(new CycleModule()), address(this)));
        beacons[1] = address(new UpgradeableBeacon(address(new AdminRecipientRegistry()), address(this)));
        beacons[2] = address(new UpgradeableBeacon(address(new VotingRecipientRegistry()), address(this)));
        beacons[3] =
            address(new UpgradeableBeacon(address(new StableYield(address(usdc), address(vault))), address(this)));
        beacons[4] =
            address(new UpgradeableBeacon(address(new PoolStableYield(address(usdc), address(vault))), address(this)));
        beacons[5] = address(new UpgradeableBeacon(address(new BaseDistributionManager()), address(this)));
        beacons[6] = address(new UpgradeableBeacon(address(new MultiStrategyDistributionManager()), address(this)));
        beacons[7] = address(new UpgradeableBeacon(address(new VotingDistributionStrategy()), address(this)));
        beacons[8] = address(new UpgradeableBeacon(address(new EqualDistributionStrategy()), address(this)));
        beacons[9] = address(new UpgradeableBeacon(address(new BasisPointsVotingModule()), address(this)));
        factory.allowlistBeacons(beacons);

        deployer = new CrowdStakeDeployer(
            address(factory),
            beacons[0],
            beacons[1],
            beacons[2],
            beacons[3],
            beacons[4],
            beacons[5],
            beacons[6],
            beacons[7],
            beacons[8],
            beacons[9]
        );

        usdc.mintTo(alice, 10_000 * ONE);
        usdc.mintTo(bob, 10_000 * ONE);
    }

    function _params(bytes32 salt, bool issueToken) internal pure returns (CrowdStakeDeployer.Params memory) {
        return CrowdStakeDeployer.Params({
            owner: OWNER,
            cycleLength: CYCLE,
            tokenName: "Integration",
            tokenSymbol: "INTG",
            maxVotingPoints: MAX_POINTS,
            salt: salt,
            registryKind: 0, // admin
            initialRecipients: new address[](0),
            proposalExpiry: 0,
            distributionKind: 0, // proportional
            tokenImageURI: "",
            bannerImageURI: "",
            crossChain: false,
            issueToken: issueToken
        });
    }

    /// @dev Adds two recipients through the admin registry (owned by OWNER).
    function _seedRecipients(address registry) internal {
        // Recipients must be queued in strictly-ascending address order.
        (address r0, address r1) =
            uint160(recipientA) < uint160(recipientB) ? (recipientA, recipientB) : (recipientB, recipientA);
        vm.startPrank(OWNER);
        AdminRecipientRegistry(registry).queueRecipientAddition(r0);
        AdminRecipientRegistry(registry).queueRecipientAddition(r1);
        vm.stopPrank();
        AdminRecipientRegistry(registry).processQueue();
    }

    /// @dev Signs + casts a proportional vote for `voter` via the real voting module.
    function _vote(address votingModule, address voter, uint256 key, uint256[] memory points, uint256 nonce) internal {
        bytes32 domainSeparator = BasisPointsVotingModule(votingModule).DOMAIN_SEPARATOR();
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Vote(address voter,bytes32 pointsHash,uint256 nonce)"),
                voter,
                keccak256(abi.encodePacked(points)),
                nonce
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        BasisPointsVotingModule(votingModule).castVoteWithSignature(voter, points, nonce, abi.encodePacked(r, s, v));
    }

    // ============================ POOL MODE ============================

    function test_PoolMode_FullCycle_RecipientsReceiveUnderlying() public {
        CrowdStakeDeployer.Instance memory i = deployer.deploy(_params("pool-int", false));

        // The yield surface is the pool (issueToken=false), and it exposes the pool probe.
        assertTrue(IStakePool(i.token).isPool(), "instance.token is a pool");
        // The distribution manager distributes the UNDERLYING, and reads yield from the pool.
        assertEq(
            address(AbstractDistributionManager(i.distributionManager).baseToken()), address(usdc), "baseToken=USDC"
        );
        assertEq(
            address(AbstractDistributionManager(i.distributionManager).yieldModule()), i.token, "yieldModule=the pool"
        );

        _seedRecipients(i.registry);

        // Deposits into the pool (ledger + auto self-delegated voting checkpoints).
        uint256 startBlock = block.number;
        vm.startPrank(alice);
        usdc.approve(i.token, 600 * ONE);
        IStakePool(i.token).mint(alice, 600 * ONE);
        vm.stopPrank();
        vm.startPrank(bob);
        usdc.approve(i.token, 400 * ONE);
        IStakePool(i.token).mint(bob, 400 * ONE);
        vm.stopPrank();

        // Advance so time-weighted voting power is non-zero within the cycle.
        vm.roll(startBlock + 10);

        // Votes: recipient order is the registry's ascending order. Alice all-in on r0, Bob on r1.
        uint256[] memory aPts = new uint256[](2);
        aPts[0] = 100;
        aPts[1] = 0;
        uint256[] memory bPts = new uint256[](2);
        bPts[0] = 0;
        bPts[1] = 100;
        _vote(i.votingModule, alice, aliceKey, aPts, 1);
        _vote(i.votingModule, bob, bobKey, bPts, 2);

        // Vault appreciates 10% → 100 USDC of yield on 1000 USDC of backing.
        vault.setRateBps(11_000);
        usdc.mintTo(address(vault), 100 * ONE);
        uint256 yield = IStakePool(i.token).yieldAccrued();
        assertEq(yield, 100 * ONE, "100 USDC donated yield");

        // Roll to cycle end and distribute.
        vm.roll(startBlock + CYCLE);
        assertTrue(BaseDistributionManager(i.distributionManager).isDistributionReady(), "ready");

        (address r0, address r1) =
            uint160(recipientA) < uint160(recipientB) ? (recipientA, recipientB) : (recipientB, recipientA);

        // Distributed events for both recipients (values checked by balance below).
        vm.recordLogs();
        BaseDistributionManager(i.distributionManager).claimAndDistribute();

        // Recipients received the UNDERLYING (USDC), proportional to time-weighted votes.
        // Alice (600) voted r0, Bob (400) voted r1 → r0 gets 60%, r1 gets 40% of 100 USDC.
        assertApproxEqAbs(usdc.balanceOf(r0), 60 * ONE, 2, "r0 got ~60 USDC");
        assertApproxEqAbs(usdc.balanceOf(r1), 40 * ONE, 2, "r1 got ~40 USDC");
        assertEq(usdc.balanceOf(r0) + usdc.balanceOf(r1), 100 * ONE, "full yield distributed in USDC");

        // No pool ledger balance was minted to recipients (they are not depositors).
        assertEq(IStakePool(i.token).balanceOf(r0), 0, "no ledger balance for recipient r0");
        assertEq(IStakePool(i.token).balanceOf(r1), 0, "no ledger balance for recipient r1");

        // Cycle advanced atomically.
        assertEq(AbstractCycleModule(i.cycleModule).getCurrentCycle(), 2, "cycle advanced");

        // A Distributed event was emitted for each recipient.
        _assertDistributedEmittedFor(r0, r1);
    }

    function _assertDistributedEmittedFor(address r0, address r1) internal {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 sig = keccak256("Distributed(address,uint256)");
        bool sawR0;
        bool sawR1;
        for (uint256 k = 0; k < logs.length; k++) {
            if (logs[k].topics[0] != sig) continue;
            // Distributed(address indexed recipient, uint256 amount): recipient is topics[1].
            address rcpt = address(uint160(uint256(logs[k].topics[1])));
            if (rcpt == r0) sawR0 = true;
            if (rcpt == r1) sawR1 = true;
        }
        assertTrue(sawR0 && sawR1, "Distributed emitted for both recipients");
    }

    function test_PoolMode_WithdrawRedeemsUnderlying() public {
        CrowdStakeDeployer.Instance memory i = deployer.deploy(_params("pool-wd", false));
        vm.startPrank(alice);
        usdc.approve(i.token, 100 * ONE);
        IStakePool(i.token).mint(alice, 100 * ONE);
        uint256 before = usdc.balanceOf(alice);
        IStakePool(i.token).burn(30 * ONE, alice);
        vm.stopPrank();
        assertEq(IStakePool(i.token).balanceOf(alice), 70 * ONE, "ledger reduced");
        assertEq(usdc.balanceOf(alice) - before, 30 * ONE, "principal redeemed in USDC");
    }

    // ============================ TOKEN MODE ============================
    // Same flow with issueToken=true asserts the classic token behavior is unchanged: a real
    // ERC-20 is minted, recipients receive the TOKEN, and it stays 1:1 redeemable for USDC.

    function test_TokenMode_FullCycle_Unchanged() public {
        CrowdStakeDeployer.Instance memory i = deployer.deploy(_params("token-int", true));

        // The yield surface is a token: baseToken == token == yieldModule (classic wiring).
        assertEq(address(AbstractDistributionManager(i.distributionManager).baseToken()), i.token, "baseToken=token");
        assertEq(
            address(AbstractDistributionManager(i.distributionManager).yieldModule()), i.token, "yieldModule=token"
        );
        // It is NOT a pool (no isPool()).
        (bool ok,) = i.token.call(abi.encodeWithSignature("isPool()"));
        assertFalse(ok, "token has no isPool() probe");

        _seedRecipients(i.registry);

        uint256 startBlock = block.number;
        vm.startPrank(alice);
        usdc.approve(i.token, 600 * ONE);
        AbstractToken(i.token).mint(alice, 600 * ONE);
        vm.stopPrank();
        vm.startPrank(bob);
        usdc.approve(i.token, 400 * ONE);
        AbstractToken(i.token).mint(bob, 400 * ONE);
        vm.stopPrank();

        vm.roll(startBlock + 10);

        uint256[] memory aPts = new uint256[](2);
        aPts[0] = 100;
        aPts[1] = 0;
        uint256[] memory bPts = new uint256[](2);
        bPts[0] = 0;
        bPts[1] = 100;
        _vote(i.votingModule, alice, aliceKey, aPts, 1);
        _vote(i.votingModule, bob, bobKey, bPts, 2);

        vault.setRateBps(11_000);
        usdc.mintTo(address(vault), 100 * ONE);
        assertEq(AbstractToken(i.token).yieldAccrued(), 100 * ONE, "100 USDC of donated yield");

        vm.roll(startBlock + CYCLE);
        BaseDistributionManager(i.distributionManager).claimAndDistribute();

        (address r0, address r1) =
            uint160(recipientA) < uint160(recipientB) ? (recipientA, recipientB) : (recipientB, recipientA);

        // In token mode recipients receive the TOKEN (not USDC directly).
        assertApproxEqAbs(AbstractToken(i.token).balanceOf(r0), 60 * ONE, 2, "r0 got ~60 tokens");
        assertApproxEqAbs(AbstractToken(i.token).balanceOf(r1), 40 * ONE, 2, "r1 got ~40 tokens");
        assertEq(usdc.balanceOf(r0), 0, "recipient holds tokens, not raw USDC yet");

        // The token is redeemable 1:1 for the underlying.
        uint256 bal = AbstractToken(i.token).balanceOf(r0);
        vm.prank(r0);
        AbstractToken(i.token).burn(bal, r0);
        assertEq(usdc.balanceOf(r0), bal, "token redeemed 1:1 for USDC");

        assertEq(AbstractCycleModule(i.cycleModule).getCurrentCycle(), 2, "cycle advanced");
    }
}
