"use client";

import { useEffect, useMemo, useState } from "react";
import { type Address } from "viem";
import { Body, Button, Caption } from "@breadcoop/ui";
import { CheckCircle } from "@phosphor-icons/react";
import {
  Card,
  EmptyState,
  PageHeader,
  ProgressBar,
} from "@/components/dapp/ui";
import { ConnectGate } from "@/components/dapp/connect-gate";
import { TxStatus } from "@/components/dapp/tx-status";
import { useRecipients } from "@/hooks/use-recipients";
import { useVote, useVotingState } from "@/hooks/use-voting";
import { useCycle } from "@/hooks/use-cycle";
import { formatAmount, shortenAddress } from "@/lib/format";
import { MAX_POINTS, addressUrl } from "@/lib/constants";

export default function VotePage() {
  return (
    <div className="mx-auto max-w-2xl">
      <PageHeader
        title="Vote"
        subtitle="Allocate your voting power across recipients. Yield is distributed proportionally to the community's weighted votes each cycle."
      />
      <ConnectGate>
        <VoteForm />
      </ConnectGate>
    </div>
  );
}

function VoteForm() {
  const { recipients } = useRecipients();
  const voting = useVotingState();
  const cycle = useCycle();
  const { vote, ...tx } = useVote();

  // Per-recipient weight in *percent* (0..100); converted to basis points on submit.
  const [weights, setWeights] = useState<Record<string, number>>({});

  const setWeight = (addr: string, v: number) =>
    setWeights((w) => ({ ...w, [addr]: v }));

  const totalVotes = useMemo(
    () => voting.distribution.reduce((a, b) => a + b, 0n),
    [voting.distribution],
  );

  useEffect(() => {
    if (tx.isSuccess) voting.refetch();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tx.isSuccess]);

  if (recipients.length === 0) {
    return (
      <EmptyState>
        No recipients have been added yet. An admin must add funding recipients
        before voting can begin.
      </EmptyState>
    );
  }

  const anyAllocated = recipients.some((r) => (weights[r] ?? 0) > 0);
  const points = recipients.map((r) =>
    BigInt(Math.round((weights[r] ?? 0) * 100)),
  ); // % → basis points

  return (
    <div>
      <Card className="mb-6">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <Caption className="text-surface-grey-2">
            Cycle #{cycle.cycleNumber?.toString() ?? "—"} · your voting power
          </Caption>
          <span className="font-breadDisplay text-text-standard font-bold">
            {formatAmount(voting.votingPower)}
          </span>
        </div>
        {voting.hasVoted && (
          <p className="text-system-green mt-3 flex items-center gap-2 text-sm font-medium">
            <CheckCircle size={18} weight="fill" />
            You&apos;ve already voted this cycle. New votes are accepted next
            cycle.
          </p>
        )}
      </Card>

      <div className="space-y-4">
        {recipients.map((r, i) => {
          const current = voting.distribution[i] ?? 0n;
          const share =
            totalVotes > 0n ? Number((current * 10000n) / totalVotes) / 100 : 0;
          const weight = weights[r] ?? 0;
          return (
            <Card key={r}>
              <div className="flex items-center justify-between">
                <a
                  href={addressUrl(r)}
                  target="_blank"
                  rel="noreferrer"
                  className="font-breadDisplay text-text-standard hover:text-core-orange font-bold"
                >
                  {shortenAddress(r as Address, 6)}
                </a>
                <Caption className="text-surface-grey-2">
                  Current: {share.toFixed(1)}%
                </Caption>
              </div>
              <div className="mt-2">
                <ProgressBar value={share / 100} />
              </div>
              <div className="mt-4 flex items-center gap-4">
                <input
                  type="range"
                  min={0}
                  max={100}
                  step={1}
                  value={weight}
                  onChange={(e) => setWeight(r, Number(e.target.value))}
                  disabled={voting.hasVoted}
                  className="bg-paper-2 accent-core-orange h-2 w-full cursor-pointer appearance-none rounded-full disabled:opacity-50"
                />
                <span className="font-breadDisplay text-core-orange w-14 text-right font-bold">
                  {weight}%
                </span>
              </div>
            </Card>
          );
        })}
      </div>

      <Button
        app="fund"
        variant="primary"
        className="mt-6 w-full"
        isLoading={tx.isBusy}
        onClick={() => vote(points)}
        {...(!anyAllocated || voting.hasVoted ? { disabled: true } : {})}
      >
        {voting.hasVoted ? "Already voted this cycle" : "Cast vote"}
      </Button>

      {!anyAllocated && !voting.hasVoted && (
        <Caption className="text-surface-grey mt-2 block text-center">
          Allocate weight to at least one recipient.
        </Caption>
      )}

      <TxStatus
        status={tx.status}
        hash={tx.hash}
        error={tx.error}
        successLabel="Vote cast"
      />

      <Body className="text-surface-grey mt-6 text-sm">
        Weights are relative — each recipient&apos;s share of the next
        distribution is proportional to its total weighted votes (your weight ×
        your voting power, summed across all voters). Max {MAX_POINTS / 100n}%
        per recipient.
      </Body>
    </div>
  );
}
