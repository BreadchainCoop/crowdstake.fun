# Per-chain yield assets (WrappedNativeYield config)

`WrappedNativeYield(WRAPPED_NATIVE, YIELD_VAULT)` mints 1:1 on a native-currency
deposit, wraps it, and parks it in an ERC-4626 vault whose `asset()` **must
equal** `WRAPPED_NATIVE`. Yield = the vault's share appreciation. To deploy on a
chain, pass these two addresses as env vars to `DeployCrowdStakeDeployer`.

The design keeps the deposit **chain-native** (deposit ETH, redeem ETH). The
honest tradeoff: safe native-ETH ERC-4626 yield is thin today (~1%), because the
high-yield vaults on these chains are stablecoin-denominated (Morpho USDC,
~4-6.65%) which can't take a native-ETH deposit. See "Stablecoin alternative".

All rows below were **verified on-chain** (`asset()`, `decimals`,
`convertToAssets(1e18)` appreciating) unless marked otherwise.

| Chain | WRAPPED_NATIVE | YIELD_VAULT | Vault | ~APY | verified |
|-------|----------------|-------------|-------|------|----------|
| Gnosis (100) | WXDAI `0xe91D153E0b41518A2Ce8Dd3D7944Fa863463a97d` | sDAI `0xaf204776c7245bF4147c2612BF6e5972Ee483701` | Spark Savings DAI | ~variable (DSR) | ✅ asset()==WXDAI |
| Arbitrum (42161) | WETH `0x82aF49447D8a07e3bd95BD0d56f35241523fBab1` | waArbWETH `0x4cE13a79f45C1Be00BdABD38B764aC28C082704E` | Aave v3 Static aToken (WETH) | ~1.0% | ✅ asset()==WETH, 18dp, 1.065 |
| Optimism (10) | WETH `0x4200000000000000000000000000000000000006` | waOptWETH `0x464b808c2C7E04b07e860fDF7a91870620246148` | Aave v3 Static aToken (WETH) | ~1.24% | ✅ asset()==WETH, 18dp, 1.054 |
| Ethereum (1, config-only) | WETH `0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2` | Gauntlet WETH Core `0x4881Ef0BF6d2365D3dd6499ccd7532bcdBCE0658` (or Steakhouse ETH `0xBEEf050ecd6a16c4e7bfFbB52Ebba7846C4b8cD4`) | Morpho MetaMorpho (WETH) | ~1.5-1.6% | asset()==WETH per research; re-verify before deploy |

## Why Aave Static aTokens on the L2s
- `asset() == WETH` (verified), 18 decimals, non-rebasing share price that
  appreciates via `convertToAssets` — exactly the sDAI model, drop-in for the
  contract. Deposit routes WETH into the deep Aave WETH pool under the hood.
- Audited (BGD `static-a-token-v3`, Certora-verified).
- Immediate withdrawals (subject to Aave pool utilization; healthy today).

## Safety notes
- **Ethereum Aave WETH is tainted** by the April-2026 rsETH bridge exploit
  (~$200M bad debt parked in the mainnet Aave WETH pool). Do NOT use the
  Ethereum Aave WETH wrapper; prefer the Morpho Gauntlet/Steakhouse WETH vaults
  above, and re-verify before any mainnet deploy. The L2 Aave pools are separate
  deployments (verified appreciating), but re-check utilization at deploy time.
- Avoid LRT-heavy Morpho WETH vaults (Re7, MEV Capital) given the same incident.
- **Never use a vault with a withdrawal cooldown/queue** (e.g. Ethena sUSDe's
  7-day cooldown) — redemptions here are synchronous.

## Stablecoin alternative (higher yield, NOT chain-native)
If yield matters more than ETH-denomination, the best sDAI-equivalents are
stablecoin vaults — but they require an ERC-20 (USDC) deposit, make the stake
USD-denominated, and need a decimals-aware token variant (MetaMorpho shares are
18-dp vs 6-dp USDC):
- Optimism: Morpho **Gauntlet USDC Prime** `0xC30ce6A5758786e0F640cC5f881Dd96e9a1C5C59` (~6.65%, native USDC).
- Arbitrum: Morpho **Steakhouse High-Yield USDC** `0x5c0C306Aaa9F877de636f4d5822cA9F2E81563BA` (~4.17%) or Aave **waArbUSDCn** `0x7F6501d3B98eE91f9b9535E4b0ac710Fb0f9e0bc` (~2.47%, deepest).
- Ethereum: **sUSDS** `0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD` (~3.6%) or Yearn/Steakhouse USDC vaults.
- Spark **sUSDS/sDAI are ERC-4626 only on Ethereum** — on L2s they're bridged ERC-20 + a PSM, not a drop-in vault.
