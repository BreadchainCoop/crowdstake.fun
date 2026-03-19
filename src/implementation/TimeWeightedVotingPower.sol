// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IVotingPowerStrategy} from "../interfaces/IVotingPowerStrategy.sol";
import {IVotesCheckpoints} from "../interfaces/IVotesCheckpoints.sol";
import {ICycleModule} from "../interfaces/ICycleModule.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {Ownable} from "@solady/contracts/auth/Ownable.sol";

/// @title TimeWeightedVotingPower
/// @author BreadKit
/// @notice Lossless time-weighted voting power calculation using the breadchain pattern
/// @dev Walks the token's ERC20Votes checkpoint array to compute the exact
///      area-under-the-curve of delegated votes over the current cycle, then
///      divides by the period length to produce a time-weighted average.
///      The lookback window is derived from the cycle module's cycle length.
///      Every balance change is accounted for — no sampling or approximation.
contract TimeWeightedVotingPower is IVotingPowerStrategy, Ownable {
    // ============ Errors ============

    /// @notice Thrown when attempting to initialize with zero address token
    error InvalidToken();

    /// @notice Thrown when attempting to initialize with zero address cycle module
    error InvalidCycleModule();

    /// @notice Thrown when start block is not before end block
    error StartAfterEnd();

    /// @notice Thrown when end block is in the future
    error FuturePeriod();

    // ============ Immutable Storage ============

    /// @notice The ERC20Votes token used for voting power calculation
    IVotesCheckpoints public immutable votingToken;

    /// @notice The cycle module for period tracking and lookback derivation
    ICycleModule public immutable cycleModule;

    constructor(IVotesCheckpoints _votingToken, ICycleModule _cycleModule) {
        if (address(_votingToken) == address(0)) revert InvalidToken();
        if (address(_cycleModule) == address(0)) revert InvalidCycleModule();

        votingToken = _votingToken;
        cycleModule = _cycleModule;

        _initializeOwner(msg.sender);
    }

    /// @inheritdoc IVotingPowerStrategy
    function getCurrentVotingPower(address account) external view override returns (uint256) {
        uint256 cycleStart = cycleModule.lastCycleStartBlock();

        uint256 periodEnd = block.number;
        uint256 periodStart = cycleStart;

        // If period is empty (we're at cycle start block), return 0
        if (periodStart >= periodEnd) {
            return 0;
        }

        return _calculateTimeWeightedPower(account, periodStart, periodEnd);
    }

    /// @notice Calculate time-weighted voting power for a specific period
    /// @param account The account to calculate voting power for
    /// @param startBlock The start block of the period
    /// @param endBlock The end block of the period (exclusive)
    /// @return The time-weighted average voting power
    function getVotingPowerForPeriod(address account, uint256 startBlock, uint256 endBlock)
        external
        view
        returns (uint256)
    {
        if (startBlock >= endBlock) revert StartAfterEnd();
        if (endBlock > block.number) revert FuturePeriod();
        return _calculateTimeWeightedPower(account, startBlock, endBlock);
    }

    /// @dev Walks the token's checkpoint array in reverse to compute the exact
    ///      integral of (delegated votes * blocks held) over [start, end), then
    ///      divides by the period length to produce the time-weighted average.
    ///      This is the breadchain pattern — every balance change is accounted for.
    function _calculateTimeWeightedPower(address account, uint256 start, uint256 end) internal view returns (uint256) {
        uint32 numCkpts = votingToken.numCheckpoints(account);
        if (numCkpts == 0) return 0;

        uint256 periodLength = end - start;
        uint256 totalArea;
        uint256 upperBound = end;

        for (uint32 i = numCkpts; i > 0; i--) {
            Checkpoints.Checkpoint208 memory ckpt = votingToken.checkpoints(account, i - 1);
            uint256 key = uint256(ckpt._key);
            uint256 value = uint256(ckpt._value);

            // Checkpoint is at or after the period end — skip it
            if (key >= end) continue;

            if (key <= start) {
                // Checkpoint predates the period — its value covers [start, upperBound)
                totalArea += value * (upperBound - start);
                break;
            }

            // Checkpoint is within (start, end) — its value covers [key, upperBound)
            totalArea += value * (upperBound - key);
            upperBound = key;
        }

        return totalArea / periodLength;
    }
}
