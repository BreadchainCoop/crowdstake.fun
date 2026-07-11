"use client";

import { useEffect, useMemo, useState } from "react";
import { type Address } from "viem";
import { useAccount } from "wagmi";
import { Body, Caption } from "@breadcoop/ui";
import { CheckCircle, Plus, Minus } from "@phosphor-icons/react";
import {
  Card,
  EmptyState,
  PageHeader,
  ProgressBar,
} from "@/components/dapp/ui";
import { ActionButton } from "@/components/dapp/action-button";
import { GasModeNote } from "@/components/dapp/gas-mode-note";
import { TxStatus } from "@/components/dapp/tx-status";
import { useRecipients } from "@/hooks/use-recipients";
import { useVote, useVotingState } from "@/hooks/use-voting";
import { useCycle } from "@/hooks/use-cycle";
import { useFamily } from "@/hooks/use-family";
import { useCrossChainVote } from "@/hooks/use-cross-chain-vote";
import { shortenAddress } from "@/lib/format";
import { addressUrl, shortChainName } from "@/lib/chains";
import { useActiveChainId } from "@/components/instance-provider";
import { useAmountFormatter } from "@/components/demo-mode-provider";
import { FamilyVoteCard } from "./_components/family-vote-card";
import { FamilyExplainer } from "./_components/family-explainer";
import { MultiChainVoteStatus } from "./_components/multi-chain-vote-status";

export default function VotePage() {
  return (
    <div className="mx-auto max-w-2xl">
      <PageHeader
        title="Vote"
        subtitle="Allocate your voting power across recipients. Yield is distributed proportionally to the community's weighted votes each cycle."
      />
      <VoteGate />
    </div>
  );
}

/**
 * The vote page's mode is gated on the `familyId()` read: classic instances get
 * the single-chain flow (unchanged), multi-chain families get the sign-once
 * cross-chain flow. A skeleton renders until the read resolves so we never
 * flash the wrong UI.
 */
function VoteGate() {
  const family = useFamily();

  // familyId not yet known — show a skeleton rather than the wrong mode.
  if (family.familyId === null && family.isLoading) {
    return <VoteSkeleton />;
  }
  if (family.isFamily) {
    return <FamilyVoteForm family={family} />;
  }
  return <VoteForm />;
}

function VoteSkeleton() {
  return (
    <div className="animate-pulse space-y-4">
      <div className="bg-paper-1 h-20 rounded-2xl" />
      <div className="bg-paper-1 h-32 rounded-2xl" />
      <div className="bg-paper-1 h-32 rounded-2xl" />
    </div>
  );
}

/** Shared allocation grid used by both the classic and family forms. */
function AllocationGrid({
  recipients,
  distribution,
  weights,
  setWeight,
  maxStep,
  disabled,
  chainLabeled,
}: {
  recipients: readonly string[];
  distribution: readonly bigint[];
  weights: Record<string, number>;
  setWeight: (addr: string, v: number) => void;
  maxStep: number;
  disabled?: boolean;
  /** Family mode: bars are per-chain, so label "Current on <chain>". */
  chainLabeled?: boolean;
}) {
  const chainId = useActiveChainId();
  const currentLabel = chainLabeled
    ? `Current on ${shortChainName(chainId)}`
    : "Current";
  const totalVotes = useMemo(
    () => distribution.reduce((a, b) => a + b, 0n),
    [distribution],
  );
  const totalPts = recipients.reduce((s, r) => s + (weights[r] ?? 0), 0);

  return (
    <div className="space-y-4">
      {recipients.map((r, i) => {
        const current = distribution[i] ?? 0n;
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
                {currentLabel}: {share.toFixed(1)}%
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
                disabled={disabled}
                onChange={(v) =>
                  setWeight(r, Math.max(0, Math.min(maxStep, v)))
                }
              />
            </div>
          </Card>
        );
      })}
    </div>
  );
}

function VoteForm() {
  const fmt = useAmountFormatter();
  const { recipients } = useRecipients();
  const voting = useVotingState();
  const cycle = useCycle();
  const { vote, recast, supportsRecast, recastProbePending, ...tx } = useVote();

  // Per-recipient weight in *percent* (0..100); converted to basis points on submit.
  const [weights, setWeights] = useState<Record<string, number>>({});

  const setWeight = (addr: string, v: number) =>
    setWeights((w) => ({ ...w, [addr]: v }));

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

  // Recasting rides the EIP-712 signature path (castVoteWithSignature). On a
  // module that doesn't expose it (VOTE_TYPEHASH() reverts), the ballot stays
  // locked for the cycle, exactly like before.
  const probing = voting.hasVoted && recastProbePending;
  const locked = voting.hasVoted && !supportsRecast;

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
            {probing
              ? "You voted this cycle."
              : supportsRecast
                ? "You voted this cycle — you can update your ballot until it ends."
                : "You've already voted this cycle. New votes are accepted next cycle."}
          </p>
        )}
      </Card>

      <div className="mb-3 flex items-center justify-between">
        <Caption className="text-surface-grey-2">
          Allocate points — each recipient&apos;s share is relative
        </Caption>
        <button
          onClick={distributeEqually}
          disabled={locked}
          className="text-core-orange text-sm font-semibold hover:underline disabled:opacity-50"
        >
          Distribute equally
        </button>
      </div>

      <AllocationGrid
        recipients={recipients}
        distribution={voting.distribution}
        weights={weights}
        setWeight={setWeight}
        maxStep={maxStep}
        disabled={locked}
      />

      <div className="mt-6">
        <ActionButton
          isLoading={tx.isBusy}
          disabled={
            !anyAllocated || locked || probing || noPower || lengthMismatch
          }
          onClick={() => (voting.hasVoted ? recast(points) : vote(points))}
        >
          {probing || locked
            ? "Already voted this cycle"
            : voting.hasVoted
              ? "Update vote"
              : "Cast vote"}
        </ActionButton>
      </div>

      {!locked && noPower && (
        <Caption className="text-system-warning mt-2 block text-center">
          Your voting power is still accruing this cycle — try again shortly.
        </Caption>
      )}
      {!locked && !noPower && lengthMismatch && (
        <Caption className="text-system-warning mt-2 block text-center">
          The recipient list just changed — refresh before voting.
        </Caption>
      )}
      {!anyAllocated && !locked && !noPower && !lengthMismatch && (
        <Caption className="text-surface-grey mt-2 block text-center">
          Allocate weight to at least one recipient.
        </Caption>
      )}

      <TxStatus
        status={tx.status}
        hash={tx.hash}
        error={tx.error}
        successLabel={voting.hasVoted ? "Vote updated" : "Vote cast"}
      />

      <Body className="text-surface-grey mt-6 text-sm">
        Points are relative — each recipient&apos;s share is its points ÷ your
        total points, weighted by your voting power. Use the +/− steppers or
        type a value.
      </Body>
    </div>
  );
}

