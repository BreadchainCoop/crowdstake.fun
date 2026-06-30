"use client";

import { useEffect, useMemo } from "react";
import { Body, Button, Caption } from "@breadcoop/ui";
import { CheckCircle, XCircle } from "@phosphor-icons/react";
import { Card, PageHeader, StatCard } from "@/components/dapp/ui";
import { ConnectGate } from "@/components/dapp/connect-gate";
import { TxStatus } from "@/components/dapp/tx-status";
import { useDistribute, useDistributionReady } from "@/hooks/use-distribution";
import { useCycle } from "@/hooks/use-cycle";
import { useRecipients } from "@/hooks/use-recipients";
import { useVotingState } from "@/hooks/use-voting";
import { useTokenStats } from "@/hooks/use-token";
import { formatAmount } from "@/lib/format";
import { TOKEN_SYMBOL } from "@/lib/constants";

export default function DistributePage() {
  return (
    <div className="mx-auto max-w-2xl">
      <PageHeader
        title="Distribute"
        subtitle="Anyone can trigger a distribution once the cycle is ready. Accrued yield is split among recipients by their votes, and the cycle advances."
      />
      <ConnectGate>
        <Distribute />
      </ConnectGate>
    </div>
  );
}

function Distribute() {
  const { isReady, refetch: refetchReady } = useDistributionReady();
  const { distribute, ...tx } = useDistribute();
  const cycle = useCycle();
  const { recipients } = useRecipients();
  const voting = useVotingState();
  const { yieldAccrued } = useTokenStats();

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
        yieldAccrued !== undefined &&
        yieldAccrued >= BigInt(Math.max(1, recipients.length)),
    },
  ];

  useEffect(() => {
    if (tx.isSuccess) {
      refetchReady();
      cycle.refetch();
      voting.refetch();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tx.isSuccess]);

  return (
    <div>
      <div className="mb-6 grid gap-4 sm:grid-cols-2">
        <StatCard
          label="Accrued yield"
          value={`${formatAmount(yieldAccrued)} ${TOKEN_SYMBOL}`}
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

        <Button
          app="fund"
          variant="primary"
          className="mt-6 w-full"
          isLoading={tx.isBusy}
          onClick={() => distribute()}
          {...(!isReady ? { disabled: true } : {})}
        >
          {isReady ? "Claim & distribute" : "Not ready to distribute"}
        </Button>

        <TxStatus
          status={tx.status}
          hash={tx.hash}
          error={tx.error}
          successLabel="Distributed — cycle advanced"
        />
      </Card>

      <Body className="text-surface-grey mt-6 text-sm">
        Distribution claims the protocol&apos;s accrued sDAI yield as freshly
        minted {TOKEN_SYMBOL}, splits it across recipients proportionally to
        their votes, and starts a new cycle — all in one transaction.
      </Body>
    </div>
  );
}
