// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IWXDAI} from "../../interfaces/IWXDAI.sol";
import {ISXDAI} from "../../interfaces/ISXDAI.sol";
import {AbstractToken} from "../../abstract/AbstractToken.sol";

contract SexyDaiYield is AbstractToken {
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

    function initialize(string memory name_, string memory symbol_, address owner_) external initializer {
        __ERC20_init(name_, symbol_);
        _initializeOwner(owner_);
    }

    function _deposit(uint256 amount_) internal override {
        IERC20(address(WX_DAI)).safeTransferFrom(msg.sender, address(this), amount_);
        IERC20(address(WX_DAI)).safeIncreaseAllowance(address(SEXY_DAI), amount_);
        SEXY_DAI.deposit(amount_, address(this));
    }

    function _depositNative(uint256 amount_) internal override {
        WX_DAI.deposit{value: amount_}();
        IERC20(address(WX_DAI)).safeIncreaseAllowance(address(SEXY_DAI), amount_);
        SEXY_DAI.deposit(amount_, address(this));
    }

    function _remit(address receiver_, uint256 amount_) internal override {
        // This contract holds the sDAI shares, so it is both the ERC-4626 `owner`
        // (whose shares are burned) and the `receiver` of the unwrapped wxDAI.
        // The native xDAI is then forwarded to `receiver_` below.
        SEXY_DAI.withdraw(amount_, address(this), address(this));
        WX_DAI.withdraw(amount_);
        _nativeTransfer(receiver_, amount_);
    }

    /// @notice Accept native xDAI sent during withdrawals (WXDAI.withdraw unwraps wxDAI → xDAI
    ///         to this contract before it is forwarded to the redeemer).
    receive() external payable {}

    function _yieldAccrued() internal view override returns (uint256) {
        uint256 bal = IERC20(address(SEXY_DAI)).balanceOf(address(this));
        uint256 assets = SEXY_DAI.convertToAssets(bal);
        uint256 supply = totalSupply();
        return assets > supply ? assets - supply : 0;
    }

    // NOTE: just a convenience rescuer of accidentally burned tokens
    // not part of BreadKitToken interface as may not be safe for all breadkit token types
    function rescueToken(address tok_, uint256 amount_) external onlyOwner {
        if (tok_ == address(SEXY_DAI)) revert IsCollateral();
        IERC20(tok_).safeTransfer(owner(), amount_);
    }
}
