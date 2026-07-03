"use client";

import { useEffect, useState, type ReactNode } from "react";
import { WagmiProvider } from "wagmi";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { RainbowKitProvider, lightTheme } from "@rainbow-me/rainbowkit";
import "@rainbow-me/rainbowkit/styles.css";
import { wagmiConfig } from "@/lib/wagmi";
import { InstanceProvider } from "@/components/instance-provider";
import { DemoModeProvider } from "@/components/demo-mode-provider";
import { hydrateRemoteAddresses } from "@/lib/remote-addresses";

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

  return (
    <WagmiProvider config={wagmiConfig}>
      <QueryClientProvider client={queryClient}>
        <RainbowKitProvider
          theme={lightTheme({
            accentColor: "#EA5817", // core-orange
            accentColorForeground: "#ffffff",
            borderRadius: "medium",
          })}
        >
          <InstanceProvider key={addressesVersion}>
            <DemoModeProvider>{children}</DemoModeProvider>
          </InstanceProvider>
        </RainbowKitProvider>
      </QueryClientProvider>
    </WagmiProvider>
  );
}
