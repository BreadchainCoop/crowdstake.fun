import { chainConfig } from "@/lib/chains";

/** LI.FI/Jumper represents a chain's native currency with the zero address. */
const NATIVE_TOKEN = "0x0000000000000000000000000000000000000000";

/**
 * A LI.FI (Jumper) hosted-app deep link that lands the active chain's *deposit
 * asset* — native xDAI/ETH on native-yield chains, USDC on stable-yield chains —
 * pre-selected as the destination. Jumper covers bridging + swapping from any
 * chain/token AND a fiat on-ramp (buy with card), so it's the one funding entry
 * point that gets a user from "no funds" to "ready to deposit" on any chain.
 *
 * Hosted rather than the embedded @lifi/widget on purpose: the widget pulls a
 * heavy, non-EVM (Sui) dependency tree that doesn't build under our static
 * export, and its own audited UI is safer to route funds through.
 */
export function jumperFundUrl(chainId: number, toAddress?: string): string {
  const cfg = chainConfig(chainId);
  const toToken =
    cfg.yieldKind === "stable" && cfg.wrappedToken
      ? cfg.wrappedToken
      : NATIVE_TOKEN;
  const params = new URLSearchParams({
    toChain: String(chainId),
    toToken,
  });
  if (toAddress) params.set("toAddress", toAddress);
  return `https://jumper.exchange/?${params.toString()}`;
}
