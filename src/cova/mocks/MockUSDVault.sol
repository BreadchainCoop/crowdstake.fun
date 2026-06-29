// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockUSD} from "./MockUSD.sol";

/// @title MockUSDVault
/// @notice Minimal ERC-4626-style USD savings vault — the Sepolia analogue of
///         sDAI (there is no canonical Gnosis sDAI on Sepolia). The
///         {CovaDollarYield} {AbstractToken} deposits the cooperative's USD
///         here; yield is simulated by sending extra USD to the vault, which
///         raises `convertToAssets`.
contract MockUSDVault {
    IERC20 public immutable assetToken;
    mapping(address => uint256) public balanceOf; // shares
    uint256 public totalShares;

    constructor(address asset_) {
        assetToken = IERC20(asset_);
    }

    function asset() external view returns (address) {
        return address(assetToken);
    }

    function totalAssets() public view returns (uint256) {
        return assetToken.balanceOf(address(this));
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        uint256 ts = totalShares;
        uint256 ta = totalAssets();
        return (ts == 0 || ta == 0) ? assets : (assets * ts) / ta;
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        uint256 ts = totalShares;
        if (ts == 0) return shares;
        return (shares * totalAssets()) / ts;
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        shares = convertToShares(assets);
        assetToken.transferFrom(msg.sender, address(this), assets);
        balanceOf[receiver] += shares;
        totalShares += shares;
    }

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares) {
        uint256 ta = totalAssets();
        shares = totalShares == 0 ? assets : (assets * totalShares + ta - 1) / ta; // round up
        balanceOf[owner] -= shares;
        totalShares -= shares;
        assetToken.transfer(receiver, assets);
    }

    /// @notice Testnet helper: simulate accrued vault yield.
    function simulateYield(uint256 amount) external {
        MockUSD(address(assetToken)).mint(address(this), amount);
    }
}
