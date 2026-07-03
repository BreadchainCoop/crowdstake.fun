import { http } from "wagmi";
import { getDefaultConfig } from "@rainbow-me/rainbowkit";
import { WALLETCONNECT_PROJECT_ID } from "@/lib/constants";
import { CHAINS, SUPPORTED_CHAINS } from "@/lib/chains";

/**
 * wagmi + RainbowKit config across every supported chain (Gnosis + Arbitrum,
 * Optimism, Ethereum). Injected wallets work out of the box; WalletConnect
 * activates when a real NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID is provided.
 */
export const wagmiConfig = getDefaultConfig({
  appName: "Crowdstaking",
  projectId: WALLETCONNECT_PROJECT_ID,
  chains: SUPPORTED_CHAINS,
  transports: Object.fromEntries(
    SUPPORTED_CHAINS.map((c) => [c.id, http(CHAINS[c.id].rpcUrl)]),
  ),
  ssr: true,
});
