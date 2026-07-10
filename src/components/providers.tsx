"use client";

import { useEffect, useState, type ReactNode } from "react";
import { WagmiProvider } from "wagmi";
import { WagmiProvider as PrivyWagmiProvider } from "@privy-io/wagmi";
import { PrivyProvider } from "@privy-io/react-auth";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fallbackWagmiConfig, privyWagmiConfig } from "@/lib/wagmi";
import { PRIVY_APP_ID, privyConfigured } from "@/lib/constants";
import { CHAINS, DEFAULT_CHAIN_ID, SUPPORTED_CHAINS } from "@/lib/chains";
import { WagmiWalletActions } from "@/components/wallet/wallet-actions";
import { PrivyWalletActions } from "@/components/wallet/privy-wallet-actions";
import { InstanceProvider } from "@/components/instance-provider";
import { DemoModeProvider } from "@/components/demo-mode-provider";
import { TelegramProvider } from "@/components/telegram-provider";
import { hydrateRemoteAddresses } from "@/lib/remote-addresses";
import { isTelegramMiniApp } from "@/lib/telegram";

export function Providers({ children }: { children: ReactNode }) {
  // One QueryClient per browser session; hashFn keeps bigint query keys stable.
  const [queryClient] = useState(
    () =>
      new QueryClient({
        defaultOptions: {
          queries: { refetchOnWindowFocus: false, retry: 2 },
        },
      }),
  );

  // Runtime address hydration: fetch the latest published contract addresses
  // (rolling `contract-addresses` GitHub release) and merge them into CHAINS,
  // so contract deploys go live without a frontend rebuild. On change, bump
  // the key to remount the instance subtree so every consumer re-reads the
  // fresh addresses. Fail-soft: baked-in addresses are used otherwise.
  const [addressesVersion, setAddressesVersion] = useState(0);
  useEffect(() => {
    let active = true;
    void hydrateRemoteAddresses().then((updated) => {
      if (active && updated) setAddressesVersion(1);
    });
    return () => {
      active = false;
    };
  }, []);

  // Privy is a client-only SDK; never run its provider during the static-export
  // prerender. Render the fallback wagmi tree on the server + first client paint
  // (correct HTML, hooks work), then mount the Privy tree on the client.
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);
  const usePrivyTree = privyConfigured() && mounted;

  // Telegram's webview injects no wallet; inside a Mini App launch Privy's
  // seamless Telegram auth (dashboard: Telegram login + seamless enabled)
  // signs the user into an embedded wallet with zero clicks — it reads the
  // #tgWebAppData launch hash on its own. Offering `telegram` in the modal is
  // scoped to that context so the web experience is unchanged. Evaluated only
  // in the mounted (client) Privy tree, so the value is settled when read.
  const inTelegram = isTelegramMiniApp();

  const app = (
    <InstanceProvider key={addressesVersion}>
      <DemoModeProvider>{children}</DemoModeProvider>
    </InstanceProvider>
  );

  return (
    <TelegramProvider>
      <QueryClientProvider client={queryClient}>
        {usePrivyTree ? (
          // Embedded wallets + native ("App pays", EIP-7702) gas sponsorship, so
          // cross-chain governance is submitted gaslessly from the browser.
          <PrivyProvider
            appId={PRIVY_APP_ID}
            config={{
              embeddedWallets: {
                ethereum: { createOnLogin: "users-without-wallets" },
                showWalletUIs: false,
              },
              defaultChain: CHAINS[DEFAULT_CHAIN_ID].chain,
              supportedChains: [...SUPPORTED_CHAINS],
              appearance: { accentColor: "#EA5817" },
              loginMethods: inTelegram
                ? ["telegram", "email", "wallet"]
                : ["email", "wallet"],
            }}
          >
            <PrivyWagmiProvider config={privyWagmiConfig}>
              <PrivyWalletActions>{app}</PrivyWalletActions>
            </PrivyWagmiProvider>
          </PrivyProvider>
        ) : (
          // No Privy (SSR, local dev, e2e) → plain wagmi/injected, self-paid gas.
          <WagmiProvider config={fallbackWagmiConfig}>
            <WagmiWalletActions>{app}</WagmiWalletActions>
          </WagmiProvider>
        )}
      </QueryClientProvider>
    </TelegramProvider>
  );
}
