"use client";

import { ChainType, LiFiWidget, type WidgetConfig } from "@lifi/widget";

/**
 * The embedded LI.FI widget, isolated in its own module so it can be pulled in
 * lazily (via `next/dynamic`, `ssr: false`) — it drags a heavy, browser-only
 * dependency tree that must stay out of the server render and the initial
 * client bundle. Rendered inside a modal by {@link ../dapp/add-funds}.
 *
 * The destination token/chain are locked to the instance's deposit asset so the
 * bridge/swap/on-ramp always lands exactly what the deposit form expects; the
 * user chooses the source chain/token and (optionally) connects a source wallet
 * inside the widget's own audited UI.
 */
export default function FundLifiWidget({
  toChainId,
  toToken,
  toAddress,
}: {
  toChainId: number;
  toToken: string;
  toAddress?: string;
}) {
  const config: Partial<WidgetConfig> = {
    variant: "compact",
    subvariant: "default",
    appearance: "light",
    toChain: toChainId,
    toToken,
    // Lock the destination — the user is here to fund one specific asset.
    disabledUI: ["toToken"],
    chains: {
      // Common source chains people already hold funds on.
      allow: [1, 10, 100, 137, 8453, 42161, 43114, 56],
    },
    ...(toAddress
      ? {
          toAddress: {
            address: toAddress,
            chainType: ChainType.EVM,
            name: "Your wallet",
          },
        }
      : {}),
    theme: {
      colorSchemes: {
        light: {
          palette: {
            primary: { main: "#EA5817" },
            secondary: { main: "#EA5817" },
            info: { main: "#EA5817" },
            success: { main: "#32a800" },
            error: { main: "#df0b00" },
            background: { default: "#f6f3eb", paper: "#fdfcf9" },
            text: { primary: "#171414", secondary: "#595959" },
            grey: { 200: "#808080", 300: "#eae2d6", 700: "#595959" },
          },
        },
      },
      typography: { fontFamily: "inherit" },
      container: {
        border: "1px solid #eae2d6",
        borderRadius: "1rem",
      },
      shape: { borderRadius: 12, borderRadiusSecondary: 8 },
    },
  };

  return <LiFiWidget config={config} integrator="crowdstake" />;
}
