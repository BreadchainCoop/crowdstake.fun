// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

contract TestWrapper is Test {
    constructor() {
        string memory rpcUrl = vm.envString("ETH_RPC_URL");

        // Try to use ETH_BLOCK_NUMBER from env if provided, otherwise use latest
        uint256 blockNumber;
        try vm.envUint("ETH_BLOCK_NUMBER") returns (uint256 envBlockNumber) {
            blockNumber = envBlockNumber;
        } catch {
            // If ETH_BLOCK_NUMBER is not set, fork at the latest block
            blockNumber = 0; // 0 means latest block in Foundry
        }

        if (blockNumber == 0) {
            // Fork at latest block
            vm.createSelectFork(rpcUrl);
        } else {
            // Fork at specific block
            vm.createSelectFork(rpcUrl, blockNumber);
        }
    }

    function _reset(string memory url_, uint256 blockNumber) internal {
        vm.createSelectFork(url_, blockNumber);
    }
}
