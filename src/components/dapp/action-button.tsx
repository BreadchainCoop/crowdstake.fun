"use client";

import type { ReactNode } from "react";
import { useAccount, useSwitchChain } from "wagmi";
import { useConnectModal } from "@rainbow-me/rainbowkit";
import { Button } from "@breadcoop/ui";
import { useActiveChain } from "@/hooks/use-chain";

type Variant = "primary" | "secondary" | "destructive";

/**
 * Primary action button that's connection-aware: prompts to connect when
 * disconnected and to switch to Gnosis on the wrong chain, otherwise runs the
 * action. Lets pages show their full form before a wallet is connected.
 */
export function ActionButton({
  children,
  onClick,
  isLoading,
  disabled,
  variant = "primary",
  className = "w-full",
}: {
  children: ReactNode;
  onClick: () => void;
  isLoading?: boolean;
  disabled?: boolean;
  variant?: Variant;
  className?: string;
}) {
  const { isConnected, chainId } = useAccount();
  const { openConnectModal } = useConnectModal();
  const { switchChain, isPending } = useSwitchChain();
  const target = useActiveChain().chain;

  if (!isConnected) {
    return (
      <Button
        app="fund"
        variant="primary"
        className={className}
        onClick={openConnectModal}
      >
        Connect wallet
      </Button>
    );
  }

  if (chainId !== target.id) {
    return (
      <Button
        app="fund"
        variant="primary"
        className={className}
        isLoading={isPending}
        onClick={() => switchChain({ chainId: target.id })}
      >
        Switch to {target.name}
      </Button>
    );
  }

  return (
    <Button
      app="fund"
      variant={variant}
      className={className}
      isLoading={isLoading}
      onClick={onClick}
      {...(disabled ? { disabled: true } : {})}
    >
      {children}
    </Button>
  );
}
