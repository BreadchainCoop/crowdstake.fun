// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IVotingPowerStrategy} from "../../interfaces/IVotingPowerStrategy.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

/// @title TokenBasedVotingPower
/// @author BreadKit
/// @notice Token balance-based voting power calculation strategy
/// @dev Implements IVotingPowerStrategy using ERC20Votes tokens.
///      Voting power is determined by the delegated vote balance of the token holder.
///      Users must delegate to themselves or another address to have voting power.
contract TokenBasedVotingPower is IVotingPowerStrategy {
    // ============ Errors ============

    /// @notice Thrown when attempting to initialize with zero address token
    error InvalidToken();

    // ============ Immutable Storage ============

    /// @notice The ERC20Votes token used for voting power calculation
    /// @dev Must implement the IVotes interface from OpenZeppelin
    IVotes public immutable VOTING_TOKEN;

    /// @notice Constructs the token-based voting power strategy
    /// @dev Reverts if token address is zero
    /// @param _votingToken The ERC20Votes token to use for voting power calculation
    constructor(IVotes _votingToken) {
        if (address(_votingToken) == address(0)) revert InvalidToken();
        VOTING_TOKEN = _votingToken;
    }

    /// @inheritdoc IVotingPowerStrategy
    function getCurrentVotingPower(address account) external view override returns (uint256) {
        // Use delegated votes (or balance if not delegated) for voting power
        return VOTING_TOKEN.getVotes(account);
    }
}
