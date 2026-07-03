// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice The canonical wrapped-native token (WETH9 shape): WXDAI on Gnosis,
///         WETH on Ethereum/Arbitrum/Optimism. Wraps native 1:1.
interface IWrappedNative {
    function deposit() external payable;
    function withdraw(uint256) external;
}
