// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AbstractStakePool} from "../src/implementation/pool/AbstractStakePool.sol";
import {PoolStableYield} from "../src/implementation/pool/PoolStableYield.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {MockUSDC, MockStableVault} from "./StableYield.t.sol";

/// @dev Pool harness mirroring YieldSplit.t.sol's HarnessToken: `assets` moves exactly like a real
///      pool's vault position — deposits/remits move it, and yield CLAIMS (which redeem the
///      underlying) also move it down, exactly like a vault redemption. So raw yield =
///      assets - totalSupply with no rounding, ideal for exact yield-split PARITY assertions
///      against the token harness. Redeemed underlying is credited to a per-receiver ledger so
///      tests can assert claims actually paid out.
contract HarnessPool is AbstractStakePool {
    uint256 public assets;
    mapping(address => uint256) public underlyingPaid;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory name_,
        string memory,
        /*symbol*/
        address owner_
    )
        external
        initializer
    {
        __AbstractStakePool_init(name_, owner_);
    }

    function symbol() external pure override returns (string memory) {
        return "MOCK";
    }

    function decimals() external pure override returns (uint8) {
        return 18;
    }

    function underlyingAsset() external pure returns (address) {
        return address(0xDEAD);
    }

    function _deposit(uint256 amount_) internal override {
        assets += amount_;
    }

    /// @dev Model a native deposit (wrap → vault) as just crediting the vault-backed assets.
    function _depositNative(uint256 amount_) internal override {
        assets += amount_;
    }

    function _remit(address receiver_, uint256 amount_) internal override {
        assets -= amount_;
        underlyingPaid[receiver_] += amount_;
    }

    /// @dev Yield claim redeems the underlying: vault-backed assets fall by the claimed amount,
    ///      just as a real 4626 redemption reduces the pool's backing.
    function _claimUnderlying(address receiver_, uint256 amount_) internal override {
        assets -= amount_;
        underlyingPaid[receiver_] += amount_;
    }

    function _yieldAccrued() internal view override returns (uint256) {
        uint256 supply = totalSupply();
        return assets > supply ? assets - supply : 0;
    }

    function addYield(uint256 amount_) external {
        assets += amount_;
    }

    function slashAssets(uint256 amount_) external {
        assets -= amount_;
    }
}

