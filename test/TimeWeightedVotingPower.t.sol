// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {TimeWeightedVotingPower, IVotesCheckpoints} from "../src/implementation/strategies/TimeWeightedVotingPower.sol";
import {ICycleModule} from "../src/interfaces/ICycleModule.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {CycleModule} from "../src/implementation/CycleModule.sol";

/// @dev ERC20Votes token that supports getPastVotes with proper checkpointing
contract MockVotesToken is ERC20, ERC20Votes, ERC20Permit {
    constructor() ERC20("Mock Token", "MOCK") ERC20Permit("Mock Token") {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        _burn(account, amount);
    }

    function _update(address from, address to, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._update(from, to, amount);
    }

    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return ERC20Permit.nonces(owner);
    }
}

contract TimeWeightedVotingPowerTest is Test {
    TimeWeightedVotingPower public strategy;
    MockVotesToken public token;
    CycleModule public cycleModule;

    address public user1 = address(0xBEEF);
    address public user2 = address(0xCAFE);
    address public owner;

    uint256 constant LOOKBACK = 100; // 100 blocks
    uint256 constant MIN_HOLDING = 50; // 50 blocks

    event LookbackPeriodUpdated(uint256 newPeriod);
    event MinHoldingPeriodUpdated(uint256 newPeriod);

    function setUp() public {
        owner = address(this);

        token = new MockVotesToken();
        cycleModule = new CycleModule();

        // Start at block 1 so getPastVotes works (can't query block 0)
        vm.roll(1);
        cycleModule.initialize(1000);

        strategy = new TimeWeightedVotingPower(
            IVotesCheckpoints(address(token)), ICycleModule(address(cycleModule)), LOOKBACK, MIN_HOLDING
        );
    }

    // ============ Constructor Tests ============

    function testConstructorSetsState() public view {
        assertEq(address(strategy.votingToken()), address(token));
        assertEq(address(strategy.cycleModule()), address(cycleModule));
        assertEq(strategy.lookbackPeriod(), LOOKBACK);
        assertEq(strategy.minHoldingPeriod(), MIN_HOLDING);
    }

    function testConstructorRevertsInvalidToken() public {
        vm.expectRevert(TimeWeightedVotingPower.InvalidToken.selector);
        new TimeWeightedVotingPower(
            IVotesCheckpoints(address(0)), ICycleModule(address(cycleModule)), LOOKBACK, MIN_HOLDING
        );
    }

    function testConstructorRevertsInvalidCycleModule() public {
        vm.expectRevert(TimeWeightedVotingPower.InvalidCycleModule.selector);
        new TimeWeightedVotingPower(IVotesCheckpoints(address(token)), ICycleModule(address(0)), LOOKBACK, MIN_HOLDING);
    }

    function testConstructorRevertsInvalidPeriod() public {
        vm.expectRevert(TimeWeightedVotingPower.InvalidPeriod.selector);
        new TimeWeightedVotingPower(
            IVotesCheckpoints(address(token)), ICycleModule(address(cycleModule)), 0, MIN_HOLDING
        );
    }

    // ============ Lossless Calculation Tests ============

    function testExactCheckpointIntegration() public {
        // Use a strategy with no min holding penalty for pure math verification
        TimeWeightedVotingPower noMinStrategy = new TimeWeightedVotingPower(
            IVotesCheckpoints(address(token)), ICycleModule(address(cycleModule)), LOOKBACK, 0
        );

        vm.roll(10);
        token.mint(user1, 1_000_000);
        vm.prank(user1);
        token.delegate(user1);

        // Advance 3 blocks
        vm.roll(13);
        // Mint another 1_000_000 (total 2_000_000)
        token.mint(user1, 1_000_000);

        // Advance 1 more block so we can query
        vm.roll(14);

        // Period [10, 14): 4 blocks
        // Block 10-12: 1M (3 blocks) = 3M
        // Block 13:    2M (1 block)  = 2M
        // Total area = 5M, avg = 5M/4 = 1_250_000
        uint256 power = noMinStrategy.getVotingPowerForPeriod(user1, 10, 14);
        assertEq(power, 1_250_000);
    }

    function testConstantBalanceFullPeriod() public {
        vm.roll(10);
        token.mint(user1, 100 ether);
        vm.prank(user1);
        token.delegate(user1);

        // Advance well past lookback + min holding so full power applies
        vm.roll(10 + LOOKBACK + MIN_HOLDING + 10);

        uint256 power = strategy.getCurrentVotingPower(user1);
        assertEq(power, 100 ether);
    }

    function testFlashLoanProtection() public {
        // User has held 1 ether for a long time
        vm.roll(10);
        token.mint(user1, 1 ether);
        vm.prank(user1);
        token.delegate(user1);

        // Advance many blocks
        vm.roll(500);

        // "Flash loan" - user acquires 1000 ether right before checking
        token.mint(user1, 1000 ether);

        // Move 1 block so getPastVotes can see the mint
        vm.roll(501);

        uint256 power = strategy.getCurrentVotingPower(user1);

        // Exact calculation:
        // Period is [401, 501) = 100 blocks
        // Blocks 401-499: 1 ether (99 blocks) = 99 ether
        // Block 500:      1001 ether (1 block) = 1001 ether
        // Total area = 1100 ether, avg = 1100/100 = 11 ether
        assertEq(power, 11 ether);
        assertLt(power, 100 ether, "Flash loan should not give near-full power");
    }

    function testFlashLoanExactMath() public {
        // Verify the exact area-under-curve for a flash loan scenario
        vm.roll(10);
        token.mint(user1, 10 ether);
        vm.prank(user1);
        token.delegate(user1);

        vm.roll(100);
        // Flash: acquire 990 ether (total 1000)
        token.mint(user1, 990 ether);

        vm.roll(101);

        // Period [1, 101) = 100 blocks, min holding met
        // Blocks 1-9: 0 (9 blocks)
        // Blocks 10-99: 10 ether (90 blocks) = 900 ether
        // Block 100: 1000 ether (1 block) = 1000 ether
        // Total area = 1900 ether, avg = 1900/100 = 19 ether
        uint256 power = strategy.getCurrentVotingPower(user1);
        assertEq(power, 19 ether);
    }

    function testMinimumHoldingPeriodPenalty() public {
        vm.roll(10);
        token.mint(user1, 100 ether);
        vm.prank(user1);
        token.delegate(user1);

        // Advance only a few blocks (less than minHoldingPeriod)
        vm.roll(20);

        uint256 earlyPower = strategy.getCurrentVotingPower(user1);

        // Advance past min holding period
        vm.roll(10 + MIN_HOLDING + LOOKBACK);

        uint256 laterPower = strategy.getCurrentVotingPower(user1);

        assertLt(earlyPower, laterPower, "Early power should be less than later power");
    }

    function testZeroBalanceReturnsZero() public {
        vm.roll(200);
        uint256 power = strategy.getCurrentVotingPower(user1);
        assertEq(power, 0);
    }

    function testPowerAtCycleStart() public {
        vm.roll(1);
        uint256 power = strategy.getCurrentVotingPower(user1);
        assertEq(power, 0, "Power should be 0 at cycle start");
    }

    function testGetVotingPowerForPeriod() public {
        vm.roll(10);
        token.mint(user1, 100 ether);
        vm.prank(user1);
        token.delegate(user1);

        vm.roll(200);

        uint256 power = strategy.getVotingPowerForPeriod(user1, 50, 150);
        // User had 100 ether for the entire period [50, 150)
        assertEq(power, 100 ether);
    }

    function testGetVotingPowerForPeriodRevertsStartAfterEnd() public {
        vm.roll(100);
        vm.expectRevert(TimeWeightedVotingPower.StartAfterEnd.selector);
        strategy.getVotingPowerForPeriod(user1, 50, 50);
    }

    function testGetVotingPowerForPeriodRevertsFuturePeriod() public {
        vm.roll(100);
        vm.expectRevert(TimeWeightedVotingPower.FuturePeriod.selector);
        strategy.getVotingPowerForPeriod(user1, 50, 200);
    }

    // ============ Checkpoint-walking edge cases ============

    function testMidPeriodBalanceChange() public {
        vm.roll(10);
        token.mint(user1, 50 ether);
        vm.prank(user1);
        token.delegate(user1);

        vm.roll(60);
        token.mint(user1, 50 ether); // now 100 ether

        vm.roll(110);
        // Period [10, 110) = 100 blocks, min holding met
        // Blocks 10-59: 50 ether (50 blocks) = 2500 ether
        // Blocks 60-109: 100 ether (50 blocks) = 5000 ether
        // Total = 7500, avg = 75 ether
        uint256 power = strategy.getVotingPowerForPeriod(user1, 10, 110);
        assertEq(power, 75 ether);
    }

    function testMultipleCheckpointsInPeriod() public {
        vm.roll(10);
        token.mint(user1, 100 ether);
        vm.prank(user1);
        token.delegate(user1);

        vm.roll(30);
        token.mint(user1, 100 ether); // 200

        vm.roll(50);
        token.mint(user1, 100 ether); // 300

        vm.roll(70);
        // Period [10, 70) = 60 blocks
        // Blocks 10-29: 100 (20 blocks) = 2000
        // Blocks 30-49: 200 (20 blocks) = 4000
        // Blocks 50-69: 300 (20 blocks) = 6000
        // Total = 12000, avg = 200 ether
        uint256 power = strategy.getVotingPowerForPeriod(user1, 10, 70);
        assertEq(power, 200 ether);
    }

    function testCheckpointBeforePeriodStart() public {
        // Token acquired well before the period — should count as constant
        vm.roll(5);
        token.mint(user1, 100 ether);
        vm.prank(user1);
        token.delegate(user1);

        vm.roll(200);
        // Period [100, 200) — user had 100 ether the whole time
        uint256 power = strategy.getVotingPowerForPeriod(user1, 100, 200);
        assertEq(power, 100 ether);
    }

    function testCheckpointAfterPeriodStart() public {
        // No tokens at period start, acquired mid-period
        vm.roll(50);
        token.mint(user1, 100 ether);
        vm.prank(user1);
        token.delegate(user1);

        vm.roll(110);
        // Period [10, 110) = 100 blocks
        // Blocks 10-49: 0 (40 blocks)
        // Blocks 50-109: 100 ether (60 blocks) = 6000 ether
        // avg = 6000/100 = 60 ether
        uint256 power = strategy.getVotingPowerForPeriod(user1, 10, 110);
        assertEq(power, 60 ether);
    }

    function testBalanceDecreaseInPeriod() public {
        vm.roll(10);
        token.mint(user1, 100 ether);
        vm.prank(user1);
        token.delegate(user1);

        vm.roll(60);
        // Transfer half away (burn for simplicity)
        vm.prank(user1);
        token.transfer(address(0xDEAD), 50 ether);

        vm.roll(110);
        // Period [10, 110) = 100 blocks
        // Blocks 10-59: 100 ether (50 blocks) = 5000 ether
        // Blocks 60-109: 50 ether (50 blocks)  = 2500 ether
        // avg = 7500/100 = 75 ether
        uint256 power = strategy.getVotingPowerForPeriod(user1, 10, 110);
        assertEq(power, 75 ether);
    }

    // ============ Cycle Boundary Tests ============

    function testCycleBoundaryHandling() public {
        vm.roll(10);
        token.mint(user1, 100 ether);
        vm.prank(user1);
        token.delegate(user1);

        // Complete cycle 1 and start cycle 2
        vm.roll(1001);
        cycleModule.startNewCycle();

        // 9 blocks into cycle 2
        vm.roll(1010);

        uint256 power = strategy.getCurrentVotingPower(user1);
        // Period is [1001, 1010) = 9 blocks, < minHoldingPeriod
        // avg = 100 ether, penalty = 100 * 9 / 50
        uint256 expectedPenalized = 100 ether * 9 / MIN_HOLDING;
        assertEq(power, expectedPenalized);
    }

    // ============ Admin Tests ============

    function testSetLookbackPeriod() public {
        vm.expectEmit(false, false, false, true);
        emit LookbackPeriodUpdated(200);
        strategy.setLookbackPeriod(200);
        assertEq(strategy.lookbackPeriod(), 200);
    }

    function testSetLookbackPeriodRevertsZero() public {
        vm.expectRevert(TimeWeightedVotingPower.InvalidPeriod.selector);
        strategy.setLookbackPeriod(0);
    }

    function testSetMinHoldingPeriod() public {
        vm.expectEmit(false, false, false, true);
        emit MinHoldingPeriodUpdated(200);
        strategy.setMinHoldingPeriod(200);
        assertEq(strategy.minHoldingPeriod(), 200);
    }

    function testSetMinHoldingPeriodToZero() public {
        strategy.setMinHoldingPeriod(0);
        assertEq(strategy.minHoldingPeriod(), 0);
    }

    function testOnlyOwnerCanSetLookbackPeriod() public {
        vm.prank(user1);
        vm.expectRevert();
        strategy.setLookbackPeriod(200);
    }

    function testOnlyOwnerCanSetMinHoldingPeriod() public {
        vm.prank(user1);
        vm.expectRevert();
        strategy.setMinHoldingPeriod(200);
    }

    // ============ No Min Holding Period Tests ============

    function testNoMinHoldingPenaltyWhenZero() public {
        TimeWeightedVotingPower noMinStrategy = new TimeWeightedVotingPower(
            IVotesCheckpoints(address(token)), ICycleModule(address(cycleModule)), LOOKBACK, 0
        );

        vm.roll(1);
        token.mint(user1, 100 ether);
        vm.prank(user1);
        token.delegate(user1);

        vm.roll(LOOKBACK + 10);
        uint256 power = noMinStrategy.getCurrentVotingPower(user1);
        assertEq(power, 100 ether);
    }

    // ============ Multiple Users ============

    function testMultipleUsersIndependent() public {
        vm.roll(10);
        token.mint(user1, 100 ether);
        vm.prank(user1);
        token.delegate(user1);

        vm.roll(50);
        token.mint(user2, 200 ether);
        vm.prank(user2);
        token.delegate(user2);

        vm.roll(200);

        uint256 power1 = strategy.getCurrentVotingPower(user1);
        uint256 power2 = strategy.getCurrentVotingPower(user2);

        // Both held for entire lookback [100, 200)
        assertEq(power1, 100 ether);
        assertEq(power2, 200 ether);
    }

    // ============ Gas ============

    function testGasWithFewCheckpoints() public {
        vm.roll(10);
        token.mint(user1, 100 ether);
        vm.prank(user1);
        token.delegate(user1);

        vm.roll(200);

        uint256 gasBefore = gasleft();
        strategy.getCurrentVotingPower(user1);
        uint256 gasUsed = gasBefore - gasleft();

        // With exact checkpoint walking and only 1 checkpoint, gas should be very low
        assertLt(gasUsed, 30_000, "Gas should be very low with few checkpoints");
    }
}
