// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

contract TestWrapper is Test {
    bool private _forked;

    constructor() {
        // Only fork if ETH_RPC_URL is provided.
        // Tests that need mainnet state (e.g. BreadKitTest) should call _requireFork() in setUp.
        // Tests that only use mocks can run without any fork.
        try vm.envString("ETH_RPC_URL") returns (string memory rpcUrl) {
            uint256 blockNumber = 0;
            try vm.envUint("ETH_BLOCK_NUMBER") returns (uint256 envBlockNumber) {
                blockNumber = envBlockNumber;
            } catch {
                // Use latest block
            }
            if (blockNumber == 0) {
                vm.createSelectFork(rpcUrl);
            } else {
                vm.createSelectFork(rpcUrl, blockNumber);
            }
            _forked = true;
        } catch {
            // No ETH_RPC_URL — tests will run without a fork
            _forked = false;
        }
    }

    /// @dev Call in setUp() if the test requires mainnet state
    function _requireFork() internal {
        if (!_forked) {
            string memory rpcUrl = vm.envString("ETH_RPC_URL");
            vm.createSelectFork(rpcUrl);
        }
    }

    function _reset(string memory url_, uint256 blockNumber) internal {
        vm.createSelectFork(url_, blockNumber);
    }
}
