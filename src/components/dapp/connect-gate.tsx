"use client";

import type { ReactNode } from "react";
import { useAccount, useSwitchChain } from "wagmi";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import { Body, Button, Heading4 } from "@breadcoop/ui";
import { useActiveChain } from "@/hooks/use-chain";
import { Card } from "@/components/dapp/ui";

/**
 * Wraps interactive content: prompts to connect when disconnected, and to
 * switch to the active instance's chain when on the wrong one.
 */
export function ConnectGate({ children }: { children: ReactNode }) {
  const { isConnected, chainId } = useAccount();
  const { switchChain, isPending } = useSwitchChain();
  const target = useActiveChain().chain;

  if (!isConnected) {
    return (
      <Card className="flex flex-col items-center gap-4 py-10 text-center">
        <Heading4 className="text-text-standard">Connect your wallet</Heading4>
        <Body className="text-surface-grey-2 max-w-sm">
          Connect a wallet on {target.name} to deposit, vote, and manage the
          protocol.
        </Body>
        <ConnectButton />
      </Card>
    );
  }

  if (chainId !== target.id) {
    return (
      <Card className="flex flex-col items-center gap-4 py-10 text-center">
        <Heading4 className="text-text-standard">Wrong network</Heading4>
        <Body className="text-surface-grey-2 max-w-sm">
          This instance runs on {target.name}. Switch networks to continue.
        </Body>
        <Button
          app="fund"
          variant="primary"
          isLoading={isPending}
          onClick={() => switchChain({ chainId: target.id })}
        >
          Switch to {target.name}
        </Button>
      </Card>
    );
  }

  return <>{children}</>;
}
