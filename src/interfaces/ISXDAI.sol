// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ISXDAI {
    function deposit(uint256 assets, address receiver) external returns (uint256);
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256);

    function convertToAssets(uint256 shares) external view returns (uint256);
}
