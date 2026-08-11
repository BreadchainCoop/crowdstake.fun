"use client";

import Link from "next/link";
import { useAccount } from "wagmi";
import { Body, Button, Caption, Heading4 } from "@breadcoop/ui";
import { WalletButton } from "@/components/dapp/wallet-button";
import { ArrowRight, CheckCircle, Circle } from "@phosphor-icons/react";
import { Card, ProgressBar, StatCard } from "@/components/dapp/ui";
import { InstanceHeader } from "@/components/dapp/instance-header";
import { OnboardingBanner } from "@/components/dapp/onboarding-banner";
import {
  useTokenBalance,
  useNativeBalance,
  useInstanceToken,
  useYieldSplit,
} from "@/hooks/use-token";
import { useCurrentVotingPower } from "@/hooks/use-voting";
import { useFamily } from "@/hooks/use-family";
import {
  scaleTo18,
  useFamilyPosition,
  useFamilyStats,
} from "@/hooks/use-family-stats";
import { useApy } from "@/hooks/use-apy";
import { useInstanceKind } from "@/hooks/use-instance-kind";
import { useVoteCount } from "@/hooks/use-vote-count";
import { shortChainName } from "@/lib/chains";
import { useCycle } from "@/hooks/use-cycle";
import { useDistributionReady } from "@/hooks/use-distribution";
import { useIsRecipient } from "@/hooks/use-recipients";
import { formatAmount, blocksToDuration } from "@/lib/format";
import {
  useAmountFormatter,
  useAmountFormatter18,
} from "@/components/demo-mode-provider";
import {
  useActiveChain,
  useBaseAssetSymbol,
  useNativeSymbol,
} from "@/hooks/use-chain";

export default function PortfolioPage() {
  const { isConnected } = useAccount();
  const balance = useTokenBalance();
  const votingPower = useCurrentVotingPower();
  const native = useNativeBalance();
  const cycle = useCycle();
  const { isReady } = useDistributionReady();
  const isRecipient = useIsRecipient();
  const { symbol: tokenSymbol } = useInstanceToken();
  // Pool instances issue no token: the position is just "your deposit"
  // (symbol() is the underlying asset's, so amounts still read naturally).
  const { isPool } = useInstanceKind();
  const fmt = useAmountFormatter();
  const fmt18 = useAmountFormatter18();
  const nativeSym = useNativeSymbol();
  const baseSym = useBaseAssetSymbol();
  const { blockTimeSeconds } = useActiveChain();

  // Families: your position is your holdings on EVERY chain, not just the one
  // being viewed (a member usually minted on several).
  const family = useFamily();
  const fpos = useFamilyPosition(family);
  const familyMode = family.isFamily && fpos.balance18 !== undefined;
  const heldChains = fpos.perChain.filter((c) => c.balance18 > 0n);
  const balanceBreakdown =
    familyMode && heldChains.length > 0
      ? heldChains
          .map((c) => `${fmt18(c.balance18)} on ${shortChainName(c.chainId)}`)
          .join(" · ")
      : null;

  // Personal stats (crowdstaking-v2's profile numbers, multichain):
  // projected annual donation = holdings × APY × the share of yield you give.
  const fstats = useFamilyStats(family);
  const apy = useApy(
    family.isFamily
      ? {
          familyId: family.familyId,
          ratePerMs: fstats.ratePerMs,
          totalStaked18: fstats.totalStaked18,
        }
      : undefined,
  );
  const { keepBps, supported: splitSupported } = useYieldSplit();
  const { decimals } = useInstanceToken();
  // Tokens without split support donate all yield; with support, give what's
  // not kept. The ACTIVE chain's split stands in for all chains on families.
  const giveShare =
    splitSupported === false || keepBps === undefined
      ? 1
      : (10_000 - keepBps) / 10_000;
  const holdings18 = familyMode
    ? fpos.balance18
    : balance.data !== undefined
      ? scaleTo18(balance.data, decimals)
      : undefined;
  const donation18 =
    holdings18 !== undefined && apy !== undefined
      ? (holdings18 * BigInt(Math.round(apy * giveShare * 100))) / 10_000n
      : undefined;
  const voteCount = useVoteCount(family);

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
          <WalletButton />
        </Card>
      )}

      {isConnected && <OnboardingBanner />}

      {/* Your position */}
      <Heading4 className="text-text-standard">Your position</Heading4>
      <div className="mt-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <StatCard
          label={
            isPool
              ? familyMode
                ? "Your deposit · all chains"
                : "Your deposit"
              : familyMode
                ? `Your ${tokenSymbol} · all chains`
                : `Your ${tokenSymbol}`
          }
          value={
            familyMode
              ? // A family's cross-chain sum mixes each chain's underlying
                // (WXDAI, USDC, …), so for a POOL the ticker suffix would be
                // dishonest — drop it (family-deposit does the same for its
                // summed total). Single-chain and token families keep it.
                `${fmt18(fpos.balance18)}${isPool ? "" : ` ${tokenSymbol}`}`
              : `${fmt(balance.data)} ${tokenSymbol}`
          }
          sub={
            balanceBreakdown ??
            // A pool deposit IS the base asset — nothing to redeem it for.
            (isPool ? "Withdrawable any time" : `Redeemable 1:1 for ${baseSym}`)
          }
          accent
        />
        <StatCard
          label={
            familyMode ? "Your voting power · all chains" : "Your voting power"
          }
          value={
            familyMode ? fmt18(fpos.votes18) : fmt(votingPower.data)
          }
          sub="Strategy weight used on the Vote page"
        />
        <StatCard
          label={`Wallet ${nativeSym}`}
          value={`${formatAmount(native.data?.value)} ${nativeSym}`}
          sub="Available to deposit"
        />
        <StatCard
          label="Projected annual donation"
          value={
            donation18 !== undefined
              ? `${fmt18(donation18)} ${tokenSymbol}`
              : "—"
          }
          sub={
            apy !== undefined
              ? `At ≈ ${apy.toFixed(1)}% APY · your current yield split`
              : "Measuring APY…"
          }
        />
        <StatCard
          label="Votes cast"
          value={
            voteCount.count !== undefined
              ? `${voteCount.partial ? "≈ " : ""}${voteCount.count}`
              : voteCount.isLoading
                ? "…"
                : "—"
          }
          sub={
            familyMode
              ? "Signed ballots · all chains · recent window"
              : "From recent on-chain votes"
          }
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
        <Button app="fund" variant="secondary" as={Link} href="/app/yield">
          Yield split
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
