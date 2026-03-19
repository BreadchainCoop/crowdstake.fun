// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";

/// @notice Extension of IVotes exposing the checkpoint array for exact historical queries
/// @dev These functions are public in OpenZeppelin's ERC20Votes but not included in IVotes.
///      See: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.5.0/contracts/token/ERC20/extensions/ERC20Votes.sol#L73-L82
interface IVotesCheckpoints is IVotes {
    function numCheckpoints(address account) external view returns (uint32);
    function checkpoints(address account, uint32 pos) external view returns (Checkpoints.Checkpoint208 memory);
}
