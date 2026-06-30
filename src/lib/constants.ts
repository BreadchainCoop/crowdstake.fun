import { gnosis } from "wagmi/chains";
import type { Address } from "viem";

/** The chain the dapp targets (Gnosis mainnet, id 100). */
export const CHAIN = gnosis;
export const CHAIN_ID = gnosis.id;

/** Treat empty-string env vars (e.g. an unset CI repo var) as absent. */
const envOr = (value: string | undefined, fallback: string): string =>
  value && value.length > 0 ? value : fallback;

/** RPC + WalletConnect project id (override via env for production). */
export const RPC_URL = envOr(
  process.env.NEXT_PUBLIC_RPC_URL,
  "https://rpc.gnosischain.com",
);
export const WALLETCONNECT_PROJECT_ID = envOr(
  process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID,
  "crowdstake_demo",
);

const env = (key: string, fallback: Address): Address =>
  envOr(process.env[key], fallback) as Address;

/**
 * Deployed CrowdStake system on Gnosis mainnet
 * (see contracts/deployments/gnosis.json). Overridable via NEXT_PUBLIC_* env.
 */
export const ADDRESSES = {
  token: env(
    "NEXT_PUBLIC_TOKEN_ADDRESS",
    "0x7E94a840143E3D5C78f367bBe45e6fB6e55098ec",
  ),
  distributionManager: env(
    "NEXT_PUBLIC_DISTRIBUTION_MANAGER_ADDRESS",
    "0xB38B15ad418202D3FdC1A139cEc51A8c13f59CB6",
  ),
  cycleModule: env(
    "NEXT_PUBLIC_CYCLE_MODULE_ADDRESS",
    "0xDfBDa0C7061276C3B8a08aC38fEdeE63c0B63827",
  ),
  votingModule: env(
    "NEXT_PUBLIC_VOTING_MODULE_ADDRESS",
    "0xf921AF0C0fCd4A9dE0F6C58b34b05DBCCf0aAc42",
  ),
  recipientRegistry: env(
    "NEXT_PUBLIC_RECIPIENT_REGISTRY_ADDRESS",
    "0x8e61175AbBC31A07237367e356833C83204945C2",
  ),
  distributionStrategy: env(
    "NEXT_PUBLIC_DISTRIBUTION_STRATEGY_ADDRESS",
    "0x91c71E49212137e750192a3dbf78878a810ACe1D",
  ),
  votingPowerStrategy: env(
    "NEXT_PUBLIC_VOTING_POWER_STRATEGY_ADDRESS",
    "0x3F477A1FD83F56537BEE5cC05406fF4628e7A399",
  ),
} as const;

/** CrowdStakeDeployer — one-tx full-instance deployer (reuses the live factory + beacons). */
export const DEPLOYER: Address = env(
  "NEXT_PUBLIC_DEPLOYER_ADDRESS",
  "0x6193210E25aAc4f645D2a7e9420Cb57B0F193033",
);

/** Underlying Gnosis tokens used by the SexyDaiYield token. */
export const WXDAI: Address = "0xe91D153E0b41518A2Ce8Dd3D7944Fa863463a97d";
export const SDAI: Address = "0xaf204776c7245bF4147c2612BF6e5972Ee483701";

/** The yield-bearing project token: 18 decimals, ERC20Votes. */
export const TOKEN_SYMBOL = "CSTAKE";
export const TOKEN_DECIMALS = 18;

/** Voting is basis-points based; max per recipient. */
export const MAX_POINTS = 10_000n;

export const BLOCK_EXPLORER = "https://gnosisscan.io";
export const txUrl = (hash: string) => `${BLOCK_EXPLORER}/tx/${hash}`;
export const addressUrl = (a: string) => `${BLOCK_EXPLORER}/address/${a}`;
