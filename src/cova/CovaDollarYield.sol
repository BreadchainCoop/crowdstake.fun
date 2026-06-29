// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {AbstractToken} from "../abstract/AbstractToken.sol";

/// @title CovaDollarYield
/// @author COVA Artist Cooperative
/// @notice The COVA cooperative dollar: a USD-pegged, yield-bearing
///         {AbstractToken}, same pattern as the protocol's `SexyDaiYield`
///         (sDAI) but USD/ERC-4626 instead of Gnosis xDAI.
/// @dev The cooperative deposits a USD stablecoin; 1 cUSD is minted per 1 USD
///      and the principal sits in an ERC-4626 USD savings vault. Interest the
///      vault accrues above the minted principal is the yield the
///      {AbstractDistributionManager} claims each cycle and routes to the
///      {CovaArtFundStrategy}. Stays on the crowdstake `AbstractToken` /
///      yield-claimer machinery (two-step claimer, auto-delegation, etc.).
contract CovaDollarYield is AbstractToken {
    using SafeERC20 for IERC20;

    error IsCollateral();

    /// @notice The USD stablecoin deposited as collateral (vault asset).
    IERC20 public immutable USD;
    /// @notice The ERC-4626 USD savings vault holding the principal.
    IERC4626 public immutable VAULT;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _usd, address _vault) {
        if (_usd == address(0) || _vault == address(0)) revert ZeroAddress();
        if (IERC4626(_vault).asset() != _usd) revert IsCollateral();
        USD = IERC20(_usd);
        VAULT = IERC4626(_vault);
        _disableInitializers();
    }

    function initialize(string memory name_, string memory symbol_, address owner_) external initializer {
        __ERC20_init(name_, symbol_);
        _initializeOwner(owner_);
    }

    /// @inheritdoc AbstractToken
    function _deposit(uint256 amount_) internal override {
        USD.safeTransferFrom(msg.sender, address(this), amount_);
        USD.safeIncreaseAllowance(address(VAULT), amount_);
        VAULT.deposit(amount_, address(this));
    }

    /// @inheritdoc AbstractToken
    function _remit(address receiver_, uint256 amount_) internal override {
        VAULT.withdraw(amount_, receiver_, address(this));
    }

    /// @inheritdoc AbstractToken
    function _yieldAccrued() internal view override returns (uint256) {
        uint256 assets = VAULT.convertToAssets(VAULT.balanceOf(address(this)));
        uint256 supply = totalSupply();
        return assets > supply ? assets - supply : 0;
    }

    /// @notice Rescues non-collateral tokens accidentally sent here.
    function rescueToken(address token_, uint256 amount_) external onlyOwner {
        if (token_ == address(VAULT)) revert IsCollateral();
        IERC20(token_).safeTransfer(owner(), amount_);
    }
}
