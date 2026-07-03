# Per-chain yield assets

Two token kinds, selected per chain by the deploy env `YIELD_KIND`:

- **`native`** — `SexyDaiYield(ASSET, YIELD_VAULT)`: deposit native currency,
  wrap it, park in an ERC-4626 vault whose `asset()` == the wrapped-native. Used
  on Gnosis (native xDAI is a dollar, so sDAI gives real yield).
- **`stable`** — `StableYield(ASSET, YIELD_VAULT)`: deposit an ERC-20 stablecoin
  (USDC) into a stablecoin ERC-4626 vault. Used on the ETH L2s, where native-ETH
  vault yield is ~1% but **stablecoin yield is 4-6.65%**. No native path; token
  decimals mirror the stablecoin (6).

In both cases `YIELD_VAULT.asset()` **must equal** `ASSET` (constructor-enforced).
All rows **verified on-chain** (`asset()`, `decimals`, appreciating `convertToAssets`).

## Chosen config (highest safe yield per chain)

| Chain | KIND | ASSET | YIELD_VAULT | Vault / ~APY | verified |
|-------|------|-------|-------------|--------------|----------|
| Gnosis (100) | native | WXDAI `0xe91D153E0b41518A2Ce8Dd3D7944Fa863463a97d` | sDAI `0xaf204776c7245bF4147c2612BF6e5972Ee483701` | Spark Savings DAI | ✅ asset()==WXDAI |
| Arbitrum (42161) | **stable** | USDC `0xaf88d065e77c8cC2239327C5EDb3A432268e5831` | Steakhouse HY USDC `0x5c0C306Aaa9F877de636f4d5822cA9F2E81563BA` | Morpho ~4.17% | ✅ asset()==USDC |
| Optimism (10) | **stable** | USDC `0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85` | Gauntlet USDC Prime `0xC30ce6A5758786e0F640cC5f881Dd96e9a1C5C59` | Morpho ~6.65% | ✅ asset()==USDC |
| Ethereum (1, config-only) | stable | USDC `0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48` | sUSDS `0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD` or a Morpho/Yearn USDC vault | ~3.6% | re-verify before deploy |

**Deploy via the etherform CI workflow** (`Deploy contracts (multi-chain)` →
Run workflow), so the key stays a repo secret (`DEPLOY_PRIVATE_KEY`, funded on
the target chain). For Optimism stablecoin, set the inputs:
- chain: `optimism`
- target: `DeployCrowdStakeDeployer`
- yield_kind: `stable`
- asset: `0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85` (native USDC)
- yield_vault: `0xC30ce6A5758786e0F640cC5f881Dd96e9a1C5C59` (Gauntlet USDC Prime)

The run summary prints the deployer address + the `NEXT_PUBLIC_DEPLOYER_10` repo
variable to set. (Locally, the equivalent is `YIELD_KIND=stable ASSET=… YIELD_VAULT=…
PRIVATE_KEY=… forge script script/DeployCrowdStakeDeployer.s.sol --rpc-url <op> --broadcast`.)

## Native-ETH alternative (rejected — ~1% yield)
The safe native-ETH ERC-4626 vaults (Aave Static aTokens, `asset()==WETH`, 18dp,
verified appreciating): Arbitrum waArbWETH `0x4cE13a79f45C1Be00BdABD38B764aC28C082704E`
(~1.0%, 1.065), Optimism waOptWETH `0x464b808c2C7E04b07e860fDF7a91870620246148`
(~1.24%, 1.054), Ethereum Morpho Gauntlet WETH Core
`0x4881Ef0BF6d2365D3dd6499ccd7532bcdBCE0658` (~1.5%). They work with
`YIELD_KIND=native` + `ASSET=WETH` but yield far less than the stablecoin vaults.

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
