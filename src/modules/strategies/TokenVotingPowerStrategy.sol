// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../interfaces/IVotingPowerStrategy.sol";
import "@openzeppelin/contracts/governance/utils/IVotes.sol";

/// @title TokenVotingPowerStrategy
/// @notice Voting power based on token balance/delegation via ERC20Votes
/// @dev Uses the token's getVotes() for current voting power
/// @author BreadKit Protocol
contract TokenVotingPowerStrategy is IVotingPowerStrategy {
    /// @notice The voting token
    address public immutable votingToken;

    constructor(address _votingToken) {
        votingToken = _votingToken;
    }

    /// @inheritdoc IVotingPowerStrategy
    function getCurrentVotingPower(address account) external view override returns (uint256) {
        return IVotes(votingToken).getVotes(account);
    }

    /// @inheritdoc IVotingPowerStrategy
    function getAccumulatedVotingPower(address account) external view override returns (uint256) {
        // For simple token-based strategy, accumulated = current
        return IVotes(votingToken).getVotes(account);
    }
}
