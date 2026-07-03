// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626Yield} from "../../interfaces/IERC4626Yield.sol";
import {AbstractToken} from "../../abstract/AbstractToken.sol";

/// @title StableYield
/// @notice A yield token whose deposit asset is an ERC-20 stablecoin (e.g. USDC)
///         parked in an ERC-4626 savings vault. Unlike the native SexyDaiYield
///         there is NO native path — native currency can't become a stablecoin
///         without a swap, so `mint()`-payable reverts. The project token mirrors
///         the stablecoin's decimals so 1 token == 1 unit of the stablecoin and
///         the yield math stays in the underlying's units.
///
///         Used on chains where the best sDAI-equivalent yield lives in a
///         stablecoin vault (Morpho USDC vaults ~4-6.65% on Arbitrum/Optimism)
///         rather than a native-denominated one. `vault.asset() == ASSET` is
///         enforced in the constructor.
contract StableYield is AbstractToken {
    using SafeERC20 for IERC20;

    error IsCollateral();
    error VaultAssetMismatch();
    error NativeNotSupported();

    IERC20 public immutable ASSET;
    IERC4626Yield public immutable YIELD_VAULT;
    uint8 private immutable _underlyingDecimals;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _asset, address _yieldVault) {
        if (IERC4626Yield(_yieldVault).asset() != _asset) revert VaultAssetMismatch();
        ASSET = IERC20(_asset);
        YIELD_VAULT = IERC4626Yield(_yieldVault);
        _underlyingDecimals = IERC20Metadata(_asset).decimals();
        _disableInitializers();
    }

    function initialize(string memory name_, string memory symbol_, address owner_) external initializer {
        __ERC20_init(name_, symbol_);
        _initializeOwner(owner_);
    }

    /// @dev Mirror the stablecoin's decimals (e.g. 6 for USDC) so mint/redeem/
    ///      yield all stay in the underlying's units.
    function decimals() public view override returns (uint8) {
        return _underlyingDecimals;
    }

    /// @dev Pull the stablecoin from the depositor and route it into the vault.
    function _deposit(uint256 amount_) internal override {
        ASSET.safeTransferFrom(msg.sender, address(this), amount_);
        ASSET.safeIncreaseAllowance(address(YIELD_VAULT), amount_);
        YIELD_VAULT.deposit(amount_, address(this));
    }

    /// @dev No native path: you can't turn native currency into a stablecoin here.
    function _depositNative(uint256) internal pure override {
        revert NativeNotSupported();
    }

    /// @dev Redeem `amount_` of the stablecoin from the vault straight to the redeemer.
    function _remit(address receiver_, uint256 amount_) internal override {
        YIELD_VAULT.withdraw(amount_, receiver_, address(this));
    }

    function _yieldAccrued() internal view override returns (uint256) {
        uint256 shares = IERC20(address(YIELD_VAULT)).balanceOf(address(this));
        uint256 assets = YIELD_VAULT.convertToAssets(shares);
        uint256 supply = totalSupply();
        return assets > supply ? assets - supply : 0;
    }

    /// @notice Rescue tokens accidentally sent here — never the vault collateral.
    function rescueToken(address tok_, uint256 amount_) external onlyOwner {
        if (tok_ == address(YIELD_VAULT)) revert IsCollateral();
        IERC20(tok_).safeTransfer(owner(), amount_);
    }
}
