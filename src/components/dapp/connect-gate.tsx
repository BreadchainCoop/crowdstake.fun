"use client";

import type { ReactNode } from "react";
import { useAccount, useSwitchChain } from "wagmi";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import { Body, Button, Heading4 } from "@breadcoop/ui";
import { CHAIN, CHAIN_ID } from "@/lib/constants";
import { Card } from "@/components/dapp/ui";

/**
 * Wraps interactive content: prompts to connect when disconnected, and to
 * switch to Gnosis when on the wrong chain. Otherwise renders children.
 */
export function ConnectGate({ children }: { children: ReactNode }) {
  const { isConnected, chainId } = useAccount();
  const { switchChain, isPending } = useSwitchChain();

  if (!isConnected) {
    return (
      <Card className="flex flex-col items-center gap-4 py-10 text-center">
        <Heading4 className="text-text-standard">Connect your wallet</Heading4>
        <Body className="text-surface-grey-2 max-w-sm">
          Connect a wallet on Gnosis Chain to deposit, vote, and manage the
          protocol.
        </Body>
        <ConnectButton />
      </Card>
    );
  }

  if (chainId !== CHAIN_ID) {
    return (
      <Card className="flex flex-col items-center gap-4 py-10 text-center">
        <Heading4 className="text-text-standard">Wrong network</Heading4>
        <Body className="text-surface-grey-2 max-w-sm">
          This app runs on {CHAIN.name}. Switch networks to continue.
        </Body>
        <Button
          app="fund"
          variant="primary"
          isLoading={isPending}
          onClick={() => switchChain({ chainId: CHAIN_ID })}
        >
          Switch to {CHAIN.name}
        </Button>
      </Card>
    );
  }

  return <>{children}</>;
}
