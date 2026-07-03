// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice The ERC-4626 subset the yield token needs from its savings vault
///         (sDAI on Gnosis; a WETH-denominated ERC-4626 vault on ETH chains).
///         The vault's `asset()` MUST equal the wrapped-native token above.
interface IERC4626Yield {
    function deposit(uint256 assets, address receiver) external returns (uint256);
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function asset() external view returns (address);
}
