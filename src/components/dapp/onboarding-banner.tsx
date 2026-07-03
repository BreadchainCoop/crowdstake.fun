"use client";

import Link from "next/link";
import { useAccount } from "wagmi";
import { Body, Button } from "@breadcoop/ui";
import {
  ArrowRight,
  Confetti,
  HandCoins,
  Sparkle,
} from "@phosphor-icons/react";
import {
  useNativeBalance,
  useTokenBalance,
  useWrapped,
} from "@/hooks/use-token";
import { useVotingState } from "@/hooks/use-voting";
import { useActiveChain, useBaseAssetSymbol } from "@/hooks/use-chain";
import { cn } from "@/lib/utils";

type Nudge = {
  tone: "action" | "done";
  icon: typeof Sparkle;
  message: string;
  href?: string;
  cta?: string;
};

/**
 * A state-aware next-step nudge on the per-instance page: prompts the connected
 * user toward the one action that moves them forward (deposit → vote), and
 * confirms when they're all set for the cycle. Renders nothing until balances
 * load, or when disconnected (the page already shows a connect prompt).
 */
export function OnboardingBanner() {
  const { isConnected } = useAccount();
  const balance = useTokenBalance();
  const native = useNativeBalance();
  const wrapped = useWrapped();
  const { hasVoted } = useVotingState();
  const baseSym = useBaseAssetSymbol();
  const { chain, yieldKind } = useActiveChain();
  const chainName = chain.name;

  if (!isConnected) return null;
  const bal = balance.data;
  // The deposit asset is the native currency on native chains, but the wrapped
  // stablecoin (USDC) on stable chains — nudge off *that* balance, not gas.
  const baseBal = yieldKind === "stable" ? wrapped.balance : native.data?.value;
  if (bal === undefined) return null; // still loading — don't flash a wrong nudge

  let nudge: Nudge;
  if (bal === 0n) {
    nudge =
      baseBal && baseBal > 0n
        ? {
            tone: "action",
            icon: HandCoins,
            message: `Deposit ${baseSym} to start earning yield and get voting power.`,
            href: "/app/deposit",
            cta: "Deposit",
          }
        : {
            tone: "action",
            icon: Sparkle,
            message: `Add some ${baseSym} on ${chainName}, then deposit to join this instance.`,
          };
  } else if (!hasVoted) {
    nudge = {
      tone: "action",
      icon: Sparkle,
      message:
        "You're staked. Cast your vote to direct where this cycle's yield goes.",
      href: "/app/vote",
      cta: "Vote",
    };
  } else {
    nudge = {
      tone: "done",
      icon: Confetti,
      message:
        "You're all set — staked and voted this cycle. Thanks for baking!",
    };
  }

  const Icon = nudge.icon;
  return (
    <div
      className={cn(
        "mb-6 flex flex-wrap items-center gap-3 rounded-xl border px-4 py-3",
        nudge.tone === "done"
          ? "border-system-green/30 bg-system-green/5"
          : "border-core-orange/30 bg-core-orange/5",
      )}
    >
      <Icon
        size={22}
        weight="fill"
        className={cn(
          "flex-none",
          nudge.tone === "done" ? "text-system-green" : "text-core-orange",
        )}
      />
      <Body className="text-text-standard min-w-0 flex-1 text-sm">
        {nudge.message}
      </Body>
      {nudge.href && nudge.cta && (
        <Button
          app="fund"
          variant="primary"
          as={Link}
          href={nudge.href}
          rightIcon={<ArrowRight weight="bold" />}
        >
          {nudge.cta}
        </Button>
      )}
    </div>
  );
}
