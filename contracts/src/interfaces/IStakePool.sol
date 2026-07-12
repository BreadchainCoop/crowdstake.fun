// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IStakePool
/// @notice The surface a tokenless "pool mode" instance exposes. It is ABI-compatible with the
///         parts of the token that the rest of the system consumes (deposit/withdraw, the yield
///         module, the yield split, the yield-claimer role) WITHOUT being an ERC-20: there is no
///         transfer/approve/allowance and no Transfer event, which is what keeps a pool invisible
///         to wallets and explorers as a token.
/// @dev Deposit/withdraw signatures are IDENTICAL to AbstractToken (mint/burn at
///      AbstractToken.sol:197/207/218) so the same deploy wiring and frontend entrypoints work.
///      Voting power is exposed separately via {IVotesCheckpoints}, which the pool also implements.
interface IStakePool {
    // ---- Ledger reads ----
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function name() external view returns (string memory);
    /// @notice The UNDERLYING asset's symbol (e.g. WXDAI/USDC) — the pool is not its own token.
    function symbol() external view returns (string memory);
    /// @notice Decimals of the underlying asset.
    function decimals() external view returns (uint8);
    /// @notice Feature probe: always true. Lets the frontend detect pool (vs token) mode.
    function isPool() external pure returns (bool);
    /// @notice The UNDERLYING asset paid out on yield claims (and principal withdrawals). The
    ///         deployer reads this to wire the DistributionManager's baseToken in pool mode.
    function underlyingAsset() external view returns (address);

    // ---- Deposit / withdraw (signatures identical to the token) ----
    function mint(address receiver) external payable;
    function mint(address receiver, uint256 amount) external;
    function burn(uint256 amount, address receiver) external;

    // ---- Yield module (consumed by BaseDistributionManager) ----
    function yieldAccrued() external view returns (uint256);
    function totalYieldAccrued() external view returns (uint256);
    /// @notice Claims donated yield, paying the UNDERLYING asset (redeemed from the vault).
    function claimYield(uint256 amount, address receiver) external;

    // ---- Yield claimer role + timelocked rotation ----
    function yieldClaimer() external view returns (address);
    function setYieldClaimer(address yieldClaimer) external;
    function prepareNewYieldClaimer(address yieldClaimer) external;
    function finalizeNewYieldClaimer() external;

    // ---- Per-holder yield split ----
    function setYieldSplit(uint16 keepBps) external;
    function yieldSplitOf(address account) external view returns (uint16);
    function keptYieldOf(address account) external view returns (uint256);
    /// @notice Claims the caller's kept yield, paying the UNDERLYING asset (redeemed from the vault).
    function claimKeptYield(address receiver) external;
}