/**
 * Multi-chain family vote: ONE signature counts on every family chain, weighted
 * by the wallet's per-chain stake. Steppers are never locked by hasVoted (recast
 * is a first-class action), and delivery status is per chain.
 */
function FamilyVoteForm({ family }: { family: ReturnType<typeof useFamily> }) {
  const { address } = useAccount();
  const chainId = useActiveChainId();
  const { recipients } = useRecipients();
  const voting = useVotingState();
  const ccv = useCrossChainVote(family);

  const [weights, setWeights] = useState<Record<string, number>>({});
  const setWeight = (addr: string, v: number) =>
    setWeights((w) => ({ ...w, [addr]: v }));

  // On settle, refetch every chain's voting state so rows reflect the landing.
  useEffect(() => {
    if (ccv.phase === "done") family.refetch();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ccv.phase]);

  if (recipients.length === 0) {
    return (
      <EmptyState>
        No recipients have been added yet. An admin must add funding recipients
        before voting can begin.
      </EmptyState>
    );
  }

  const totalPts = recipients.reduce((s, r) => s + (weights[r] ?? 0), 0);
  const anyAllocated = totalPts > 0;
  // Points map to the ACTIVE chain's registry order; siblings re-map by identity.
  const points = recipients.map((r) => BigInt(weights[r] ?? 0));
  const recipientList = recipients as readonly Address[];
  const maxStep = Math.min(99, Number(voting.maxPoints));

  // The active chain's row tells us whether this is a fresh vote or a recast.
  const active = family.perChain.find((c) => c.chainId === chainId);
  const alreadyVoted = active?.hasVoted ?? false;

  // Names of the chains this ballot will actually target (found + has power).
  const targetChains = family.perChain
    .filter((c) => c.status === "found")
    .map((c) => shortChainName(c.chainId));
  const chainListText =
    targetChains.length <= 1
      ? (targetChains[0] ?? "this chain")
      : `${targetChains.slice(0, -1).join(", ")} and ${targetChains.at(-1)}`;

  const distributeEqually = () => {
    const w: Record<string, number> = {};
    recipients.forEach((r) => (w[r] = 1));
    setWeights(w);
  };

  return (
    <div>
      <FamilyExplainer />

      <FamilyVoteCard
        perChain={family.perChain}
        onRetry={() => family.refetch({ force: true })}
      />

      <div className="mb-3 flex items-center justify-between">
        <Caption className="text-surface-grey-2">
          Allocate points — each recipient&apos;s share is relative
        </Caption>
        <button
          onClick={distributeEqually}
          className="text-core-orange text-sm font-semibold hover:underline"
        >
          Distribute equally
        </button>
      </div>

      <AllocationGrid
        recipients={recipients}
        distribution={voting.distribution}
        weights={weights}
        setWeight={setWeight}
        maxStep={maxStep}
        chainLabeled
      />

      <div className="mt-6">
        <Caption className="text-surface-grey-2 mb-2 block text-center">
          One signature casts this vote on {chainListText} — anyone can deliver
          it; valid for 72 hours.
        </Caption>
        <ActionButton
          chainless
          isLoading={ccv.isBusy}
          disabled={!anyAllocated || !address}
          onClick={() => ccv.sign(points, recipientList)}
        >
          {alreadyVoted ? "Update vote" : "Cast vote"}
        </ActionButton>
        <div className="mt-2 text-center">
          <GasModeNote />
        </div>
      </div>

      {!anyAllocated && (
        <Caption className="text-surface-grey mt-2 block text-center">
          Allocate weight to at least one recipient.
        </Caption>
      )}
      {ccv.error && (
        <Caption className="text-system-red mt-2 block text-center">
          {ccv.error}
        </Caption>
      )}

      <MultiChainVoteStatus
        rows={ccv.rows}
        phase={ccv.phase}
        submitting={ccv.submitting}
        payload={ccv.payload}
        onSubmitOnChain={ccv.submitOnChain}
        onRetryFailed={ccv.retryFailed}
      />

      <Body className="text-surface-grey mt-6 text-sm">
        Results can differ per chain — voting power is per-chain stake. Your
        points are relative: each recipient&apos;s share is its points ÷ your
        total points.
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
