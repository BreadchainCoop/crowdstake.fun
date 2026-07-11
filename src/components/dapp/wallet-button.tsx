"use client";

import { useAccount } from "wagmi";
import { Button } from "@breadcoop/ui";
import { SignOut } from "@phosphor-icons/react";
import { cn } from "@/lib/utils";
import { useWalletActions } from "@/components/wallet/wallet-actions";

/** Shortened `0x1234…abcd` address. */
function shortAddress(address: string): string {
  return `${address.slice(0, 6)}…${address.slice(-4)}`;
}

/**
 * Wallet connect / account control. Backed by Privy (email/social + external
 * wallets, gasless) when configured, else a plain injected wallet. Address +
 * connection come from wagmi, so this one component works in both.
 *
 * `nav` renders the quiet pill variant: the design system's brutalist offset
 * shadow reads as clutter inside the slim h-16 bar, so the nav gets a flat
 * rounded-full treatment instead.
 */
export function WalletButton({
  full = false,
  size,
  nav = false,
}: {
  full?: boolean;
  /** Button size — the nav passes "sm" so it fits the h-16 row. */
  size?: "sm";
  /** Quiet rounded-pill styling for the nav bar. */
  nav?: boolean;
}) {
  const { address, isConnected } = useAccount();
  const { connect, disconnect } = useWalletActions();

  if (!isConnected || !address) {
    return (
      <Button
        app="fund"
        variant="primary"
        size={size}
        className={cn(
          full ? "w-full" : "whitespace-nowrap",
          nav && "rounded-full shadow-none",
        )}
        onClick={connect}
      >
        Connect wallet
      </Button>
    );
  }

  return (
    <div className="flex items-center gap-1.5">
      <span
        className={cn(
          "border-paper-2 text-text-standard rounded-full border font-mono",
          nav ? "bg-paper-0 h-8 px-3 text-xs leading-8" : "px-3 py-1.5 text-sm",
        )}
      >
        {shortAddress(address)}
      </span>
      <button
        onClick={disconnect}
        aria-label="Disconnect wallet"
        title="Disconnect"
        className={cn(
          "border-paper-2 text-surface-grey-2 hover:text-core-orange hover:border-core-orange/40 flex items-center justify-center rounded-full border transition-colors",
          nav ? "h-8 w-8" : "h-9 w-9",
        )}
      >
        <SignOut size={16} weight="bold" />
      </button>
    </div>
  );
}
