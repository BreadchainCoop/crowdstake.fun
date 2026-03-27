// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IToken} from "../interfaces/IToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@solady/contracts/auth/Ownable.sol";
import {
    ERC20VotesUpgradeable,
    ERC20Upgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";

/// @title AbstractToken
/// @author BreadKit
/// @notice Abstract base contract for yield-bearing ERC20 tokens with voting delegation
/// @dev Extends ERC20VotesUpgradeable with yield claiming, a two-phase yield claimer transfer
///      mechanism (14-day timelock), and automatic delegation on transfers/mints.
///      Inheriting contracts must implement _deposit, _remit, and _yieldAccrued.
abstract contract AbstractToken is ERC20VotesUpgradeable, Ownable, IToken {
    /// @notice Thrown when attempting to mint zero tokens
    error MintZero();
    /// @notice Thrown when attempting to burn zero tokens
    error BurnZero();
    /// @notice Thrown when attempting to claim zero yield
    error ClaimZero();
    /// @notice Thrown when claimed amount exceeds available yield
    error YieldInsufficient();
    /// @notice Thrown when a non-claimer address attempts to claim yield
    error OnlyClaimer();
    /// @notice Thrown when finalizing with no pending claimer
    error NoPendingClaimer();
    /// @notice Thrown when preparing a new claimer while one is already pending
    error PendingClaimer();
    /// @notice Thrown when finalizing before the 14-day timelock has elapsed
    error TimelockNotElapsed();
    /// @notice Thrown when setting yield claimer after it has already been set
    error AlreadySetClaimer();
    /// @notice Thrown when preparing a new claimer that matches the current one
    error SameClaimer();
    /// @notice Thrown when a native ETH transfer fails
    error NativeTransferFailed();
    /// @notice Thrown when a zero address is provided
    error ZeroAddress();

    // ============ EIP-7201 Namespaced Storage ============

    /// @custom:storage-location erc7201:crowdstake.storage.AbstractToken
    struct AbstractTokenStorage {
        /// @notice Address authorized to claim accrued yield
        address yieldClaimer;
        /// @notice Address awaiting timelock to become the new yield claimer
        address pendingYieldClaimer;
        /// @notice Timestamp after which the pending yield claimer can be finalized
        uint256 pendingFinishedAt;
    }

    // keccak256(abi.encode(uint256(keccak256("crowdstake.storage.AbstractToken")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ABSTRACT_TOKEN_STORAGE =
        0x6746ae24d567a69cac363d4ed8572608d7aa218bd671c5a748fb340bd7db1000;

    function _getAbstractTokenStorage() internal pure returns (AbstractTokenStorage storage $) {
        assembly {
            $.slot := ABSTRACT_TOKEN_STORAGE
        }
    }

    // ============ Public Getters ============

    /// @notice Returns the current yield claimer address
    function yieldClaimer() public view returns (address) {
        return _getAbstractTokenStorage().yieldClaimer;
    }

    /// @notice Returns the address awaiting timelock to become the new yield claimer
    function pendingYieldClaimer() public view returns (address) {
        return _getAbstractTokenStorage().pendingYieldClaimer;
    }

    /// @notice Returns the timestamp after which the pending yield claimer can be finalized
    function pendingFinishedAt() public view returns (uint256) {
        return _getAbstractTokenStorage().pendingFinishedAt;
    }

    // ============ Events ============

    /// @notice Emitted when tokens are minted to a receiver
    event Minted(address receiver, uint256 amount);
    /// @notice Emitted when tokens are burned for a receiver
    event Burned(address receiver, uint256 amount);
    /// @notice Emitted when the yield claimer is set or updated
    event YieldClaimerSet(address yieldClaimer);
    /// @notice Emitted when a new pending yield claimer is proposed
    event PendingYieldClaimerSet(address yieldClaimer);
    /// @notice Emitted when yield is claimed
    event ClaimedYield(uint256 amount);

    /// @dev MUST implement in derived contract
    /// logic to deposit user collateral into yield bearing position
    function _deposit(
        uint256 /*amount_*/
    )
        internal
        virtual {}

    /// @dev OPTIONAL to implement in derived contract
    /// logic to deposit native token into yield bearing position
    function _depositNative(
        uint256 /*amount_*/
    )
        internal
        virtual
    {
        revert("native deposits not supported");
    }

    /// @dev MUST implement in derived contract
    /// logic to remit collateral value to user
    function _remit(
        address,
        /*receiver_*/
        uint256 /*amount_*/
    )
        internal
        virtual {}

    /// @dev MUST implement in derived contract
    /// logic to calculate unclaimed accrued yield
    function _yieldAccrued() internal view virtual returns (uint256) {}

    /// @notice Mints tokens to the receiver by depositing the specified amount of collateral
    /// @param receiver_ Address to receive the minted tokens
    /// @param amount_ Amount of collateral to deposit and tokens to mint
    function mint(address receiver_, uint256 amount_) external virtual {
        if (amount_ == 0) revert MintZero();

        _mintAndDelegate(receiver_, amount_);

        _deposit(amount_);
    }

    /// @notice Mints tokens to the receiver by depositing native ETH
    /// @param receiver_ Address to receive the minted tokens
    function mint(address receiver_) external payable virtual {
        if (msg.value == 0) revert MintZero();

        _mintAndDelegate(receiver_, msg.value);

        _depositNative(msg.value);
    }

    /// @notice Burns tokens from the caller and remits the underlying collateral to the receiver
    /// @param amount_ Amount of tokens to burn
    /// @param receiver_ Address to receive the underlying collateral
    function burn(uint256 amount_, address receiver_) external virtual {
        if (amount_ == 0) revert BurnZero();
        _burn(msg.sender, amount_);

        _remit(receiver_, amount_);

        emit Burned(receiver_, amount_);
    }

    /// @notice Claims accrued yield and mints it as tokens to the receiver
    /// @dev Only callable by the authorized yield claimer
    /// @param amount_ Amount of yield to claim
    /// @param receiver_ Address to receive the minted yield tokens
    function claimYield(uint256 amount_, address receiver_) external virtual {
        AbstractTokenStorage storage $ = _getAbstractTokenStorage();
        if (msg.sender != $.yieldClaimer) revert OnlyClaimer();
        if (amount_ == 0) revert ClaimZero();
        uint256 yield = _yieldAccrued();
        if (yield == 0) revert YieldInsufficient();
        if (yield < amount_) revert YieldInsufficient();

        _mint(receiver_, amount_);
        if (this.delegates(receiver_) == address(0)) _delegate(receiver_, receiver_);

        emit ClaimedYield(amount_);
    }

    /// @notice Sets the initial yield claimer address (one-time only)
    /// @dev Can only be called by the owner and only when no claimer has been set
    /// @param yieldClaimer_ Address to authorize as the yield claimer
    function setYieldClaimer(address yieldClaimer_) external onlyOwner {
        AbstractTokenStorage storage $ = _getAbstractTokenStorage();
        if (yieldClaimer_ == address(0)) revert ZeroAddress();
        if ($.yieldClaimer != address(0)) revert AlreadySetClaimer();
        $.yieldClaimer = yieldClaimer_;

        emit YieldClaimerSet(yieldClaimer_);
    }

    /// @notice Initiates a 14-day timelock to transfer yield claimer role to a new address
    /// @dev Reverts if a transfer is already pending or the new address matches the current claimer
    /// @param _newYieldClaimer Address to become the new yield claimer after the timelock
    function prepareNewYieldClaimer(address _newYieldClaimer) external onlyOwner {
        AbstractTokenStorage storage $ = _getAbstractTokenStorage();
        if (_newYieldClaimer == address(0)) revert ZeroAddress();
        if ($.yieldClaimer == _newYieldClaimer) revert SameClaimer();
        if ($.pendingFinishedAt > 0) revert PendingClaimer();
        $.pendingYieldClaimer = _newYieldClaimer;
        $.pendingFinishedAt = block.timestamp + 14 days;

        emit PendingYieldClaimerSet(_newYieldClaimer);
    }

    /// @notice Finalizes the pending yield claimer transfer after the 14-day timelock
    /// @dev Callable by anyone once the timelock has elapsed
    function finalizeNewYieldClaimer() external {
        AbstractTokenStorage storage $ = _getAbstractTokenStorage();
        if ($.pendingFinishedAt == 0) revert NoPendingClaimer();
        if (block.timestamp < $.pendingFinishedAt) revert TimelockNotElapsed();
        $.yieldClaimer = $.pendingYieldClaimer;
        $.pendingYieldClaimer = address(0);
        $.pendingFinishedAt = 0;

        emit YieldClaimerSet($.yieldClaimer);
    }

    /// @notice Transfers tokens and auto-delegates the recipient if they have no delegate set
    function transfer(address recipient_, uint256 amount_) public override(ERC20Upgradeable, IERC20) returns (bool) {
        super.transfer(recipient_, amount_);
        if (this.delegates(recipient_) == address(0)) _delegate(recipient_, recipient_);
        return true;
    }

    /// @notice Transfers tokens on behalf of another address and auto-delegates the recipient
    function transferFrom(address from_, address to_, uint256 value_)
        public
        override(ERC20Upgradeable, IERC20)
        returns (bool)
    {
        super.transferFrom(from_, to_, value_);
        if (this.delegates(to_) == address(0)) _delegate(to_, to_);
        return true;
    }

    /// @notice Returns the total unclaimed accrued yield
    function yieldAccrued() external view returns (uint256) {
        return _yieldAccrued();
    }

    /// @dev Mints tokens to the receiver and auto-delegates if no delegate is set
    function _mintAndDelegate(address receiver_, uint256 amount_) internal {
        _mint(receiver_, amount_);
        if (this.delegates(receiver_) == address(0)) _delegate(receiver_, receiver_);

        emit Minted(receiver_, amount_);
    }

    /// @dev Transfers native ETH to an address, reverts on failure
    function _nativeTransfer(address to_, uint256 amount_) internal {
        bool success;
        assembly {
            // Transfer the ETH and store if it succeeded or not.
            success := call(gas(), to_, amount_, 0, 0, 0, 0)
        }

        if (!success) revert NativeTransferFailed();
    }
}
