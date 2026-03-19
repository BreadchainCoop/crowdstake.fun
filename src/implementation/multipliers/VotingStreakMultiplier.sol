// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MultiplierVotingModule} from "../MultiplierVotingModule.sol";

/// @title VotingStreakMultiplier
/// @author BreadKit
/// @notice Gives bonus voting power for consecutive cycle participation.
///         Voting 10 cycles in a row yields a 2x multiplier.
/// @dev Reads streak data directly from MultiplierVotingModule's public storage.
///      No state mutation needed — the voting module tracks streaks automatically.
///      Multiplier = 1e18 + (streak * 0.1e18), capped at streak of 10 → 2x.
contract VotingStreakMultiplier {
    uint256 public constant BASE = 1e18;
    uint256 public constant BONUS_PER_STREAK = 0.1e18;

    MultiplierVotingModule public immutable votingModule;

    constructor(address _votingModule) {
        votingModule = MultiplierVotingModule(_votingModule);
    }

    /// @notice Returns the multiplier for a voter in 1e18 precision
    function getMultiplier(address voter) external view returns (uint256) {
        uint256 streak = votingModule.votingStreak(voter);
        return BASE + (streak * BONUS_PER_STREAK);
    }
}
