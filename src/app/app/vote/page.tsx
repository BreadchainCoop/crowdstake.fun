"use client";

import { useEffect, useMemo, useState } from "react";
import { type Address } from "viem";
import { Body, Caption } from "@breadcoop/ui";
import { CheckCircle, Plus, Minus } from "@phosphor-icons/react";
import {
  Card,
  EmptyState,
  PageHeader,
  ProgressBar,
} from "@/components/dapp/ui";
import { ActionButton } from "@/components/dapp/action-button";
import { TxStatus } from "@/components/dapp/tx-status";
import { useRecipients } from "@/hooks/use-recipients";
import { useVote, useVotingState } from "@/hooks/use-voting";
import { useCycle } from "@/hooks/use-cycle";
import { shortenAddress } from "@/lib/format";
import { addressUrl } from "@/lib/chains";
import { useActiveChainId } from "@/components/instance-provider";
import { useAmountFormatter } from "@/components/demo-mode-provider";

export default function VotePage() {
  return (
    <div className="mx-auto max-w-2xl">
      <PageHeader
        title="Vote"
        subtitle="Allocate your voting power across recipients. Yield is distributed proportionally to the community's weighted votes each cycle."
      />
      <VoteForm />
    </div>
  );
}

function VoteForm() {
  const fmt = useAmountFormatter();
  const chainId = useActiveChainId();
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

  // Relative points per recipient: the module normalises by the voter's own
  // total, so a recipient's share is points[i] / sum(points).
  const totalPts = recipients.reduce((s, r) => s + (weights[r] ?? 0), 0);
  const anyAllocated = totalPts > 0;
  const points = recipients.map((r) => BigInt(weights[r] ?? 0));
  const maxStep = Math.min(99, Number(voting.maxPoints)); // per-recipient cap

  // Time-weighted voting power is 0 until it accrues within the cycle; voting
  // then "succeeds" but records nothing and locks you out — block it.
  const noPower = !voting.votingPower || voting.votingPower === 0n;
  // The contract requires points.length == recipient count; if the recipient
  // set changed under us, refuse rather than revert.
  const lengthMismatch =
    voting.expectedPointsLength !== undefined &&
    points.length !== Number(voting.expectedPointsLength);

  const distributeEqually = () => {
    const w: Record<string, number> = {};
    recipients.forEach((r) => (w[r] = 1));
    setWeights(w);
  };

  return (
    <div>
      <Card className="mb-6">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <Caption className="text-surface-grey-2">
            Cycle #{cycle.cycleNumber?.toString() ?? "—"} · your voting power
          </Caption>
          <span className="font-breadDisplay text-text-standard font-bold">
            {fmt(voting.votingPower)}
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

      <div className="mb-3 flex items-center justify-between">
        <Caption className="text-surface-grey-2">
          Allocate points — each recipient&apos;s share is relative
        </Caption>
        <button
          onClick={distributeEqually}
          disabled={voting.hasVoted}
          className="text-core-orange text-sm font-semibold hover:underline disabled:opacity-50"
        >
          Distribute equally
        </button>
      </div>

      <div className="space-y-4">
        {recipients.map((r, i) => {
          const current = voting.distribution[i] ?? 0n;
          const share =
            totalVotes > 0n ? Number((current * 10000n) / totalVotes) / 100 : 0;
          const pts = weights[r] ?? 0;
          const alloc = totalPts > 0 ? (pts / totalPts) * 100 : 0;
          return (
            <Card key={r}>
              <div className="flex items-center justify-between">
                <a
                  href={addressUrl(r, chainId)}
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
              <div className="mt-4 flex items-center justify-between gap-4">
                <span className="text-text-standard text-sm">
                  Your allocation:{" "}
                  <span className="font-breadDisplay text-core-orange font-bold">
                    {alloc.toFixed(0)}%
                  </span>
                </span>
                <Stepper
                  value={pts}
                  disabled={voting.hasVoted}
                  onChange={(v) =>
                    setWeight(r, Math.max(0, Math.min(maxStep, v)))
                  }
                />
              </div>
            </Card>
          );
        })}
      </div>

      <div className="mt-6">
        <ActionButton
          isLoading={tx.isBusy}
          disabled={
            !anyAllocated || voting.hasVoted || noPower || lengthMismatch
          }
          onClick={() => vote(points)}
        >
          {voting.hasVoted ? "Already voted this cycle" : "Cast vote"}
        </ActionButton>
      </div>

      {!voting.hasVoted && noPower && (
        <Caption className="text-system-warning mt-2 block text-center">
          Your voting power is still accruing this cycle — try again shortly.
        </Caption>
      )}
      {!voting.hasVoted && !noPower && lengthMismatch && (
        <Caption className="text-system-warning mt-2 block text-center">
          The recipient list just changed — refresh before voting.
        </Caption>
      )}
      {!anyAllocated && !voting.hasVoted && !noPower && !lengthMismatch && (
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
        Points are relative — each recipient&apos;s share is its points ÷ your
        total points, weighted by your voting power. Use the +/− steppers or
        type a value.
      </Body>
    </div>
  );
}

function Stepper({
  value,
  onChange,
  disabled,
}: {
  value: number;
  onChange: (v: number) => void;
  disabled?: boolean;
}) {
  const btn =
    "border-paper-2 text-text-standard hover:border-core-orange flex h-9 w-9 items-center justify-center rounded-lg border disabled:opacity-40";
  return (
    <div className="flex items-center gap-1.5">
      <button
        type="button"
        aria-label="Decrease"
        onClick={() => onChange(value - 1)}
        disabled={disabled || value <= 0}
        className={btn}
      >
        <Minus weight="bold" />
      </button>
      <input
        type="text"
        inputMode="numeric"
        value={value}
        disabled={disabled}
        onChange={(e) => {
          const n = parseInt(e.target.value.replace(/[^0-9]/g, ""), 10);
          onChange(Number.isNaN(n) ? 0 : n);
        }}
        className="border-paper-2 bg-paper-main text-text-standard w-12 rounded-lg border py-1.5 text-center font-bold outline-none disabled:opacity-50"
      />
      <button
        type="button"
        aria-label="Increase"
        onClick={() => onChange(value + 1)}
        disabled={disabled}
        className={btn}
      >
        <Plus weight="bold" />
      </button>
    </div>
  );
}
