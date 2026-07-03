"use client";

import Link from "next/link";
import { useAccount } from "wagmi";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import { Body, Button, Caption, Heading4 } from "@breadcoop/ui";
import { ArrowRight, CheckCircle, Circle } from "@phosphor-icons/react";
import { Card, ProgressBar, StatCard } from "@/components/dapp/ui";
import { InstanceHeader } from "@/components/dapp/instance-header";
import { OnboardingBanner } from "@/components/dapp/onboarding-banner";
import {
  useTokenBalance,
  useVotes,
  useNativeBalance,
  useInstanceToken,
} from "@/hooks/use-token";
import { useCycle } from "@/hooks/use-cycle";
import { useDistributionReady } from "@/hooks/use-distribution";
import { useIsRecipient } from "@/hooks/use-recipients";
import { formatAmount, blocksToDuration } from "@/lib/format";
import { useAmountFormatter } from "@/components/demo-mode-provider";
import {
  useActiveChain,
  useBaseAssetSymbol,
  useNativeSymbol,
} from "@/hooks/use-chain";

export default function PortfolioPage() {
  const { isConnected } = useAccount();
  const balance = useTokenBalance();
  const votes = useVotes();
  const native = useNativeBalance();
  const cycle = useCycle();
  const { isReady } = useDistributionReady();
  const isRecipient = useIsRecipient();
  const { symbol: tokenSymbol } = useInstanceToken();
  const fmt = useAmountFormatter();
  const nativeSym = useNativeSymbol();
  const baseSym = useBaseAssetSymbol();
  const { blockTimeSeconds } = useActiveChain();

  return (
    <div>
      {/* Instance identity + live stats — this instance's own page. */}
      <InstanceHeader />

      {!isConnected && (
        <Card className="mb-8 flex flex-col items-center gap-3 py-8 text-center">
          <Body className="text-surface-grey-2">
            Connect your wallet to see your balance, voting power, and stake
            position.
          </Body>
          <ConnectButton />
        </Card>
      )}

      {isConnected && <OnboardingBanner />}

      {/* Your position */}
      <Heading4 className="text-text-standard">Your position</Heading4>
      <div className="mt-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <StatCard
          label={`Your ${tokenSymbol}`}
          value={`${fmt(balance.data)} ${tokenSymbol}`}
          sub={`Redeemable 1:1 for ${baseSym}`}
          accent
        />
        <StatCard
          label="Your voting power"
          value={fmt(votes.data)}
          sub="Delegated automatically on deposit"
        />
        <StatCard
          label={`Wallet ${nativeSym}`}
          value={`${formatAmount(native.data?.value)} ${nativeSym}`}
          sub="Available to deposit"
        />
      </div>

      {/* Cycle */}
      <Card className="mt-6">
        <div className="flex flex-wrap items-baseline justify-between gap-2">
          <Heading4 className="text-text-standard">
            Cycle #{cycle.cycleNumber?.toString() ?? "—"}
          </Heading4>
          <Caption className="text-surface-grey-2">
            {cycle.isComplete
              ? "Cycle complete — distribution can run"
              : `${blocksToDuration(cycle.blocksUntilNext, blockTimeSeconds)} left`}
          </Caption>
        </div>
        <div className="mt-3">
          <ProgressBar value={cycle.progress} />
        </div>
        <div className="mt-4 flex items-center gap-2">
          {isReady ? (
            <CheckCircle
              size={18}
              weight="fill"
              className="text-system-green"
            />
          ) : (
            <Circle size={18} className="text-surface-grey" />
          )}
          <Caption className="text-surface-grey-2">
            {isReady
              ? "Distribution is ready to run"
              : "Distribution not ready yet"}
          </Caption>
        </div>
      </Card>

      {isConnected && (
        <Caption className="text-surface-grey mt-4 block">
          {isRecipient.data
            ? "✓ You are an active funding recipient."
            : "You are not currently a funding recipient."}
        </Caption>
      )}

      {/* Quick actions */}
      <div className="mt-8 flex flex-wrap gap-3">
        <Button
          app="fund"
          variant="primary"
          as={Link}
          href="/app/deposit"
          rightIcon={<ArrowRight weight="bold" />}
        >
          Deposit
        </Button>
        <Button app="fund" variant="secondary" as={Link} href="/app/vote">
          Vote
        </Button>
        <Button app="fund" variant="secondary" as={Link} href="/app/distribute">
          Distribute
        </Button>
        <Button app="fund" variant="secondary" as={Link} href="/app/withdraw">
          Withdraw
        </Button>
      </div>
    </div>
  );
}
