"use client";

import { useEffect, useMemo } from "react";
import { Body, Caption, Heading4 } from "@breadcoop/ui";
import { CheckCircle, XCircle } from "@phosphor-icons/react";
import { Card, PageHeader, StatCard } from "@/components/dapp/ui";
import { ActionButton } from "@/components/dapp/action-button";
import { TxStatus } from "@/components/dapp/tx-status";
import { useDistribute, useDistributionReady } from "@/hooks/use-distribution";
import { useCycle } from "@/hooks/use-cycle";
import { useRecipients } from "@/hooks/use-recipients";
import { useVotingState } from "@/hooks/use-voting";
import { useInstanceToken, useTokenStats } from "@/hooks/use-token";
import { useLiveYieldDetails } from "@/hooks/use-live-yield";
import { useApy } from "@/hooks/use-apy";
import { useActiveChain } from "@/hooks/use-chain";
import { useAmountFormatter } from "@/components/demo-mode-provider";
import { ProgressBar } from "@/components/dapp/ui";
import { LiveYield } from "@/components/dapp/live-yield";

export default function DistributePage() {
  return (
    <div className="mx-auto max-w-2xl">
      <PageHeader
        title="Distribute"
        subtitle="Anyone can trigger a distribution once the cycle is ready. Accrued yield is split among recipients by their votes, and the cycle advances."
      />
      <Distribute />
    </div>
  );
}

function Distribute() {
  const { isReady, refetch: refetchReady } = useDistributionReady();
  const { distribute, ...tx } = useDistribute();
  const cycle = useCycle();
  const { recipients } = useRecipients();
  const voting = useVotingState();
  const tokenStats = useTokenStats();
  const { yieldAccrued } = tokenStats;
  const { symbol } = useInstanceToken();
  const { live, ratePerMs } = useLiveYieldDetails();
  const apy = useApy();
  const { blockTimeSeconds } = useActiveChain();
  const fmt = useAmountFormatter();

  const totalVotes = useMemo(
    () => voting.distribution.reduce((a, b) => a + b, 0n),
    [voting.distribution],
  );

  // Projected pot at cycle end: current accrual + measured rate × time left
  // (crowdstaking-v2's "Est. after 30 days", generalized to any cycle length).
  const projected = useMemo(() => {
    if (live === undefined) return undefined;
    if (cycle.isComplete || ratePerMs <= 0) return live;
    const remainingMs = Number(cycle.blocksUntilNext) * blockTimeSeconds * 1000;
    return live + BigInt(Math.floor(ratePerMs * remainingMs));
  }, [
    live,
    ratePerMs,
    cycle.isComplete,
    cycle.blocksUntilNext,
    blockTimeSeconds,
  ]);

  const checks = [
    { label: "Cycle complete", ok: cycle.isComplete },
    { label: "At least one recipient", ok: recipients.length > 0 },
    { label: "Votes have been cast this cycle", ok: totalVotes > 0n },
    {
      label: "Yield has accrued",
      ok:
        yieldAccrued !== undefined && yieldAccrued >= BigInt(recipients.length),
    },
  ];
  // All shown gates green but the contract still says not-ready means the
  // instance is mis-wired (cycle module not pointing at this manager).
  const wiringIssue = !isReady && checks.every((c) => c.ok);

  useEffect(() => {
    if (tx.isSuccess) {
      refetchReady();
      cycle.refetch();
      voting.refetch();
      tokenStats.refetch();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tx.isSuccess]);

  return (
    <div>
      <div className="mb-6 grid gap-4 sm:grid-cols-2">
        <StatCard
          label="Accrued yield"
          value={<LiveYield symbol={symbol} />}
          sub="To be distributed"
          accent
        />
        <StatCard
          label="Projected at cycle end"
          value={`${fmt(projected)} ${symbol}`}
          sub={
            apy !== undefined
              ? `≈ ${apy.toFixed(1)}% APY, measured live`
              : "Measuring accrual rate…"
          }
        />
        {/* Not a StatCard: its `sub` renders inside a <p>, where the progress
            bar's <div> would be invalid HTML (hydration error on load). */}
        <Card>
          <Caption className="text-surface-grey-2">Cycle</Caption>
          <Heading4 className="text-text-standard mt-2">
            #{cycle.cycleNumber?.toString() ?? "—"}
          </Heading4>
          <div className="mt-2">
            <ProgressBar value={cycle.isComplete ? 1 : cycle.progress} />
          </div>
          <Caption className="text-surface-grey mt-1 block">
            {cycle.isComplete
              ? "Complete — distribution can run"
              : `${Math.round(cycle.progress * 100)}% elapsed`}
          </Caption>
        </Card>
        <StatCard
          label="Recipients"
          value={recipients.length}
          sub="Will share this round"
        />
      </div>

      <Card>
        <Caption className="text-surface-grey-2">Readiness</Caption>
        <ul className="mt-3 space-y-2">
          {checks.map((c) => (
            <li key={c.label} className="flex items-center gap-2">
              {c.ok ? (
                <CheckCircle
                  size={18}
                  weight="fill"
                  className="text-system-green"
                />
              ) : (
                <XCircle
                  size={18}
                  weight="fill"
                  className="text-surface-grey"
                />
              )}
              <Body
                className={c.ok ? "text-text-standard" : "text-surface-grey-2"}
              >
                {c.label}
              </Body>
            </li>
          ))}
        </ul>

        {wiringIssue && (
          <Caption className="text-system-warning mt-3 block">
            All checks pass but the protocol still reports not ready — this
            instance may be mis-wired (its cycle module isn&apos;t pointed at
            this distribution manager).
          </Caption>
        )}

        <div className="mt-6">
          <ActionButton
            isLoading={tx.isBusy}
            disabled={!isReady}
            onClick={() => distribute()}
          >
            {isReady ? "Claim & distribute" : "Not ready to distribute"}
          </ActionButton>
        </div>

        <TxStatus
          status={tx.status}
          hash={tx.hash}
          error={tx.error}
          successLabel="Distributed — cycle advanced"
        />
      </Card>

      <Body className="text-surface-grey mt-6 text-sm">
        Distribution claims the protocol&apos;s accrued yield as freshly minted{" "}
        {symbol}, splits it across recipients proportionally to their votes, and
        starts a new cycle — all in one transaction.
      </Body>
    </div>
  );
}