/// @notice Pool unit tests: deposit/withdraw both variants, yield accrual, yield-split accumulator
///         PARITY with the token, claimYield paying the underlying + gating + rotation timelock,
///         checkpoints written correctly, and no ERC-20 transfer surface.
contract StakePoolTest is Test {
    HarnessPool pool;
    address claimer = address(0xCAFE);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    uint16 constant BPS = 10_000;

    function setUp() public {
        HarnessPool impl = new HarnessPool();
        bytes memory data = abi.encodeWithSelector(HarnessPool.initialize.selector, "Community Pool", "", address(this));
        pool = HarnessPool(address(new ERC1967Proxy(address(impl), data)));
        pool.setYieldClaimer(claimer);
    }

    function _depositFor(address who, uint256 amount) internal {
        vm.prank(who);
        pool.mint(who, amount);
    }

    /* --------------------------- ledger + probe --------------------------- */

    function test_IsPoolProbeAndName() public view {
        assertTrue(pool.isPool(), "isPool feature probe true");
        assertEq(pool.name(), "Community Pool", "instance name");
    }

    function test_NoTransferSurface() public {
        // The pool is NOT an ERC-20: it has no transfer/approve/allowance/transferFrom. A call to
        // any of those selectors hits the fallback and reverts (no matching function).
        (bool ok,) = address(pool).call(abi.encodeWithSignature("transfer(address,uint256)", bob, 1));
        assertFalse(ok, "no transfer()");
        (ok,) = address(pool).call(abi.encodeWithSignature("approve(address,uint256)", bob, 1));
        assertFalse(ok, "no approve()");
        (ok,) = address(pool).call(abi.encodeWithSignature("allowance(address,address)", alice, bob));
        assertFalse(ok, "no allowance()");
        (ok,) = address(pool).call(abi.encodeWithSignature("transferFrom(address,address,uint256)", alice, bob, 1));
        assertFalse(ok, "no transferFrom()");
    }

    /* --------------------------- deposit / withdraw ----------------------- */

    function test_DepositErc20Path_RecordsLedgerAndEmitsDeposited() public {
        vm.expectEmit(true, false, false, true);
        emit AbstractStakePool.Deposited(alice, 100 ether);
        _depositFor(alice, 100 ether);

        assertEq(pool.balanceOf(alice), 100 ether, "ledger balance");
        assertEq(pool.totalSupply(), 100 ether, "supply");
        assertEq(pool.getVotes(alice), 100 ether, "auto self-delegated voting weight");
    }

    function test_FrontendVotingReads_GetVotesAndDelegates() public {
        // Pool must expose getVotes/delegates on instance.token (auto self-delegate on
        // deposit) so admin re-delegation and strategy inputs stay coherent. Portfolio
        // "Your voting power" reads Voting Power Strategy getCurrentVotingPower instead.
        assertEq(pool.getVotes(alice), 0, "no votes before deposit");
        assertEq(pool.delegates(alice), alice, "auto self-delegated: delegate is the account itself");

        _depositFor(alice, 100 ether);
        assertEq(pool.getVotes(alice), 100 ether, "getVotes = current deposit balance");
        assertEq(pool.delegates(alice), alice, "delegate stays the account itself");

        vm.prank(alice);
        pool.burn(40 ether, alice);
        assertEq(pool.getVotes(alice), 60 ether, "getVotes tracks the balance down");
    }

    function test_DepositNativePath_RecordsLedger() public {
        vm.deal(alice, 5 ether);
        vm.prank(alice);
        pool.mint{value: 3 ether}(alice);
        assertEq(pool.balanceOf(alice), 3 ether, "native deposit ledgered");
        assertEq(pool.totalSupply(), 3 ether, "supply from native path");
    }

    function test_Withdraw_BurnsLedgerPaysUnderlyingEmitsWithdrawn() public {
        _depositFor(alice, 100 ether);
        vm.expectEmit(true, false, false, true);
        emit AbstractStakePool.Withdrawn(bob, 40 ether);
        vm.prank(alice);
        pool.burn(40 ether, bob);

        assertEq(pool.balanceOf(alice), 60 ether, "ledger reduced");
        assertEq(pool.totalSupply(), 60 ether, "supply reduced");
        assertEq(pool.underlyingPaid(bob), 40 ether, "underlying remitted to receiver");
    }

    function test_Withdraw_RevertsOverBalance() public {
        _depositFor(alice, 10 ether);
        vm.prank(alice);
        vm.expectRevert(AbstractStakePool.InsufficientBalance.selector);
        pool.burn(11 ether, alice);
    }

    function test_MintZeroReverts() public {
        vm.prank(alice);
        vm.expectRevert(AbstractStakePool.MintZero.selector);
        pool.mint(alice, 0);
    }

    /* ----------------------- yield accrual via vault ---------------------- */

    function test_YieldAccrual() public {
        _depositFor(alice, 100 ether);
        assertEq(pool.totalYieldAccrued(), 0, "no yield yet");
        pool.addYield(7 ether);
        assertEq(pool.totalYieldAccrued(), 7 ether, "vault appreciation surfaces as yield");
        assertEq(pool.yieldAccrued(), 7 ether, "all donated by default");
    }

    /* --------------------- claimYield pays underlying --------------------- */

    function test_ClaimYield_PaysUnderlyingAndGated() public {
        _depositFor(alice, 100 ether);
        pool.addYield(10 ether);

        // Gated to the yield claimer.
        vm.prank(alice);
        vm.expectRevert(AbstractStakePool.OnlyClaimer.selector);
        pool.claimYield(1 ether, alice);

        vm.prank(claimer);
        pool.claimYield(10 ether, claimer);
        assertEq(pool.underlyingPaid(claimer), 10 ether, "claimer received the UNDERLYING (not pool balance)");
        assertEq(pool.balanceOf(claimer), 0, "no pool ledger balance minted for the claim");
        assertEq(pool.yieldAccrued(), 0, "donated pool drained");
    }

    /* ---------------------- yield-claimer rotation ------------------------ */

    function test_ClaimerRotation_Timelock() public {
        address next = address(0xBEEF);

        vm.expectRevert(AbstractStakePool.NoPendingClaimer.selector);
        pool.finalizeNewYieldClaimer();

        pool.prepareNewYieldClaimer(next);
        assertEq(pool.pendingYieldClaimer(), next, "pending set");

        vm.expectRevert(AbstractStakePool.TimelockNotElapsed.selector);
        pool.finalizeNewYieldClaimer();

        vm.warp(block.timestamp + 14 days);
        pool.finalizeNewYieldClaimer();
        assertEq(pool.yieldClaimer(), next, "claimer rotated after 14-day timelock");
    }

    function test_SetClaimer_OnlyOnce() public {
        vm.expectRevert(AbstractStakePool.AlreadySetClaimer.selector);
        pool.setYieldClaimer(address(0x1234));
    }

    /* -------------------------- checkpoints ------------------------------- */

    function test_CheckpointsWrittenOnDepositAndWithdraw() public {
        vm.roll(100);
        _depositFor(alice, 100 ether);
        assertEq(pool.numCheckpoints(alice), 1, "one checkpoint after first deposit");
        Checkpoints.Checkpoint208 memory c0 = pool.checkpoints(alice, 0);
        assertEq(uint256(c0._key), 100, "checkpoint keyed by block.number");
        assertEq(uint256(c0._value), 100 ether, "checkpoint value = balance");

        vm.roll(150);
        _depositFor(alice, 50 ether);
        assertEq(pool.numCheckpoints(alice), 2, "second checkpoint at new block");
        Checkpoints.Checkpoint208 memory c1 = pool.checkpoints(alice, 1);
        assertEq(uint256(c1._key), 150, "second key");
        assertEq(uint256(c1._value), 150 ether, "cumulative balance");

        vm.roll(200);
        vm.prank(alice);
        pool.burn(30 ether, alice);
        Checkpoints.Checkpoint208 memory c2 = pool.checkpoints(alice, 2);
        assertEq(uint256(c2._value), 120 ether, "withdraw checkpoints the reduced balance");
    }

    function test_SameBlockDepositOverwritesCheckpoint() public {
        vm.roll(300);
        _depositFor(alice, 10 ether);
        _depositFor(alice, 5 ether); // same block
        assertEq(pool.numCheckpoints(alice), 1, "same-block writes coalesce (OZ Checkpoints semantics)");
        Checkpoints.Checkpoint208 memory c = pool.checkpoints(alice, 0);
        assertEq(uint256(c._value), 15 ether, "coalesced to final balance");
    }

    /* ----------------- yield-split accumulator PARITY --------------------- */
    // These mirror YieldSplit.t.sol's token tests 1:1 and assert IDENTICAL numbers, proving the
    // 1e27 accumulator was ported faithfully (settlement points: deposit/withdraw/setYieldSplit/
    // claimKeptYield — the pool has no transfers).

    function test_Parity_DefaultDonatesEverything() public {
        _depositFor(alice, 100 ether);
        pool.addYield(10 ether);
        assertEq(pool.yieldAccrued(), 10 ether, "all yield donated by default");
        assertEq(pool.totalYieldAccrued(), 10 ether, "raw surplus");
        assertEq(pool.keptYieldOf(alice), 0, "nothing kept by default");
    }

    function test_Parity_SplitAppliesOnlyGoingForward() public {
        _depositFor(alice, 100 ether);
        pool.addYield(10 ether);

        vm.prank(alice);
        pool.setYieldSplit(5000);
        assertEq(pool.keptYieldOf(alice), 0, "past yield stays donated");
        assertEq(pool.yieldAccrued(), 10 ether, "donated pool untouched");

        pool.addYield(10 ether);
        assertEq(pool.keptYieldOf(alice), 5 ether, "half of new yield kept");
        assertEq(pool.yieldAccrued(), 15 ether, "old 10 + new donated 5");
    }

    function test_Parity_SingleHolderKeepsHalf_ClaimPaysUnderlying() public {
        vm.prank(alice);
        pool.setYieldSplit(5000);
        _depositFor(alice, 100 ether);
        pool.addYield(10 ether);

        assertEq(pool.keptYieldOf(alice), 5 ether, "kept half");
        assertEq(pool.yieldAccrued(), 5 ether, "donated half");
        assertEq(pool.totalYieldAccrued(), 10 ether, "raw is the sum");

        // The claimer cannot touch the kept share.
        vm.prank(claimer);
        vm.expectRevert(AbstractStakePool.YieldInsufficient.selector);
        pool.claimYield(6 ether, claimer);

        vm.prank(claimer);
        pool.claimYield(5 ether, claimer);
        assertEq(pool.underlyingPaid(claimer), 5 ether, "donated pool paid in underlying");

        vm.prank(alice);
        pool.claimKeptYield(alice);
        assertEq(pool.underlyingPaid(alice), 5 ether, "kept yield paid in underlying (not minted)");
        assertEq(pool.balanceOf(alice), 100 ether, "claim did NOT change the ledger balance");
        assertEq(pool.keptYieldOf(alice), 0, "kept claimed");
        assertEq(pool.totalYieldAccrued(), 0, "everything consumed");
    }

    function test_Parity_TwoHoldersDifferentSplits() public {
        vm.prank(alice);
        pool.setYieldSplit(BPS); // keeps everything
        _depositFor(alice, 100 ether); // 25% of supply
        _depositFor(bob, 300 ether); // donates everything

        pool.addYield(40 ether);
        assertEq(pool.keptYieldOf(alice), 10 ether, "alice keeps her quarter");
        assertEq(pool.keptYieldOf(bob), 0, "bob donates");
        assertEq(pool.yieldAccrued(), 30 ether, "bob's share is donated");
    }

    function test_Parity_ChangeSplitSettlesAtOldRate() public {
        vm.prank(alice);
        pool.setYieldSplit(BPS);
        _depositFor(alice, 100 ether);
        pool.addYield(10 ether);

        vm.prank(alice);
        pool.setYieldSplit(0); // stop keeping
        assertEq(pool.keptYieldOf(alice), 10 ether, "pre-change yield kept at old split");

        pool.addYield(10 ether);
        assertEq(pool.keptYieldOf(alice), 10 ether, "new yield donated");
        assertEq(pool.yieldAccrued(), 10 ether, "new yield in the pool");
    }

    function test_Parity_WithdrawSettlesAndKeptSurvivesExit() public {
        vm.prank(alice);
        pool.setYieldSplit(5000);
        _depositFor(alice, 100 ether);
        pool.addYield(10 ether);

        vm.prank(alice);
        pool.burn(100 ether, alice);
        assertEq(pool.balanceOf(alice), 0, "fully exited");
        assertEq(pool.keptYieldOf(alice), 5 ether, "kept yield survives exit");

        vm.prank(alice);
        pool.claimKeptYield(alice);
        assertEq(pool.underlyingPaid(alice), 100 ether + 5 ether, "principal (withdraw) + kept yield paid out");
        assertEq(pool.yieldAccrued(), 5 ether, "donated half still claimable");
    }

    /// Conservation fuzz mirroring YieldSplit.t.sol: attribution never exceeds the vault surplus.
    function testFuzz_Parity_KeptPlusDonatedNeverExceedRaw(uint16 bpsA, uint16 bpsB, uint96 y1, uint96 y2) public {
        bpsA = uint16(bound(bpsA, 0, BPS));
        bpsB = uint16(bound(bpsB, 0, BPS));
        y1 = uint96(bound(y1, 0, 1_000_000 ether));
        y2 = uint96(bound(y2, 0, 1_000_000 ether));

        vm.prank(alice);
        pool.setYieldSplit(bpsA);
        vm.prank(bob);
        pool.setYieldSplit(bpsB);
        _depositFor(alice, 100 ether);
        _depositFor(bob, 200 ether);

        pool.addYield(y1);
        pool.addYield(y2);

        uint256 raw = pool.totalYieldAccrued();
        uint256 attributed = pool.keptYieldOf(alice) + pool.keptYieldOf(bob) + pool.yieldAccrued();
        assertLe(attributed, raw, "attribution never exceeds the vault surplus");
        assertApproxEqAbs(attributed, raw, 10, "nothing material leaks");
    }
}

