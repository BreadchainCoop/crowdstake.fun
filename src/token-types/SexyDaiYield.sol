// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IWXDAI} from "../interfaces/IWXDAI.sol";
import {ISXDAI} from "../interfaces/ISXDAI.sol";
import {BaseToken} from "../BaseToken.sol";

contract SexyDaiYield is BaseToken {
    using SafeERC20 for IERC20;

    error IsCollateral();

    IWXDAI public immutable wxDai;
    ISXDAI public immutable sexyDai;

    constructor(address _wxDai, address _sexyDai) {
        wxDai = IWXDAI(_wxDai);
        sexyDai = ISXDAI(_sexyDai);
    }

    function initialize(string memory name_, string memory symbol_, address owner_) external initializer {
        __ERC20_init(name_, symbol_);
        _initializeOwner(owner_);
    }

    function _deposit(uint256 amount_) internal override {
        IERC20(address(wxDai)).safeTransferFrom(msg.sender, address(this), amount_);
        IERC20(address(wxDai)).safeIncreaseAllowance(address(sexyDai), amount_);
        sexyDai.deposit(amount_, address(this));
    }

    function _depositNative(uint256 amount_) internal override {
        wxDai.deposit{value: amount_}();
        IERC20(address(wxDai)).safeIncreaseAllowance(address(sexyDai), amount_);
        sexyDai.deposit(amount_, address(this));
    }

    function _remit(address receiver_, uint256 amount_) internal override {
        sexyDai.withdraw(amount_, address(this), receiver_);
        wxDai.withdraw(amount_);
        _nativeTransfer(receiver_, amount_);
    }

    function _yieldAccrued() internal view override returns (uint256) {
        uint256 bal = IERC20(address(sexyDai)).balanceOf(address(this));
        uint256 assets = sexyDai.convertToAssets(bal);
        uint256 supply = totalSupply();
        return assets > supply ? assets - supply : 0;
    }

    // NOTE: just a convenience rescuer of accidentally burned tokens
    // not part of BreadKitToken interface as may not be safe for all breadkit token types
    function rescueToken(address tok_, uint256 amount_) external onlyOwner {
        if (tok_ == address(sexyDai)) revert IsCollateral();
        IERC20(tok_).safeTransfer(owner(), amount_);
    }
}
