// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626Yield} from "../../interfaces/IERC4626Yield.sol";
import {AbstractStakePool} from "./AbstractStakePool.sol";

/// @title PoolStableYield
/// @notice Tokenless "pool mode" counterpart of {StableYield}: an ERC-20 stablecoin (e.g. USDC)
///         parked in an ERC-4626 savings vault, recorded as ledger entries with no token issued.
/// @dev Structurally mirrors StableYield: no native path (you can't turn native currency into a
///      stablecoin here), decimals mirror the underlying, and `vault.asset() == ASSET` is enforced
///      in the constructor. Principal withdrawals and yield claims BOTH pay the underlying
///      stablecoin, so _remit and _claimUnderlying are the same redeem-to-receiver operation. In
///      pool mode the deployer wires the DistributionManager's baseToken = the stablecoin.
contract PoolStableYield is AbstractStakePool {
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

    function initialize(
        string memory name_,
        string memory,
        /*symbol_ ignored: uses underlying's*/
        address owner_
    )
        external
        initializer
    {
        __AbstractStakePool_init(name_, owner_);
    }

    /// @dev The pool reports the UNDERLYING stablecoin's symbol — it is not its own token.
    function symbol() external view override returns (string memory) {
        return IERC20Metadata(address(ASSET)).symbol();
    }

    /// @dev Mirror the stablecoin's decimals (e.g. 6 for USDC) so the ledger stays in its units.
    function decimals() external view override returns (uint8) {
        return _underlyingDecimals;
    }

    /// @dev Pull the stablecoin from the depositor and route it into the vault (mirrors StableYield._deposit).
    /// @dev Fee-on-transfer underlyings are UNSUPPORTED (same as the token path): the ledger credits
    ///      `amount_`, but a transfer-fee asset would deposit less than `amount_` into the vault, so
    ///      the ledger supply would over-count the backing. Only use plain-transfer underlyings.
    function _deposit(uint256 amount_) internal override {
        ASSET.safeTransferFrom(msg.sender, address(this), amount_);
        ASSET.safeIncreaseAllowance(address(YIELD_VAULT), amount_);
        YIELD_VAULT.deposit(amount_, address(this));
    }

    /// @dev No native path (mirrors StableYield._depositNative).
    function _depositNative(uint256) internal pure override {
        revert NativeNotSupported();
    }

    /// @dev Principal withdrawal: redeem the stablecoin from the vault to the redeemer (StableYield._remit).
    function _remit(address receiver_, uint256 amount_) internal override {
        YIELD_VAULT.withdraw(amount_, receiver_, address(this));
    }

    /// @dev Yield claim: same redeem-to-receiver as _remit — the underlying is the stablecoin, which
    ///      is exactly what the DistributionManager's baseToken is wired to in pool mode.
    function _claimUnderlying(address receiver_, uint256 amount_) internal override {
        YIELD_VAULT.withdraw(amount_, receiver_, address(this));
    }

    /// @dev Vault-backed surplus over ledger supply (mirrors StableYield._yieldAccrued).
    function _yieldAccrued() internal view override returns (uint256) {
        uint256 shares = IERC20(address(YIELD_VAULT)).balanceOf(address(this));
        uint256 assets = YIELD_VAULT.convertToAssets(shares);
        uint256 supply = totalSupply();
        return assets > supply ? assets - supply : 0;
    }

    /// @notice The underlying asset paid out on yield claims and principal withdrawals.
    /// @dev The deployer reads this to wire the DistributionManager's baseToken in pool mode.
    function underlyingAsset() external view returns (address) {
        return address(ASSET);
    }

    /// @notice Rescue tokens accidentally sent here — never the vault collateral.
    function rescueToken(address tok_, uint256 amount_) external onlyOwner {
        if (tok_ == address(YIELD_VAULT)) revert IsCollateral();
        IERC20(tok_).safeTransfer(owner(), amount_);
    }
}
