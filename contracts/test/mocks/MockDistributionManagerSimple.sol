// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IDistributionManager} from "../../src/interfaces/IDistributionManager.sol";
import {IRecipientRegistry} from "../../src/interfaces/IRecipientRegistry.sol";
import {ICycleModule} from "../../src/interfaces/ICycleModule.sol";
import {IVotingModule} from "../../src/interfaces/IVotingModule.sol";

/// @title MockDistributionManagerSimple
/// @notice Mock implementation that returns true for distribution readiness every 200 blocks
/// @dev Simple mock for testing automation triggers
contract MockDistributionManagerSimple is IDistributionManager {
    uint256 public constant BLOCKS_PER_CYCLE = 200;
    uint256 public lastDistributionBlock;

    event MockDistributionExecuted(uint256 blockNumber);

    constructor() {
        lastDistributionBlock = block.number;
    }

    function recipientRegistry() external pure override returns (IRecipientRegistry) {
        return IRecipientRegistry(address(0));
    }

    function cycleManager() external pure override returns (ICycleModule) {
        return ICycleModule(address(0));
    }

    function votingModule() external pure override returns (IVotingModule) {
        return IVotingModule(address(0));
    }

    /// @notice Checks if distribution is ready (every 200 blocks)
    /// @return ready True if 200 blocks have passed since last distribution
    function isDistributionReady() external view override returns (bool ready) {
        return block.number >= lastDistributionBlock + BLOCKS_PER_CYCLE;
    }

    /// @notice Mock execution that simply updates the last distribution block
    function claimAndDistribute() external override {
        require(block.number >= lastDistributionBlock + BLOCKS_PER_CYCLE, "Not ready");

        lastDistributionBlock = block.number;

        emit MockDistributionExecuted(block.number);
    }

    /// @notice Get the number of blocks until next distribution
    /// @return blocks Number of blocks remaining
    function blocksUntilDistribution() external view returns (uint256 blocks) {
        if (block.number >= lastDistributionBlock + BLOCKS_PER_CYCLE) {
            return 0;
        }
        return (lastDistributionBlock + BLOCKS_PER_CYCLE) - block.number;
    }

    /// @notice Get the last distribution block number
    /// @return blockNumber The block number of the last distribution
    function getLastDistributionBlock() external view returns (uint256 blockNumber) {
        return lastDistributionBlock;
    }
}