/// @notice End-to-end pool test on the real PoolStableYield impl + a 4626-style vault: verifies
///         principal in/out, yield accrual via appreciation, and claims paying the UNDERLYING
///         stablecoin (redeemed from the vault), all with NO token issued.
contract PoolStableYieldTest is Test {
    MockUSDC usdc;
    MockStableVault vault;
    PoolStableYield pool;
    address claimer = address(0xCAFE);
    address user = address(0xBEEF);
    address recipient = address(0x9999);

    uint256 constant ONE = 1e6; // 1 USDC

    function setUp() public {
        usdc = new MockUSDC();
        vault = new MockStableVault(address(usdc));
        PoolStableYield impl = new PoolStableYield(address(usdc), address(vault));
        bytes memory data = abi.encodeWithSelector(PoolStableYield.initialize.selector, "USDC Pool", "", address(this));
        pool = PoolStableYield(payable(address(new ERC1967Proxy(address(impl), data))));
        pool.setYieldClaimer(claimer);
        usdc.mintTo(user, 1_000 * ONE);
    }

    function test_SymbolIsUnderlyingsAndDecimalsMirror() public view {
        assertEq(pool.symbol(), "USDC", "pool reports the UNDERLYING symbol, not a synthetic one");
        assertEq(pool.decimals(), 6, "decimals mirror the underlying");
        assertEq(pool.underlyingAsset(), address(usdc), "underlyingAsset() = the stablecoin");
    }

    function test_ConstructorRevertsOnAssetMismatch() public {
        MockUSDC other = new MockUSDC();
        MockStableVault wrong = new MockStableVault(address(other));
        vm.expectRevert(PoolStableYield.VaultAssetMismatch.selector);
        new PoolStableYield(address(usdc), address(wrong));
    }

    function test_NativeDepositReverts() public {
        vm.deal(user, 1 ether);
        vm.prank(user);
        vm.expectRevert(PoolStableYield.NativeNotSupported.selector);
        pool.mint{value: 1 ether}(user);
    }

    function test_DepositWithdraw_1to1_NoToken() public {
        vm.startPrank(user);
        usdc.approve(address(pool), 100 * ONE);
        pool.mint(user, 100 * ONE);
        vm.stopPrank();

        assertEq(pool.balanceOf(user), 100 * ONE, "ledger 1:1 in 6dp");
        assertEq(pool.totalSupply(), 100 * ONE, "supply");
        assertEq(usdc.balanceOf(address(vault)), 100 * ONE, "vault holds the USDC");

        uint256 before = usdc.balanceOf(user);
        vm.prank(user);
        pool.burn(40 * ONE, user);
        assertEq(pool.balanceOf(user), 60 * ONE, "ledger reduced");
        assertEq(usdc.balanceOf(user) - before, 40 * ONE, "USDC redeemed 1:1 to the withdrawer");
    }

    function test_YieldAccrual_ClaimPaysUnderlyingStablecoin() public {
        vm.startPrank(user);
        usdc.approve(address(pool), 100 * ONE);
        pool.mint(user, 100 * ONE);
        vm.stopPrank();

        vault.setRateBps(10_500); // +5% appreciation
        usdc.mintTo(address(vault), 5 * ONE); // back the appreciation with real USDC
        assertEq(pool.totalYieldAccrued(), 5 * ONE, "5 USDC of yield");
        assertEq(pool.yieldAccrued(), 5 * ONE, "all donated by default");

        vm.prank(claimer);
        pool.claimYield(5 * ONE, recipient);
        assertEq(usdc.balanceOf(recipient), 5 * ONE, "yield claim paid the UNDERLYING USDC");
        assertEq(pool.balanceOf(recipient), 0, "no pool ledger balance minted");
        assertEq(pool.yieldAccrued(), 0, "drained");
    }
}
