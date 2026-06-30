"use client";

import { useEffect, useMemo } from "react";
import { Body, Caption } from "@breadcoop/ui";
import { CheckCircle, XCircle } from "@phosphor-icons/react";
import { Card, PageHeader, StatCard } from "@/components/dapp/ui";
import { ActionButton } from "@/components/dapp/action-button";
import { TxStatus } from "@/components/dapp/tx-status";
import { useDistribute, useDistributionReady } from "@/hooks/use-distribution";
import { useCycle } from "@/hooks/use-cycle";
import { useRecipients } from "@/hooks/use-recipients";
import { useVotingState } from "@/hooks/use-voting";
import { useInstanceToken, useTokenStats } from "@/hooks/use-token";
import { formatAmount } from "@/lib/format";

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

  const totalVotes = useMemo(
    () => voting.distribution.reduce((a, b) => a + b, 0n),
    [voting.distribution],
  );

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
          value={`${formatAmount(yieldAccrued)} ${symbol}`}
          sub="To be distributed"
          accent
        />
        <StatCard
          label="Cycle"
          value={`#${cycle.cycleNumber?.toString() ?? "—"}`}
          sub={cycle.isComplete ? "Complete" : "In progress"}
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
        Distribution claims the protocol&apos;s accrued sDAI yield as freshly
        minted {symbol}, splits it across recipients proportionally to their
        votes, and starts a new cycle — all in one transaction.
      </Body>
    </div>
  );
}
