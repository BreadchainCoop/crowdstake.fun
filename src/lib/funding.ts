import { chainConfig } from "@/lib/chains";

/** LI.FI represents a chain's native currency with the zero address. */
export const NATIVE_TOKEN = "0x0000000000000000000000000000000000000000";

/**
 * The token a user needs to fund in order to deposit on a given chain — i.e.
 * the instance's *deposit asset*: the native currency (0x0) on native-yield
 * chains, or USDC on stable-yield chains. Used as LI.FI's locked destination
 * token so any funding flow lands exactly what the deposit form expects.
 */
export function fundToToken(chainId: number): string {
  const cfg = chainConfig(chainId);
  return cfg.yieldKind === "stable" && cfg.wrappedToken
    ? cfg.wrappedToken
    : NATIVE_TOKEN;
}

/**
 * A LI.FI (Jumper) hosted-app deep link that lands the active chain's deposit
 * asset pre-selected as the destination. We embed the @lifi/widget in-app for
 * the primary flow; this hosted link is the "open in a new tab" fallback for
 * users who'd rather run the bridge/on-ramp on LI.FI's own site.
 */
export function jumperFundUrl(chainId: number, toAddress?: string): string {
  const params = new URLSearchParams({
    toChain: String(chainId),
    toToken: fundToToken(chainId),
  });
  if (toAddress) params.set("toAddress", toAddress);
  return `https://jumper.exchange/?${params.toString()}`;
}
