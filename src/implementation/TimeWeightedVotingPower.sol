// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IVotingPowerStrategy} from "../interfaces/IVotingPowerStrategy.sol";
import {IVotesCheckpoints} from "../interfaces/IVotesCheckpoints.sol";
import {ICycleModule} from "../interfaces/ICycleModule.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {Ownable} from "@solady/contracts/auth/Ownable.sol";

/// @title TimeWeightedVotingPower
/// @author BreadKit
/// @notice Time-weighted voting power with optional per-interval quadratic scaling
/// @dev By default computes a lossless time-weighted average over the cycle window.
///      When a non-zero scalingPeriod is set, applies a quadratic penalty to each
///      checkpoint interval where duration < scalingPeriod:
///
///      - intervalLength >= scalingPeriod: contribution = value * intervalLength  (no penalty)
///      - intervalLength < scalingPeriod: contribution = value * intervalLength^2 / scalingPeriod
///
///      This makes flash-loan attacks progressively more expensive even when the
///      total period is long — an attacker holding tokens for only 1 block with
///      scalingPeriod=10 gets ~100x less voting power than the nominal amount.
///
///      Every balance change in the ERC20Votes checkpoint array is fully accounted for.
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

    /// @notice Thrown when scaling period exceeds the maximum allowed value
    error ScalingPeriodTooLarge();

    /// @notice Maximum allowed scaling period (~30 days in blocks at 12s/block)
    uint256 public constant MAX_SCALING_PERIOD = 365 days / 12;

    // ============ Immutable Storage ============

    /// @notice The ERC20Votes token used for voting power calculation
    IVotesCheckpoints public immutable VOTING_TOKEN;

    /// @notice The cycle module for period tracking and lookback derivation
    ICycleModule public immutable CYCLE_MODULE;

    /// @notice Scaling period in blocks for the quadratic flash-loan penalty.
    /// @dev When 0 (default), no penalty is applied (classic time-weighted average).
    ///      When set to a non-zero value, intervals shorter than this period receive
    ///      a quadratic penalty: contribution = value * duration^2 / scalingPeriod.
    ///      Example: scalingPeriod=100, attacker holds 1000 ETH for 1 block →
    ///      10 ETH effective power (100x reduction).
    ///      WARNING: The owner can change scalingPeriod mid-cycle. A timelock or
    ///      governance delay is recommended for production deployments.
    uint256 public scalingPeriod;

    // ============ Events ============

    /// @notice Emitted when the scaling period is updated
    /// @param oldPeriod The previous scaling period value
    /// @param newPeriod The new scaling period value
    event ScalingPeriodUpdated(uint256 oldPeriod, uint256 newPeriod);

    // ============ Constructor ============

    /// @notice Constructs the time-weighted voting power strategy
    /// @dev Reverts if either token or cycle module address is zero
    /// @param _votingToken The ERC20Votes token with checkpoint support
    /// @param _cycleModule The cycle module for period tracking
    /// @param _scalingPeriod Initial scaling period in blocks (0 = disabled)
    constructor(
        IVotesCheckpoints _votingToken,
        ICycleModule _cycleModule,
        uint256 _scalingPeriod
    ) {
        if (address(_votingToken) == address(0)) revert InvalidToken();
        if (address(_cycleModule) == address(0)) revert InvalidCycleModule();
        if (_scalingPeriod > MAX_SCALING_PERIOD) revert ScalingPeriodTooLarge();

        VOTING_TOKEN = _votingToken;
        CYCLE_MODULE = _cycleModule;
        scalingPeriod = _scalingPeriod;

        _initializeOwner(msg.sender);
    }

    /// @inheritdoc IVotingPowerStrategy
    function getCurrentVotingPower(address account) external view override returns (uint256) {
        uint256 cycleStart = CYCLE_MODULE.lastCycleStartBlock();

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

    // ============ Admin Functions ============

    /// @notice Sets the scaling period for flash-loan quadratic penalty
    /// @dev Only callable by owner. Setting to 0 disables the penalty (classic TWAV).
    /// @param _scalingPeriod New scaling period in blocks
    function setScalingPeriod(uint256 _scalingPeriod) external onlyOwner {
        if (_scalingPeriod > MAX_SCALING_PERIOD) revert ScalingPeriodTooLarge();
        uint256 old = scalingPeriod;
        scalingPeriod = _scalingPeriod;
        emit ScalingPeriodUpdated(old, _scalingPeriod);
    }

    // ============ Internal Functions ============

    /// @dev Applies the quadratic scaling penalty to a checkpoint interval.
    ///      When scalingPeriod is 0, returns area unchanged (no penalty).
    ///      When intervalLength >= scalingPeriod, returns area unchanged (fully vested).
    ///      When intervalLength < scalingPeriod, returns area * intervalLength / scalingPeriod.
    ///      Since area = value * intervalLength, the effective formula is:
    ///        value * intervalLength^2 / scalingPeriod (quadratic in duration).
    /// @param area The raw area contribution (value * intervalLength)
    /// @param intervalLength The duration of this checkpoint interval in blocks
    /// @return The scaled area contribution
    function _applyScalingPenalty(uint256 area, uint256 intervalLength) internal view returns (uint256) {
        if (scalingPeriod == 0 || intervalLength >= scalingPeriod) {
            return area;
        }
        return (area * intervalLength) / scalingPeriod;
    }

    /// @dev Walks the token's checkpoint array in reverse to compute the exact
    ///      integral of (delegated votes * blocks held) over [start, end), then
    ///      divides by the period length to produce the time-weighted average.
    ///      This is the breadchain pattern — every balance change is accounted for.
    ///
    ///      When scalingPeriod is non-zero, each interval shorter than scalingPeriod
    ///      receives a quadratic penalty (see _applyScalingPenalty), making flash-loan
    ///      attacks progressively more expensive.
    function _calculateTimeWeightedPower(address account, uint256 start, uint256 end)
        internal
        view
        returns (uint256)
    {
        uint32 numCkpts = VOTING_TOKEN.numCheckpoints(account);
        if (numCkpts == 0) return 0;

        uint256 periodLength = end - start;
        uint256 totalArea;
        uint256 upperBound = end;

        for (uint32 i = numCkpts; i > 0; i--) {
            Checkpoints.Checkpoint208 memory ckpt = VOTING_TOKEN.checkpoints(account, i - 1);
            uint256 key = uint256(ckpt._key);
            uint256 value = uint256(ckpt._value);

            // Checkpoint is at or after the period end — skip it
            if (key >= end) continue;

            uint256 intervalLength;
            if (key <= start) {
                // Checkpoint predates the period — its value covers [start, upperBound)
                intervalLength = upperBound - start;
                uint256 area = value * intervalLength;
                totalArea += _applyScalingPenalty(area, intervalLength);
                break;
            }

            // Checkpoint is within (start, end) — its value covers [key, upperBound)
            intervalLength = upperBound - key;
            uint256 contribution = value * intervalLength;
            totalArea += _applyScalingPenalty(contribution, intervalLength);
            upperBound = key;
        }

        return totalArea / periodLength;
    }
}
