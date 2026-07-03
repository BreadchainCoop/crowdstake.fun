import { type Address, type Chain } from "viem";
import { arbitrum, gnosis, mainnet, optimism } from "viem/chains";

/** The full set of contract addresses that make up one CrowdStake instance. */
export interface InstanceAddresses {
  token: Address;
  distributionManager: Address;
  cycleModule: Address;
  votingModule: Address;
  recipientRegistry: Address;
  distributionStrategy: Address;
  votingPowerStrategy: Address;
}

/** Per-chain deployment + presentation config. */
export interface ChainConfig {
  chain: Chain;
  /** RPC endpoint (env-overridable per chain via NEXT_PUBLIC_RPC_URL_<id>). */
  rpcUrl: string;
  /** Canonical CrowdStakeDeployer on this chain, or null if not deployed yet. */
  deployer: Address | null;
  /** The instance that ships with the app on this chain, if any. */
  defaultInstance: InstanceAddresses | null;
  /** The ERC20 the yield token wraps native into (WXDAI on Gnosis), if any. */
  wrappedToken: Address | null;
  /** Human symbol for the wrapped ERC20 (e.g. WXDAI). */
  wrappedSymbol: string;
  /**
   * Seconds per `block.number` increment on this chain — used to convert a
   * time-based cycle length to/from blocks. NOTE: this tracks what the EVM
   * `block.number` opcode does, which on Arbitrum follows the ~L1 cadence, not
   * the sub-second L2 block rate.
   */
  blockTimeSeconds: number;
  /** Block explorer base URL. */
  explorer: string;
  /** Whether new instances can be deployed here (deployer present). */
  deployable: boolean;
}

const env = (key: string) => {
  const v = process.env[key];
  return v && v.length > 0 ? v : undefined;
};

// Gnosis's native token is branded "xDAI"; viem labels it "XDAI". Use the
// branded casing for display (RPC/wallet key on chain id, not the symbol).
const gnosisChain: Chain = {
  ...gnosis,
  nativeCurrency: { ...gnosis.nativeCurrency, symbol: "xDAI" },
};

/** The Gnosis instance that ships with the app (see contracts/deployments). */
const GNOSIS_INSTANCE: InstanceAddresses = {
  token: (env("NEXT_PUBLIC_TOKEN_ADDRESS") ??
    "0x7E94a840143E3D5C78f367bBe45e6fB6e55098ec") as Address,
  distributionManager: (env("NEXT_PUBLIC_DISTRIBUTION_MANAGER_ADDRESS") ??
    "0xB38B15ad418202D3FdC1A139cEc51A8c13f59CB6") as Address,
  cycleModule: (env("NEXT_PUBLIC_CYCLE_MODULE_ADDRESS") ??
    "0xDfBDa0C7061276C3B8a08aC38fEdeE63c0B63827") as Address,
  votingModule: (env("NEXT_PUBLIC_VOTING_MODULE_ADDRESS") ??
    "0xf921AF0C0fCd4A9dE0F6C58b34b05DBCCf0aAc42") as Address,
  recipientRegistry: (env("NEXT_PUBLIC_RECIPIENT_REGISTRY_ADDRESS") ??
    "0x8e61175AbBC31A07237367e356833C83204945C2") as Address,
  distributionStrategy: (env("NEXT_PUBLIC_DISTRIBUTION_STRATEGY_ADDRESS") ??
    "0x91c71E49212137e750192a3dbf78878a810ACe1D") as Address,
  votingPowerStrategy: (env("NEXT_PUBLIC_VOTING_POWER_STRATEGY_ADDRESS") ??
    "0x3F477A1FD83F56537BEE5cC05406fF4628e7A399") as Address,
};

/**
 * Supported chains. Gnosis is fully live; the L2s + Ethereum are configured so
 * the app can read/switch/deploy on them once a CrowdStakeDeployer is deployed
 * there (`deployer` flips from null → address). `NEXT_PUBLIC_DEPLOYER_<id>` and
 * `NEXT_PUBLIC_RPC_URL_<id>` override per chain.
 */
