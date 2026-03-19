// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";

/// @notice Extension of IVotes exposing the checkpoint array for exact historical queries
interface IVotesCheckpoints is IVotes {
    function numCheckpoints(address account) external view returns (uint32);
    function checkpoints(address account, uint32 pos) external view returns (Checkpoints.Checkpoint208 memory);
}
