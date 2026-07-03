"use client";

import { useActiveChainId } from "@/components/instance-provider";
import { chainConfig, nativeSymbol, type ChainConfig } from "@/lib/chains";

/** The config for the chain the active instance lives on. */
export function useActiveChain(): ChainConfig {
  return chainConfig(useActiveChainId());
}

/** Native currency symbol of the active chain (xDAI on Gnosis, ETH elsewhere). */
export function useNativeSymbol(): string {
  return nativeSymbol(useActiveChainId());
}

/**
 * The asset a stake is deposited into / redeemed for: the native currency on
 * native-yield chains (xDAI/ETH), or the stablecoin on stable-yield chains (USDC).
 */
export function useBaseAssetSymbol(): string {
  const chainId = useActiveChainId();
  const cfg = chainConfig(chainId);
  return cfg.yieldKind === "stable"
    ? cfg.wrappedSymbol
    : cfg.chain.nativeCurrency.symbol;
}
