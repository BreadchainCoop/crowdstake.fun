// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IWrappedNative} from "../../interfaces/IWrappedNative.sol";
import {IERC4626Yield} from "../../interfaces/IERC4626Yield.sol";
import {AbstractToken} from "../../abstract/AbstractToken.sol";

/// @title WrappedNativeYield
/// @notice Chain-agnostic yield token. Mints 1:1 on deposit of the chain's
///         native currency, routes the wrapped native into an ERC-4626 savings
///         vault, and accrues the vault's appreciation as claimable yield.
///
///         The Gnosis original (SexyDaiYield) is the special case
///         (WRAPPED_NATIVE = WXDAI, YIELD_VAULT = sDAI). On an ETH chain it is
///         (WRAPPED_NATIVE = WETH, YIELD_VAULT = a WETH-denominated ERC-4626
///         vault — e.g. an Aave StataToken or Yearn v3 WETH vault). The only
///         invariant: `YIELD_VAULT.asset() == WRAPPED_NATIVE`, enforced in the
///         constructor.
contract WrappedNativeYield is AbstractToken {
    using SafeERC20 for IERC20;

    error IsCollateral();
    error VaultAssetMismatch();

    IWrappedNative public immutable WRAPPED_NATIVE;
    IERC4626Yield public immutable YIELD_VAULT;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _wrappedNative, address _yieldVault) {
        if (IERC4626Yield(_yieldVault).asset() != _wrappedNative) {
            revert VaultAssetMismatch();
        }
        WRAPPED_NATIVE = IWrappedNative(_wrappedNative);
        YIELD_VAULT = IERC4626Yield(_yieldVault);
        _disableInitializers();
    }

    function initialize(string memory name_, string memory symbol_, address owner_) external initializer {
        __ERC20_init(name_, symbol_);
        _initializeOwner(owner_);
    }

    /// @dev Deposit the wrapped-native ERC20 directly (e.g. a user who already
    ///      holds WETH/WXDAI) and route it into the vault.
    function _deposit(uint256 amount_) internal override {
        IERC20(address(WRAPPED_NATIVE)).safeTransferFrom(msg.sender, address(this), amount_);
        IERC20(address(WRAPPED_NATIVE)).safeIncreaseAllowance(address(YIELD_VAULT), amount_);
        YIELD_VAULT.deposit(amount_, address(this));
    }

    /// @dev Wrap the native currency sent with the deposit and route it in.
    function _depositNative(uint256 amount_) internal override {
        WRAPPED_NATIVE.deposit{value: amount_}();
        IERC20(address(WRAPPED_NATIVE)).safeIncreaseAllowance(address(YIELD_VAULT), amount_);
        YIELD_VAULT.deposit(amount_, address(this));
    }

    /// @dev Redeem `amount_` of wrapped-native from the vault, unwrap to native,
    ///      and forward it to the redeemer. This contract is both the 4626
    ///      `owner` (whose shares burn) and the receiver of the unwrapped asset.
    function _remit(address receiver_, uint256 amount_) internal override {
        YIELD_VAULT.withdraw(amount_, address(this), address(this));
        WRAPPED_NATIVE.withdraw(amount_);
        _nativeTransfer(receiver_, amount_);
    }

    /// @notice Accept native forwarded by WRAPPED_NATIVE.withdraw() during redemptions.
    receive() external payable {}

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
