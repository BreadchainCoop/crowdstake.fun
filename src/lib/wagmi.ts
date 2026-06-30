import { http } from "wagmi";
import { gnosis } from "wagmi/chains";
import { getDefaultConfig } from "@rainbow-me/rainbowkit";
import { RPC_URL, WALLETCONNECT_PROJECT_ID } from "@/lib/constants";

/**
 * wagmi + RainbowKit config. Single chain (Gnosis). Injected wallets
 * (MetaMask/Rabby/Brave) work out of the box; WalletConnect activates when
 * a real NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID is provided.
 */
export const wagmiConfig = getDefaultConfig({
  appName: "Crowdstaking",
  projectId: WALLETCONNECT_PROJECT_ID,
  chains: [gnosis],
  transports: {
    [gnosis.id]: http(RPC_URL),
  },
  ssr: true,
});
