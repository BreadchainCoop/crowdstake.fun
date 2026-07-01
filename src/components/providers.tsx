"use client";

import { useState, type ReactNode } from "react";
import { WagmiProvider } from "wagmi";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { RainbowKitProvider, lightTheme } from "@rainbow-me/rainbowkit";
import "@rainbow-me/rainbowkit/styles.css";
import { wagmiConfig } from "@/lib/wagmi";
import { InstanceProvider } from "@/components/instance-provider";
import { DemoModeProvider } from "@/components/demo-mode-provider";

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
          <InstanceProvider>
            <DemoModeProvider>{children}</DemoModeProvider>
          </InstanceProvider>
        </RainbowKitProvider>
      </QueryClientProvider>
    </WagmiProvider>
  );
}
