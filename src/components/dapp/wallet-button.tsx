"use client";

import { useAccount } from "wagmi";
import { Button } from "@breadcoop/ui";
import { SignOut } from "@phosphor-icons/react";
import { useWalletActions } from "@/components/wallet/wallet-actions";

/** Shortened `0x1234…abcd` address. */
function shortAddress(address: string): string {
  return `${address.slice(0, 6)}…${address.slice(-4)}`;
}

/**
 * Wallet connect / account control for the nav. Backed by Privy (email/social +
 * external wallets, gasless) when configured, else a plain injected wallet.
 * Address + connection come from wagmi, so this one component works in both.
 */
export function WalletButton({
  full = false,
  size,
}: {
  full?: boolean;
  /** Button size — the nav passes "sm" so it fits the h-16 row. */
  size?: "sm";
}) {
  const { address, isConnected } = useAccount();
  const { connect, disconnect } = useWalletActions();

  if (!isConnected || !address) {
    return (
      <Button
        app="fund"
        variant="primary"
        size={size}
        className={full ? "w-full" : "whitespace-nowrap"}
        onClick={connect}
      >
        Connect wallet
      </Button>
    );
  }

  return (
    <div className="flex items-center gap-2">
      <span className="border-paper-2 text-text-standard rounded-full border px-3 py-1.5 font-mono text-sm">
        {shortAddress(address)}
      </span>
      <Button
        app="fund"
        variant="secondary"
        size={size}
        className="px-2"
        onClick={disconnect}
        leftIcon={<SignOut weight="bold" />}
        aria-label="Disconnect wallet"
      >
        <span className="sr-only">Disconnect</span>
      </Button>
    </div>
  );
}
