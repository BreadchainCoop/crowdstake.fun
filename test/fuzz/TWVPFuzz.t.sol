// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";

/// @title MockVotesCheckpoints
/// @notice Minimal mock that stores checkpoints for TWVP fuzz testing
contract MockVotesCheckpoints {
    mapping(address => Checkpoints.Checkpoint208[]) private _checkpoints;

    function addCheckpoint(address account, uint48 key, uint208 value) external {
        _checkpoints[account].push(Checkpoints.Checkpoint208({_key: key, _value: value}));
    }

    function numCheckpoints(address account) external view returns (uint32) {
        return uint32(_checkpoints[account].length);
    }

    function checkpoints(address account, uint32 pos) external view returns (Checkpoints.Checkpoint208 memory) {
        return _checkpoints[account][pos];
    }
}

/// @title TWVPFuzz
/// @notice Fuzz tests for time-weighted voting power calculation logic.
///         Reimplements the core TWVP algorithm from TimeWeightedVotingPower._calculateTimeWeightedPower
///         to test invariants without requiring the full contract deployment.
contract TWVPFuzz is Test {
    MockVotesCheckpoints mockToken;
    address constant ACCOUNT = address(0xBEEF);

    function setUp() public {
        mockToken = new MockVotesCheckpoints();
    }

    /// @notice Fuzz that zero balance always returns zero power
    function testFuzz_ZeroBalanceReturnsZeroPower(uint256 startBlock, uint256 duration) public {
        startBlock = bound(startBlock, 1, 1e6);
        duration = bound(duration, 1, 1e6);
        uint256 endBlock = startBlock + duration;

        // No checkpoints at all
        uint256 power = _calculateTWVP(ACCOUNT, startBlock, endBlock);
        assertEq(power, 0);
    }

    /// @notice Fuzz that constant balance over full period returns that balance
    function testFuzz_ConstantBalanceReturnsSameValue(uint208 balance, uint256 startBlock, uint256 duration) public {
        balance = uint208(bound(balance, 0, 1e24));
        startBlock = bound(startBlock, 10, 1e6);
        duration = bound(duration, 1, 1e6);
        uint256 endBlock = startBlock + duration;

        // Single checkpoint before period start
        mockToken.addCheckpoint(ACCOUNT, uint48(startBlock - 1), balance);

        // Roll to endBlock so the view function works (block.number >= endBlock conceptually)
        vm.roll(endBlock);

        uint256 power = _calculateTWVP(ACCOUNT, startBlock, endBlock);
        assertEq(power, uint256(balance));
    }

    /// @notice Fuzz that power is always <= max balance across the period
    function testFuzz_PowerNeverExceedsMaxBalance(
        uint208 balance1,
        uint208 balance2,
        uint256 startBlock,
        uint256 midOffset,
        uint256 duration
    ) public {
        balance1 = uint208(bound(balance1, 0, 1e24));
        balance2 = uint208(bound(balance2, 0, 1e24));
        startBlock = bound(startBlock, 10, 1e6);
        duration = bound(duration, 2, 1e6);
        midOffset = bound(midOffset, 1, duration - 1);

        uint256 midBlock = startBlock + midOffset;
        uint256 endBlock = startBlock + duration;

        // Checkpoint before period and one in the middle
        mockToken.addCheckpoint(ACCOUNT, uint48(startBlock - 1), balance1);
        mockToken.addCheckpoint(ACCOUNT, uint48(midBlock), balance2);

        vm.roll(endBlock);

        uint256 power = _calculateTWVP(ACCOUNT, startBlock, endBlock);
        uint256 maxBalance = balance1 > balance2 ? uint256(balance1) : uint256(balance2);
        assertLe(power, maxBalance);
    }

    /// @notice Fuzz that constant balance gives consistent time-weighted average
    function testFuzz_ConstantBalancePowerConsistentAcrossDurations(
        uint208 balance,
        uint256 startBlock,
        uint256 shortDuration,
        uint256 extraDuration
    ) public {
        balance = uint208(bound(balance, 1, 1e24));
        startBlock = bound(startBlock, 10, 1e6);
        shortDuration = bound(shortDuration, 1, 5e5);
        extraDuration = bound(extraDuration, 1, 5e5);

        uint256 endShort = startBlock + shortDuration;
        uint256 endLong = startBlock + shortDuration + extraDuration;

        // Checkpoint at start of period
        mockToken.addCheckpoint(ACCOUNT, uint48(startBlock), balance);

        vm.roll(endLong);

        uint256 powerShort = _calculateTWVP(ACCOUNT, startBlock, endShort);
        uint256 powerLong = _calculateTWVP(ACCOUNT, startBlock, endLong);

        // With constant balance, TWVP should be the same regardless of duration
        // (time-weighted average of a constant = that constant)
        assertEq(powerShort, powerLong);
        // Both should equal the balance
        assertEq(powerShort, uint256(balance));
    }

    /// @notice Fuzz that late deposit gives less power than holding from start
    function testFuzz_LateDepositLessPower(
        uint208 balance,
        uint256 startBlock,
        uint256 depositOffset,
        uint256 duration
    ) public {
        balance = uint208(bound(balance, 1, 1e24));
        startBlock = bound(startBlock, 10, 1e6);
        duration = bound(duration, 10, 1e6);
        depositOffset = bound(depositOffset, 1, duration - 1);

        uint256 depositBlock = startBlock + depositOffset;
        uint256 endBlock = startBlock + duration;

        // Scenario A: holds from before period start
        MockVotesCheckpoints tokenA = new MockVotesCheckpoints();
        tokenA.addCheckpoint(ACCOUNT, uint48(startBlock - 1), balance);

        // Scenario B: deposits partway through
        MockVotesCheckpoints tokenB = new MockVotesCheckpoints();
        tokenB.addCheckpoint(ACCOUNT, uint48(depositBlock), balance);

        vm.roll(endBlock);

        uint256 powerA = _calculateTWVPWith(tokenA, ACCOUNT, startBlock, endBlock);
        uint256 powerB = _calculateTWVPWith(tokenB, ACCOUNT, startBlock, endBlock);

        // Full-period holder should have >= power than late depositor
        assertGe(powerA, powerB);
    }

    // ---- Internal TWVP calculation (mirrors TimeWeightedVotingPower._calculateTimeWeightedPower) ----

    function _calculateTWVP(address account, uint256 start, uint256 end) internal view returns (uint256) {
        return _calculateTWVPWith(mockToken, account, start, end);
    }

    function _calculateTWVPWith(MockVotesCheckpoints token, address account, uint256 start, uint256 end)
        internal
        view
        returns (uint256)
    {
        uint32 numCkpts = token.numCheckpoints(account);
        if (numCkpts == 0) return 0;

        uint256 periodLength = end - start;
        uint256 totalArea;
        uint256 upperBound = end;

        for (uint32 i = numCkpts; i > 0; i--) {
            Checkpoints.Checkpoint208 memory ckpt = token.checkpoints(account, i - 1);
            uint256 key = uint256(ckpt._key);
            uint256 value = uint256(ckpt._value);

            if (key >= end) continue;

            if (key <= start) {
                totalArea += value * (upperBound - start);
                break;
            }

            totalArea += value * (upperBound - key);
            upperBound = key;
        }

        return totalArea / periodLength;
    }
}