export const CHAINS: Record<number, ChainConfig> = {
  [gnosis.id]: {
    chain: gnosisChain,
    rpcUrl: env("NEXT_PUBLIC_RPC_URL") ?? "https://rpc.gnosischain.com",
    deployer: (env("NEXT_PUBLIC_DEPLOYER_ADDRESS") ??
      "0x4D6178572690B39D04d2E790E1D0c776f2cBBC95") as Address,
    defaultInstance: GNOSIS_INSTANCE,
    wrappedToken: "0xe91D153E0b41518A2Ce8Dd3D7944Fa863463a97d" as Address, // WXDAI
    wrappedSymbol: "WXDAI",
    blockTimeSeconds: 5,
    explorer: "https://gnosisscan.io",
    deployable: true,
  },
  [arbitrum.id]: {
    chain: arbitrum,
    rpcUrl: env("NEXT_PUBLIC_RPC_URL_42161") ?? "https://arb1.arbitrum.io/rpc",
    deployer: (env("NEXT_PUBLIC_DEPLOYER_42161") ?? null) as Address | null,
    defaultInstance: null,
    wrappedToken: null,
    wrappedSymbol: "WETH",
    blockTimeSeconds: 12, // block.number follows the L1 cadence on Arbitrum
    explorer: "https://arbiscan.io",
    deployable: !!env("NEXT_PUBLIC_DEPLOYER_42161"),
  },
  [optimism.id]: {
    chain: optimism,
    rpcUrl: env("NEXT_PUBLIC_RPC_URL_10") ?? "https://mainnet.optimism.io",
    deployer: (env("NEXT_PUBLIC_DEPLOYER_10") ?? null) as Address | null,
    defaultInstance: null,
    wrappedToken: null,
    wrappedSymbol: "WETH",
    blockTimeSeconds: 2,
    explorer: "https://optimistic.etherscan.io",
    deployable: !!env("NEXT_PUBLIC_DEPLOYER_10"),
  },
  [mainnet.id]: {
    chain: mainnet,
    rpcUrl:
      env("NEXT_PUBLIC_RPC_URL_1") ?? "https://ethereum-rpc.publicnode.com",
    deployer: (env("NEXT_PUBLIC_DEPLOYER_1") ?? null) as Address | null,
    defaultInstance: null,
    wrappedToken: null,
    wrappedSymbol: "WETH",
    blockTimeSeconds: 12,
    explorer: "https://etherscan.io",
    deployable: !!env("NEXT_PUBLIC_DEPLOYER_1"),
  },
};

/** The chain shown before a wallet connects, and the app's home instance. */
export const DEFAULT_CHAIN_ID = gnosis.id;

/** Ordered list of viem chains for the wagmi config. */
export const SUPPORTED_CHAINS: readonly [Chain, ...Chain[]] = [
  gnosisChain,
  arbitrum,
  optimism,
  mainnet,
];

/** Config for a chain id, falling back to the default chain. */
export function chainConfig(chainId?: number): ChainConfig {
  return (chainId && CHAINS[chainId]) || CHAINS[DEFAULT_CHAIN_ID];
}

/** Native currency symbol for a chain (e.g. xDAI, ETH). */
export function nativeSymbol(chainId?: number): string {
  return chainConfig(chainId).chain.nativeCurrency.symbol;
}

/** Whether a chain id is one we support. */
export function isSupportedChain(chainId?: number): boolean {
  return !!chainId && chainId in CHAINS;
}

/** Block-explorer transaction URL for a chain. */
export function txUrl(hash: string, chainId?: number): string {
  return `${chainConfig(chainId).explorer}/tx/${hash}`;
}

/** Block-explorer address URL for a chain. */
export function addressUrl(address: string, chainId?: number): string {
  return `${chainConfig(chainId).explorer}/address/${address}`;
}
