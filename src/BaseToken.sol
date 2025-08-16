// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IBreadKitToken} from "./interfaces/IBreadKitToken.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@solady/contracts/auth/Ownable.sol";
import {
    ERC20VotesUpgradeable,
    ERC20Upgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";

abstract contract BaseToken is ERC20VotesUpgradeable, Ownable, IBreadKitToken {
    error MintZero();
    error BurnZero();
    error ClaimZero();
    error YieldInsufficient();
    error OnlyClaimer();
    error NoPendingClaimer();
    error PendingClaimer();
    error AlreadySetClaimer();
    error SameClaimer();
    error NativeTransferFailed();
    error ZeroAddress();

    address public yieldClaimer;
    address public pendingYieldClaimer;
    uint256 public pendingFinishedAt;

    event Minted(address receiver, uint256 amount);
    event Burned(address receiver, uint256 amount);
    event YieldClaimerSet(address yieldClaimer);
    event PendingYieldClaimerSet(address yieldClaimer);
    event ClaimedYield(uint256 amount);

    /// @dev MUST implement in derived contract
    /// logic to deposit user collateral into yield bearing position
    function _deposit(uint256 /*amount_*/ ) internal virtual {}

    /// @dev OPTIONAL to implement in derived contract
    /// logic to deposit native token into yield bearing position
    function _depositNative(uint256 /*amount_*/ ) internal virtual {
        revert("native deposits not supported");
    }

    /// @dev MUST implement in derived contract
    /// logic to remit collateral value to user
    function _remit(address, /*receiver_*/ uint256 /*amount_*/ ) internal virtual {}

    /// @dev MUST implement in derived contract
    /// logic to calculate unclaimed accrued yield
    function _yieldAccrued() internal view virtual returns (uint256) {}

    function mint(address receiver_, uint256 amount_) external virtual {
        if (amount_ == 0) revert MintZero();

        _mintAndDelegate(receiver_, amount_);

        _deposit(amount_);
    }

    function mint(address receiver_) external payable virtual {
        if (msg.value == 0) revert MintZero();

        _mintAndDelegate(receiver_, msg.value);

        _depositNative(msg.value);
    }

    function burn(uint256 amount_, address receiver_) external virtual {
        if (amount_ == 0) revert BurnZero();
        _burn(msg.sender, amount_);

        _remit(receiver_, amount_);

        emit Burned(receiver_, amount_);
    }

    function claimYield(uint256 amount_, address receiver_) external virtual {
        if (msg.sender != yieldClaimer) revert OnlyClaimer();
        if (amount_ == 0) revert ClaimZero();
        uint256 yield = _yieldAccrued();
        if (yield < amount_) revert YieldInsufficient();

        _mint(receiver_, amount_);
        if (this.delegates(receiver_) == address(0)) _delegate(receiver_, receiver_);

        emit ClaimedYield(amount_);
    }

    function setYieldClaimer(address yieldClaimer_) external onlyOwner {
        if (yieldClaimer_ == address(0)) revert ZeroAddress();
        if (yieldClaimer != address(0)) revert AlreadySetClaimer();
        yieldClaimer = yieldClaimer_;

        emit YieldClaimerSet(yieldClaimer_);
    }

    function prepareNewYieldClaimer(address _newYieldClaimer) external onlyOwner {
        if (_newYieldClaimer == address(0)) revert ZeroAddress();
        if (yieldClaimer == _newYieldClaimer) revert SameClaimer();
        if (pendingFinishedAt > 0) revert PendingClaimer();
        pendingYieldClaimer = _newYieldClaimer;
        pendingFinishedAt = block.timestamp + 14 days;

        emit PendingYieldClaimerSet(_newYieldClaimer);
    }

    function finalizeNewYieldClaimer() external {
        if (pendingFinishedAt == 0) revert NoPendingClaimer();
        yieldClaimer = pendingYieldClaimer;
        pendingFinishedAt = 0;

        emit YieldClaimerSet(yieldClaimer);
    }

    function transfer(address recipient_, uint256 amount_) public override(ERC20Upgradeable, IERC20) returns (bool) {
        super.transfer(recipient_, amount_);
        if (this.delegates(recipient_) == address(0)) _delegate(recipient_, recipient_);
        return true;
    }

    function transferFrom(address from_, address to_, uint256 value_)
        public
        override(ERC20Upgradeable, IERC20)
        returns (bool)
    {
        super.transferFrom(from_, to_, value_);
        if (this.delegates(to_) == address(0)) _delegate(to_, to_);
        return true;
    }

    function yieldAccrued() external view returns (uint256) {
        return _yieldAccrued();
    }

    function _mintAndDelegate(address receiver_, uint256 amount_) internal {
        _mint(receiver_, amount_);
        if (this.delegates(receiver_) == address(0)) _delegate(receiver_, receiver_);

        emit Minted(receiver_, amount_);
    }

    function _nativeTransfer(address to_, uint256 amount_) internal {
        bool success;
        assembly {
            // Transfer the ETH and store if it succeeded or not.
            success := call(gas(), to_, amount_, 0, 0, 0, 0)
        }

        if (!success) revert NativeTransferFailed();
    }
}
