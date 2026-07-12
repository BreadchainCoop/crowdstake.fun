// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IWXDAI} from "../../interfaces/IWXDAI.sol";
import {ISXDAI} from "../../interfaces/ISXDAI.sol";
import {AbstractStakePool} from "./AbstractStakePool.sol";

/// @title PoolNativeYield
/// @notice Tokenless "pool mode" counterpart of {SexyDaiYield}: native xDAI → wxDAI → sDAI.
/// @dev Structurally mirrors SexyDaiYield's deposit/remit/yield logic (deposit native, wrap to
///      wxDAI, park in the sDAI ERC-4626 vault) but records ledger entries instead of minting a
///      token. Principal withdrawals ({burn}) unwrap all the way back to native xDAI, exactly as
///      SexyDaiYield does. Yield claims ({claimYield}/{claimKeptYield}) instead pay the UNDERLYING
///      ERC-20 (wxDAI): in pool mode the deployer wires the DistributionManager's baseToken =
///      wxDAI, so distributions move the real wrapped-native asset to recipients.
contract PoolNativeYield is AbstractStakePool {
    using SafeERC20 for IERC20;

    error IsCollateral();

    IWXDAI public immutable WX_DAI;
    ISXDAI public immutable SEXY_DAI;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _wxDai, address _sexyDai) {
        WX_DAI = IWXDAI(_wxDai);
        SEXY_DAI = ISXDAI(_sexyDai);
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

    /// @dev The pool reports the UNDERLYING (wxDAI) symbol — it is not its own token.
    function symbol() external view override returns (string memory) {
        return IERC20Metadata(address(WX_DAI)).symbol();
    }

    /// @dev The pool reports the UNDERLYING (wxDAI) decimals.
    function decimals() external view override returns (uint8) {
        return IERC20Metadata(address(WX_DAI)).decimals();
    }

    /// @dev Pull wxDAI from the depositor and route it into the sDAI vault (mirrors SexyDaiYield._deposit).
    /// @dev Fee-on-transfer underlyings are UNSUPPORTED (same as the token path): the ledger credits
    ///      `amount_`, but a transfer-fee asset would deposit less than `amount_` into the vault, so
    ///      the ledger supply would over-count the backing. wxDAI is a plain 1:1 wrapper, so this
    ///      holds; do not repoint this pool at a fee-charging wrapped-native token.
    function _deposit(uint256 amount_) internal override {
        IERC20(address(WX_DAI)).safeTransferFrom(msg.sender, address(this), amount_);
        IERC20(address(WX_DAI)).safeIncreaseAllowance(address(SEXY_DAI), amount_);
        SEXY_DAI.deposit(amount_, address(this));
    }

    /// @dev Wrap native xDAI to wxDAI then park in the sDAI vault (mirrors SexyDaiYield._depositNative).
    function _depositNative(uint256 amount_) internal override {
        WX_DAI.deposit{value: amount_}();
        IERC20(address(WX_DAI)).safeIncreaseAllowance(address(SEXY_DAI), amount_);
        SEXY_DAI.deposit(amount_, address(this));
    }

    /// @dev Principal withdrawal: redeem sDAI → wxDAI → native xDAI and forward (mirrors SexyDaiYield._remit).
    function _remit(address receiver_, uint256 amount_) internal override {
        SEXY_DAI.withdraw(amount_, address(this), address(this));
        WX_DAI.withdraw(amount_);
        _nativeTransfer(receiver_, amount_);
    }

    /// @dev Yield claim: redeem sDAI → wxDAI and transfer the UNDERLYING ERC-20 (wxDAI) to the
    ///      receiver. Unlike _remit this does NOT unwrap to native, because the DistributionManager's
    ///      baseToken is wxDAI and distributions move that ERC-20 to recipients.
    function _claimUnderlying(address receiver_, uint256 amount_) internal override {
        SEXY_DAI.withdraw(amount_, address(this), address(this));
        IERC20(address(WX_DAI)).safeTransfer(receiver_, amount_);
    }

    /// @notice Accept native xDAI unwrapped by WXDAI.withdraw during principal withdrawals.
    receive() external payable {}

    /// @dev Vault-backed surplus over ledger supply (mirrors SexyDaiYield._yieldAccrued).
    function _yieldAccrued() internal view override returns (uint256) {
        uint256 bal = IERC20(address(SEXY_DAI)).balanceOf(address(this));
        uint256 assets = SEXY_DAI.convertToAssets(bal);
        uint256 supply = totalSupply();
        return assets > supply ? assets - supply : 0;
    }

    /// @notice The underlying asset paid out on yield claims (the wrapped-native, wxDAI).
    /// @dev The deployer reads this to wire the DistributionManager's baseToken in pool mode.
    function underlyingAsset() external view returns (address) {
        return address(WX_DAI);
    }

    /// @notice Rescue tokens accidentally sent here — never the vault collateral.
    function rescueToken(address tok_, uint256 amount_) external onlyOwner {
        if (tok_ == address(SEXY_DAI)) revert IsCollateral();
        IERC20(tok_).safeTransfer(owner(), amount_);
    }
}
