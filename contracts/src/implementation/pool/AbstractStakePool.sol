// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IStakePool} from "../../interfaces/IStakePool.sol";
import {IVotesCheckpoints} from "../../interfaces/IVotesCheckpoints.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title AbstractStakePool
/// @author BreadKit
/// @notice Tokenless "pool mode" counterpart of {AbstractToken}. Communities can run an
///         instance where NO token is issued: deposits become ledger entries here, but yield,
///         voting and distribution mechanics are byte-for-byte the same as the token path.
/// @dev This contract is ABI-compatible with the surface the rest of the system consumes from
///      the token (the yield module, the deposit/withdraw entrypoints, the voting-power source),
///      WITHOUT being an ERC-20. It has NO transfer/approve/allowance and emits NO Transfer
///      events, which is precisely what keeps it invisible to wallets and explorers as a token.
///
///      The logic mirrors {AbstractToken} (see the cited line refs against
///      contracts/src/abstract/AbstractToken.sol) with two structural differences:
///        1. The ledger is a plain balance/supply mapping instead of ERC20VotesUpgradeable.
///        2. Yield claims (donated pool + kept shares) pay the UNDERLYING asset by redeeming
///           from the vault, rather than minting more pool balance. In pool mode the deployer
///           wires the DistributionManager's baseToken = the underlying asset, so recipients
///           receive the real asset.
///
///      Voting power: every deposit/withdraw writes an OZ Checkpoints.Checkpoint208 keyed by
///      block.number with the holder's post-change balance (auto self-delegated). This is the
///      exact shape ERC20Votes produces, so the EXISTING TimeWeightedVotingPower strategy — which
///      only reads numCheckpoints(account)/checkpoints(account,i) via IVotesCheckpoints — is
///      deployed against the pool unchanged (see TimeWeightedVotingPower.sol:36-45, :90-98).
///
///      Inheriting contracts must implement _deposit, _remit, _yieldAccrued, _claimUnderlying,
///      decimals() and symbol() — the same responsibilities SexyDaiYield/StableYield carry.
abstract contract AbstractStakePool is IStakePool, IVotesCheckpoints, Initializable, OwnableUpgradeable {
    using Checkpoints for Checkpoints.Trace208;

    // ============ Errors (mirror AbstractToken.sol:26-50) ============

    /// @notice Thrown when attempting to deposit zero
    error MintZero();
    /// @notice Thrown when attempting to withdraw zero
    error BurnZero();
    /// @notice Thrown when attempting to claim zero yield
    error ClaimZero();
    /// @notice Thrown when claimed amount exceeds available yield
    error YieldInsufficient();
    /// @notice Thrown when a non-claimer address attempts to claim yield
    error OnlyClaimer();
    /// @notice Thrown when a yield split exceeds 100% (10,000 bps)
    error InvalidYieldSplit();
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
    /// @notice Thrown when a withdrawal exceeds the holder's ledger balance
    error InsufficientBalance();

    // ============ Ledger + EIP-7201 Namespaced Storage ============

    /// @custom:storage-location erc7201:crowdstake.storage.AbstractStakePool
    struct AbstractStakePoolStorage {
        /// @notice Instance display name (the token's name() analogue)
        string name;
        /// @notice Ledger balance per holder (no ERC-20 Transfer semantics)
        mapping(address => uint256) balanceOf;
        /// @notice Total ledger supply
        uint256 totalSupply;
        /// @notice Per-holder self-delegated voting checkpoints (block.number => balance)
        mapping(address => Checkpoints.Trace208) checkpoints;
        /// @notice Address authorized to claim accrued yield (mirrors AbstractToken.sol:57)
        address yieldClaimer;
        /// @notice Address awaiting timelock to become the new yield claimer (AbstractToken.sol:59)
        address pendingYieldClaimer;
        /// @notice Timestamp after which the pending yield claimer can be finalized (AbstractToken.sol:61)
        uint256 pendingFinishedAt;
    }

    // keccak256(abi.encode(uint256(keccak256("crowdstake.storage.AbstractStakePool")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ABSTRACT_STAKE_POOL_STORAGE =
        0xa22a978ee2696d2efc2332b8f51ba192878a27319b07ef0b6ab02074b8399d00;

    function _getAbstractStakePoolStorage() internal pure returns (AbstractStakePoolStorage storage $) {
        assembly {
            $.slot := ABSTRACT_STAKE_POOL_STORAGE
        }
    }

    // ============ Yield Split Storage (mirrors AbstractToken.sol:77-111) ============

    /// @notice Basis-points denominator for yield splits (100% = 10,000)
    uint256 public constant YIELD_SPLIT_BPS = 10_000;

    /// @dev Precision scale for the yield-per-token accumulator (AbstractToken.sol:82).
    ///      High enough that the truncation lost per accrual (supply / YIELD_PRECISION wei)
    ///      stays sub-wei for any realistic supply; any dust lands in the donated pool.
    uint256 private constant YIELD_PRECISION = 1e27;

    /// @custom:storage-location erc7201:crowdstake.storage.PoolYieldSplit
    struct YieldSplitStorage {
        uint256 accYieldPerToken;
        uint256 accountedYield;
        uint256 keepWeight;
        uint256 keepWeightIndex;
        uint256 keptYieldTotal;
        mapping(address => uint16) keepBps;
        mapping(address => uint256) index;
        mapping(address => uint256) keptYield;
    }

    // keccak256(abi.encode(uint256(keccak256("crowdstake.storage.PoolYieldSplit")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant POOL_YIELD_SPLIT_STORAGE =
        0x644cf6815b2c79b6f21aa4ac6f2dcbb99137bf5f81d0e31beac1dbf7bec76e00;

    function _getYieldSplitStorage() internal pure returns (YieldSplitStorage storage $) {
        assembly {
            $.slot := POOL_YIELD_SPLIT_STORAGE
        }
    }

    // ============ Events ============

    /// @notice Emitted when a deposit is recorded in the ledger. NO ERC-20 Transfer event is
    ///         emitted — that omission is what keeps the pool invisible to wallets/explorers.
    event Deposited(address indexed receiver, uint256 amount);
    /// @notice Emitted when a withdrawal is recorded and the underlying is remitted.
    event Withdrawn(address indexed receiver, uint256 amount);
    /// @notice Emitted when the yield claimer is set or updated (AbstractToken.sol:151)
    event YieldClaimerSet(address yieldClaimer);
    /// @notice Emitted when a new pending yield claimer is proposed (AbstractToken.sol:153)
    event PendingYieldClaimerSet(address yieldClaimer);
    /// @notice Emitted when donated yield is claimed (AbstractToken.sol:155)
    event ClaimedYield(uint256 amount);
    /// @notice Emitted when a holder updates their yield split (AbstractToken.sol:157)
    event YieldSplitSet(address indexed account, uint16 keepBps);
    /// @notice Emitted when a holder claims their kept yield (AbstractToken.sol:159)
    event KeptYieldClaimed(address indexed account, address receiver, uint256 amount);

    // ============ Initialization ============

    /// @dev Sets the instance name + owner. Concrete pools call this from their initializer.
    // solhint-disable-next-line func-name-mixedcase
    function __AbstractStakePool_init(string memory name_, address owner_) internal onlyInitializing {
        __Ownable_init(owner_);
        _getAbstractStakePoolStorage().name = name_;
    }

    // ============ Ledger reads (the token's consumed surface, minus token semantics) ============

    /// @notice Ledger balance of an account
    function balanceOf(address account_) public view returns (uint256) {
        return _getAbstractStakePoolStorage().balanceOf[account_];
    }

    /// @notice Total ledger supply
    function totalSupply() public view returns (uint256) {
        return _getAbstractStakePoolStorage().totalSupply;
    }

    /// @notice Instance name (the token's name() analogue)
    function name() external view returns (string memory) {
        return _getAbstractStakePoolStorage().name;
    }

    /// @notice The UNDERLYING asset's symbol (e.g. WXDAI/USDC). MUST implement in derived.
    /// @dev Deliberately the underlying's symbol, not a synthetic one: the pool is not a token,
    ///      so surfaces that read symbol() label it by what was actually deposited.
    function symbol() external view virtual returns (string memory);

    /// @notice Decimals of the underlying asset. MUST implement in derived.
    function decimals() external view virtual returns (uint8);

    /// @notice Feature probe used by the frontend to detect pool (vs token) mode. Always true.
    function isPool() external pure returns (bool) {
        return true;
    }

    // ============ Deposit / Withdraw (signatures IDENTICAL to AbstractToken.sol:197/207/218) ============

    /// @notice Records a deposit of `amount_` of collateral for `receiver_` (ERC20 path).
    /// @dev Signature matches AbstractToken.mint(address,uint256) at AbstractToken.sol:197.
    function mint(address receiver_, uint256 amount_) external virtual {
        if (amount_ == 0) revert MintZero();
        _depositLedger(receiver_, amount_);
        _deposit(amount_);
    }

    /// @notice Records a deposit of native ETH for `receiver_` (native path).
    /// @dev Signature matches AbstractToken.mint(address) at AbstractToken.sol:207.
    function mint(address receiver_) external payable virtual {
        if (msg.value == 0) revert MintZero();
        _depositLedger(receiver_, msg.value);
        _depositNative(msg.value);
    }

    /// @notice Burns `amount_` of the caller's ledger balance and remits the underlying to `receiver_`.
    /// @dev Signature matches AbstractToken.burn(uint256,address) at AbstractToken.sol:218.
    function burn(uint256 amount_, address receiver_) external virtual {
        if (amount_ == 0) revert BurnZero();
        _withdrawLedger(msg.sender, amount_);
        _remit(receiver_, amount_);
        emit Withdrawn(receiver_, amount_);
    }

    // ============ Yield module surface (consumed by BaseDistributionManager) ============

    /// @notice Unclaimed donated yield — the pool the yield claimer can distribute (AbstractToken.sol:368).
    function yieldAccrued() external view returns (uint256) {
        return _donatedYieldAccrued();
    }

    /// @notice Total unclaimed vault surplus: donated pool plus all kept shares (AbstractToken.sol:373).
    function totalYieldAccrued() external view returns (uint256) {
        return _yieldAccrued();
    }

    /// @notice Claims accrued donated yield and remits the UNDERLYING to the receiver.
    /// @dev Mirrors AbstractToken.claimYield (AbstractToken.sol:232) but pays the underlying by
    ///      redeeming from the vault instead of minting pool balance. Only the donated portion is
    ///      claimable here; holders' kept shares stay reserved for them.
    /// @dev INVARIANT: assumes the yield vault is a standard ERC-4626 that rounds convertToAssets
    ///      DOWN and previewWithdraw UP (sDAI and Morpho conform). yieldAccrued() values the
    ///      position via the round-down convertToAssets, and _claimUnderlying withdraws exactly
    ///      `amount_`; because the accrued figure never over-counts, a claim can always be satisfied
    ///      by a round-up-cost withdraw. A vault that rounds the other way could report more accrued
    ///      than is withdrawable and brick claims — do NOT wire such a vault in as the yield source.
    function claimYield(uint256 amount_, address receiver_) external virtual {
        AbstractStakePoolStorage storage $ = _getAbstractStakePoolStorage();
        if (msg.sender != $.yieldClaimer) revert OnlyClaimer();
        if (amount_ == 0) revert ClaimZero();
        _accrueGlobalYield();
        uint256 yield = _donatedYieldAccrued();
        if (yield == 0) revert YieldInsufficient();
        if (yield < amount_) revert YieldInsufficient();

        // Redeem the underlying from the vault to the receiver (vs. AbstractToken minting).
        _claimUnderlying(receiver_, amount_);
        // The claim consumed vault surplus; keep the high-water mark in sync (AbstractToken.sol:244).
        _getYieldSplitStorage().accountedYield -= amount_;

        emit ClaimedYield(amount_);
    }

    // ============ Yield Split (mirrors AbstractToken.sol:254-306) ============

    /// @notice Sets the caller's yield split (AbstractToken.sol:254). Settlement point.
    function setYieldSplit(uint16 keepBps_) external {
        if (keepBps_ > YIELD_SPLIT_BPS) revert InvalidYieldSplit();
        YieldSplitStorage storage $ = _getYieldSplitStorage();
        _accrueGlobalYield();
        _settleAndDetach(msg.sender);
        // Re-baseline so only yield accrued after this change uses the new split.
        $.index[msg.sender] = $.accYieldPerToken;
        $.keepBps[msg.sender] = keepBps_;
        _attach(msg.sender);

        emit YieldSplitSet(msg.sender, keepBps_);
    }

    /// @notice The share of their yield an account keeps, in bps (AbstractToken.sol:268).
    function yieldSplitOf(address account_) external view returns (uint16) {
        return _getYieldSplitStorage().keepBps[account_];
    }

    /// @notice An account's kept yield: settled balance plus unsettled share (AbstractToken.sol:273).
    function keptYieldOf(address account_) external view returns (uint256) {
        YieldSplitStorage storage $ = _getYieldSplitStorage();
        uint256 kept = $.keptYield[account_];
        uint256 bps = $.keepBps[account_];
        if (bps == 0) return kept;
        uint256 acc = _simulatedAccYieldPerToken();
        uint256 idx = $.index[account_];
        if (acc > idx) {
            kept += balanceOf(account_) * (acc - idx) / YIELD_PRECISION * bps / YIELD_SPLIT_BPS;
        }
        return kept;
    }

    /// @notice Claims the caller's kept yield, remitting the UNDERLYING to `receiver_`.
    /// @dev Mirrors AbstractToken.claimKeptYield (AbstractToken.sol:288) but pays the underlying
    ///      by redeeming from the vault instead of minting pool balance. Settlement point.
    function claimKeptYield(address receiver_) external {
        YieldSplitStorage storage $ = _getYieldSplitStorage();
        _accrueGlobalYield();
        _settleAndDetach(msg.sender);
        _attach(msg.sender);

        uint256 amount = $.keptYield[msg.sender];
        if (amount == 0) revert ClaimZero();
        if (_yieldAccrued() < amount) revert YieldInsufficient();
        $.keptYield[msg.sender] = 0;
        $.keptYieldTotal -= amount;

        _claimUnderlying(receiver_, amount);
        // The claim consumed vault surplus; keep the high-water mark in sync (AbstractToken.sol:303).
        $.accountedYield -= amount;

        emit KeptYieldClaimed(msg.sender, receiver_, amount);
    }

    // ============ Yield claimer role + timelock (mirrors AbstractToken.sol:311-345) ============

    /// @notice Current yield claimer address
    function yieldClaimer() public view returns (address) {
        return _getAbstractStakePoolStorage().yieldClaimer;
    }

    /// @notice Address awaiting timelock to become the new yield claimer
    function pendingYieldClaimer() public view returns (address) {
        return _getAbstractStakePoolStorage().pendingYieldClaimer;
    }

    /// @notice Timestamp after which the pending yield claimer can be finalized
    function pendingFinishedAt() public view returns (uint256) {
        return _getAbstractStakePoolStorage().pendingFinishedAt;
    }

    /// @notice Sets the initial yield claimer address (one-time only) (AbstractToken.sol:311).
    function setYieldClaimer(address yieldClaimer_) external onlyOwner {
        AbstractStakePoolStorage storage $ = _getAbstractStakePoolStorage();
        if (yieldClaimer_ == address(0)) revert ZeroAddress();
        if ($.yieldClaimer != address(0)) revert AlreadySetClaimer();
        $.yieldClaimer = yieldClaimer_;

        emit YieldClaimerSet(yieldClaimer_);
    }

    /// @notice Initiates a 14-day timelock to rotate the yield claimer (AbstractToken.sol:323).
    function prepareNewYieldClaimer(address _newYieldClaimer) external onlyOwner {
        AbstractStakePoolStorage storage $ = _getAbstractStakePoolStorage();
        if (_newYieldClaimer == address(0)) revert ZeroAddress();
        if ($.yieldClaimer == _newYieldClaimer) revert SameClaimer();
        if ($.pendingFinishedAt > 0) revert PendingClaimer();
        $.pendingYieldClaimer = _newYieldClaimer;
        $.pendingFinishedAt = block.timestamp + 14 days;

        emit PendingYieldClaimerSet(_newYieldClaimer);
    }

    /// @notice Finalizes the pending yield claimer after the 14-day timelock (AbstractToken.sol:336).
    function finalizeNewYieldClaimer() external {
        AbstractStakePoolStorage storage $ = _getAbstractStakePoolStorage();
        if ($.pendingFinishedAt == 0) revert NoPendingClaimer();
        if (block.timestamp < $.pendingFinishedAt) revert TimelockNotElapsed();
        $.yieldClaimer = $.pendingYieldClaimer;
        $.pendingYieldClaimer = address(0);
        $.pendingFinishedAt = 0;

        emit YieldClaimerSet($.yieldClaimer);
    }

    // ============ Voting power: IVotesCheckpoints over the ledger ============

    /// @notice Number of voting checkpoints for `account` (mirrors ERC20Votes numCheckpoints).
    /// @dev The only checkpoint accessor TimeWeightedVotingPower calls at runtime
    ///      (TimeWeightedVotingPower.sol:90) besides {checkpoints}.
    function numCheckpoints(address account) external view returns (uint32) {
        return SafeCast.toUint32(_getAbstractStakePoolStorage().checkpoints[account].length());
    }

    /// @notice The `pos`-th voting checkpoint for `account` (block.number => balance).
    /// @dev Matches ERC20Votes' shape so the existing strategy walks it unchanged
    ///      (TimeWeightedVotingPower.sol:98).
    function checkpoints(address account, uint32 pos) external view returns (Checkpoints.Checkpoint208 memory) {
        return _getAbstractStakePoolStorage().checkpoints[account].at(pos);
    }

    /// @notice Current voting weight = ledger balance (holders are auto self-delegated).
    function getVotes(address account) external view returns (uint256) {
        return _getAbstractStakePoolStorage().checkpoints[account].latest();
    }

    /// @notice Historical voting weight at a past block (upper-lookup on the checkpoint trace).
    function getPastVotes(address account, uint256 timepoint) external view returns (uint256) {
        if (timepoint >= block.number) revert("future lookup");
        return _getAbstractStakePoolStorage().checkpoints[account].upperLookup(SafeCast.toUint48(timepoint));
    }

    /// @notice Past total supply is not checkpointed; the strategy never calls it. Reverts.
    function getPastTotalSupply(uint256) external pure returns (uint256) {
        revert("unsupported");
    }

    /// @notice Every holder is auto self-delegated; delegation is fixed to `account`.
    function delegates(address account) external pure returns (address) {
        return account;
    }

    /// @notice Delegation is fixed (auto self-delegation); explicit delegation is a no-op-revert.
    function delegate(address) external pure {
        revert("delegation fixed");
    }

    /// @notice Delegation is fixed (auto self-delegation); signed delegation is unsupported.
    function delegateBySig(address, uint256, uint256, uint8, bytes32, bytes32) external pure {
        revert("delegation fixed");
    }

    // ============ Ledger internals ============

    /// @dev Credits `receiver_` and checkpoints their new balance. Settlement point around the
    ///      balance change (mirrors AbstractToken._update at AbstractToken.sol:456).
    function _depositLedger(address receiver_, uint256 amount_) internal {
        if (receiver_ == address(0)) revert ZeroAddress();
        AbstractStakePoolStorage storage $ = _getAbstractStakePoolStorage();

        _accrueGlobalYield();
        _settleAndDetach(receiver_);

        $.balanceOf[receiver_] += amount_;
        $.totalSupply += amount_;
        _writeCheckpoint(receiver_, $.balanceOf[receiver_]);

        _attach(receiver_);

        emit Deposited(receiver_, amount_);
    }

    /// @dev Debits `from_` and checkpoints their new balance. Settlement point around the change.
    function _withdrawLedger(address from_, uint256 amount_) internal {
        AbstractStakePoolStorage storage $ = _getAbstractStakePoolStorage();
        if ($.balanceOf[from_] < amount_) revert InsufficientBalance();

        _accrueGlobalYield();
        _settleAndDetach(from_);

        $.balanceOf[from_] -= amount_;
        $.totalSupply -= amount_;
        _writeCheckpoint(from_, $.balanceOf[from_]);

        _attach(from_);
    }

    /// @dev Pushes a (block.number, balance) checkpoint. Same shape ERC20Votes writes on delegate
    ///      vote moves, so the strategy reads it identically. Repeated writes in one block
    ///      overwrite the current block's entry (OZ Checkpoints._insert semantics).
    function _writeCheckpoint(address account, uint256 balance) private {
        _getAbstractStakePoolStorage()
        .checkpoints[account].push(SafeCast.toUint48(block.number), SafeCast.toUint208(balance));
    }

    // ============ Yield Split Internals (ported verbatim from AbstractToken.sol:381-452) ============

    /// @dev Attributes fresh vault surplus to current holders via the accumulator (AbstractToken.sol:381).
    function _accrueGlobalYield() internal {
        YieldSplitStorage storage $ = _getYieldSplitStorage();
        uint256 raw = _yieldAccrued();
        uint256 accounted = $.accountedYield;
        if (raw <= accounted) return;
        uint256 supply = totalSupply();
        if (supply > 0) {
            $.accYieldPerToken += (raw - accounted) * YIELD_PRECISION / supply;
        }
        $.accountedYield = raw;
    }

    /// @dev The accumulator as if _accrueGlobalYield ran now (AbstractToken.sol:395).
    function _simulatedAccYieldPerToken() private view returns (uint256 acc) {
        YieldSplitStorage storage $ = _getYieldSplitStorage();
        acc = $.accYieldPerToken;
        uint256 raw = _yieldAccrued();
        uint256 accounted = $.accountedYield;
        uint256 supply = totalSupply();
        if (raw > accounted && supply > 0) {
            acc += (raw - accounted) * YIELD_PRECISION / supply;
        }
    }

    /// @dev Vault surplus minus every holder's kept share (AbstractToken.sol:409).
    function _donatedYieldAccrued() private view returns (uint256) {
        YieldSplitStorage storage $ = _getYieldSplitStorage();
        uint256 raw = _yieldAccrued();
        uint256 unsettledKept =
            (_simulatedAccYieldPerToken() * $.keepWeight - $.keepWeightIndex) / YIELD_PRECISION / YIELD_SPLIT_BPS;
        uint256 reserved = $.keptYieldTotal + unsettledKept;
        return raw > reserved ? raw - reserved : 0;
    }

    /// @dev Credits pending kept yield and removes the account from the aggregates (AbstractToken.sol:421).
    function _settleAndDetach(address account_) internal {
        if (account_ == address(0)) return;
        YieldSplitStorage storage $ = _getYieldSplitStorage();
        uint256 bps = $.keepBps[account_];
        if (bps == 0) return;
        uint256 balance = balanceOf(account_);
        uint256 acc = $.accYieldPerToken;
        uint256 idx = $.index[account_];
        if (acc > idx) {
            uint256 kept = balance * (acc - idx) / YIELD_PRECISION * bps / YIELD_SPLIT_BPS;
            if (kept > 0) {
                $.keptYield[account_] += kept;
                $.keptYieldTotal += kept;
            }
        }
        uint256 weight = balance * bps;
        $.keepWeight -= weight;
        $.keepWeightIndex -= weight * idx;
        $.index[account_] = acc;
    }

    /// @dev Adds the account's current balance/split terms to the aggregates (AbstractToken.sol:444).
    function _attach(address account_) internal {
        if (account_ == address(0)) return;
        YieldSplitStorage storage $ = _getYieldSplitStorage();
        uint256 bps = $.keepBps[account_];
        if (bps == 0) return;
        uint256 weight = balanceOf(account_) * bps;
        $.keepWeight += weight;
        $.keepWeightIndex += weight * $.index[account_];
    }

    // ============ Hooks the concrete pool must implement (mirror the token's) ============

    /// @dev Deposit user collateral into the yield-bearing position (mirrors AbstractToken._deposit).
    function _deposit(uint256 amount_) internal virtual;

    /// @dev Deposit native collateral into the yield-bearing position (mirrors AbstractToken._depositNative).
    function _depositNative(
        uint256 /*amount_*/
    )
        internal
        virtual
    {
        revert("native deposits not supported");
    }

    /// @dev Remit collateral value to a withdrawing user (mirrors AbstractToken._remit).
    function _remit(address receiver_, uint256 amount_) internal virtual;

    /// @dev Redeem `amount_` of the UNDERLYING from the vault to `receiver_`. This is the pool's
    ///      replacement for the token's yield-claim mint: claimYield/claimKeptYield pay the real
    ///      asset. Typically identical to _remit (redeem from the vault), but named separately so
    ///      implementations can distinguish principal withdrawals from yield claims if needed.
    function _claimUnderlying(address receiver_, uint256 amount_) internal virtual;

    /// @dev Unclaimed accrued yield = vault-backed assets minus ledger supply (mirrors AbstractToken._yieldAccrued).
    function _yieldAccrued() internal view virtual returns (uint256);

    /// @dev Transfers native ETH, reverts on failure (AbstractToken.sol:474).
    function _nativeTransfer(address to_, uint256 amount_) internal {
        bool success;
        assembly {
            success := call(gas(), to_, amount_, 0, 0, 0, 0)
        }
        if (!success) revert NativeTransferFailed();
    }
}
