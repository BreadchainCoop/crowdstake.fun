"use client";

import { useState } from "react";
import { Body, Button, Caption } from "@breadcoop/ui";
import {
  ArrowSquareOut,
  CaretDown,
  Globe,
  Warning,
} from "@phosphor-icons/react";
import { Card, EmptyState, PageHeader, StatCard } from "@/components/dapp/ui";
import {
  useDistributionHistory,
  type EnrichedRound,
  type RecipientSummary,
} from "@/hooks/use-distribution-history";
import { addressUrl, shortChainName, txUrl } from "@/lib/chains";
import { toDecimal } from "@/lib/distribution-history";
import { formatAmount, formatPercent, shortenAddress } from "@/lib/format";
import { useInstanceToken } from "@/hooks/use-token";

/** ~decimal number → grouped string (family total across stablecoin chains). */
function fmtNum(n: number, frac = 2): string {
  return n.toLocaleString("en-US", { maximumFractionDigits: frac });
}

function fmtDate(ts: number): string {
  if (!ts) return "—";
  return new Date(ts * 1000).toLocaleDateString("en-US", {
    year: "numeric",
    month: "short",
    day: "numeric",
  });
}

export default function HistoryPage() {
  const { history, isLoading, error, loadOlder } = useDistributionHistory();
  const { symbol: tokenSymbol } = useInstanceToken();

  const hasData = history && history.roundCount > 0;

  return (
    <div>
      <PageHeader
        title={`${tokenSymbol} distribution history`}
        subtitle="Every yield payout, aggregated across all the chains this community lives on."
      />

      {isLoading && !history && (
        <Card>
          <Body className="text-surface-grey-2">
            Reading distributions from each chain…
          </Body>
        </Card>
      )}

      {error && !history && (
        <Card>
          <Body className="text-system-red">
            Couldn&apos;t load history: {error}
          </Body>
        </Card>
      )}

      {/* Partial data: one or more chains couldn't be read, so totals undercount. */}
      {history && history.failedChains.length > 0 && (
        <Card className="border-system-warning/40 bg-system-warning/5 mb-6">
          <Caption className="text-system-warning flex items-center gap-1.5">
            <Warning size={14} weight="fill" />
            Partial history — couldn&apos;t read{" "}
            {history.failedChains.map((c) => shortChainName(c)).join(", ")}.
            Totals below exclude{" "}
            {history.failedChains.length === 1 ? "it" : "them"}; try again
            shortly.
          </Caption>
        </Card>
      )}

      {history &&
        !hasData &&
        !isLoading &&
        history.failedChains.length === 0 && (
          <EmptyState>
            No yield has been distributed yet. Once a cycle completes and
            someone runs distribution, it will show up here.
          </EmptyState>
        )}

      {hasData && (
        <>
          {/* Summary */}
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <StatCard
              label="Total distributed"
              value={`≈ ${fmtNum(history.totalNormalized)}`}
              sub={
                history.isFamily
                  ? `across ${history.chains.length} chains`
                  : shortChainName(history.chains[0]?.chainId)
              }
              accent
            />
            <StatCard label="Payout rounds" value={history.roundCount} />
            <StatCard label="Recipients paid" value={history.recipientCount} />
            <StatCard
              label="Chains"
              value={history.chains.length}
              sub={history.isFamily ? "one community, many chains" : undefined}
            />
          </div>

          {/* Per-chain breakdown */}
          {history.isFamily && history.chains.length > 1 && (
            <Card className="mt-6">
              <Caption className="text-surface-grey-2 flex items-center gap-1.5">
                <Globe size={14} weight="fill" className="text-core-orange" />
                By chain
              </Caption>
              <ul className="mt-3 space-y-3">
                {history.chains.map((c) => {
                  const pct = history.totalNormalized
                    ? c.normalized / history.totalNormalized
                    : 0;
                  return (
                    <li key={c.chainId}>
                      <div className="flex items-baseline justify-between text-sm">
                        <span className="text-text-standard font-medium">
                          {shortChainName(c.chainId)}
                        </span>
                        <span className="text-surface-grey-2">
                          {formatAmount(c.total, 2, c.decimals)} {c.symbol}
                          <span className="text-surface-grey ml-2">
                            {c.rounds} round{c.rounds === 1 ? "" : "s"}
                          </span>
                        </span>
                      </div>
                      <div className="bg-paper-2 mt-1.5 h-2 w-full overflow-hidden rounded-full">
                        <div
                          className="bg-core-orange h-full rounded-full"
                          style={{ width: `${Math.max(2, pct * 100)}%` }}
                        />
                      </div>
                    </li>
                  );
                })}
              </ul>
            </Card>
          )}

          {/* Recipient leaderboard */}
          <Card className="mt-6">
            <Caption className="text-surface-grey-2">
              Recipients (all-time)
            </Caption>
            <ul className="mt-3 space-y-3">
              {history.recipients.slice(0, 12).map((r) => (
                <RecipientRow
                  key={r.recipient}
                  r={r}
                  isFamily={history.isFamily}
                />
              ))}
            </ul>
          </Card>

          {/* Timeline */}
          <Caption className="text-surface-grey-2 mt-8 mb-3 block">
            Payout timeline
          </Caption>
          <div className="space-y-2">
            {history.rounds.map((round) => (
              <RoundRow
                key={`${round.chainId}-${round.txHash}`}
                round={round}
                allTimeNormalized={history.totalNormalized}
              />
            ))}
          </div>

          <div className="mt-6 flex items-center gap-3">
            <Button
              app="fund"
              variant="secondary"
              isLoading={isLoading}
              onClick={() => loadOlder()}
            >
              Load older history
            </Button>
            <Caption className="text-surface-grey">
              History is read live from each chain — older payouts may take a
              moment to load.
            </Caption>
          </div>
        </>
      )}
    </div>
  );
}

function RecipientRow({
  r,
  isFamily,
}: {
  r: RecipientSummary;
  isFamily: boolean;
}) {
  return (
    <li className="flex items-start justify-between gap-3">
      <a
        href={addressUrl(r.recipient, r.perChain[0]?.chainId)}
        target="_blank"
        rel="noreferrer"
        className="text-text-standard hover:text-core-orange font-mono text-sm"
      >
        {shortenAddress(r.recipient)}
      </a>
      <div className="text-right">
        <span className="text-text-standard text-sm font-semibold">
          ≈ {fmtNum(r.normalized)}
        </span>
        {isFamily && r.perChain.length > 0 && (
          <div className="text-surface-grey mt-0.5 text-xs">
            {r.perChain
              .map(
                (pc) =>
                  `${formatAmount(pc.amount, 2, pc.decimals)} ${pc.symbol} on ${shortChainName(
                    pc.chainId,
                  )}`,
              )
              .join(" · ")}
          </div>
        )}
      </div>
    </li>
  );
}

function RoundRow({
  round,
  allTimeNormalized,
}: {
  round: EnrichedRound;
  allTimeNormalized: number;
}) {
  const [open, setOpen] = useState(false);
  const panelId = `round-${round.chainId}-${round.txHash}`;
  // This round's weight in everything ever distributed (normalized — rounds on
  // 6-dp chains compare fairly against 18-dp ones).
  const shareOfAllTime =
    allTimeNormalized > 0
      ? toDecimal(round.total, round.decimals) / allTimeNormalized
      : 0;
  return (
    <Card className="!p-0">
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        aria-expanded={open}
        aria-controls={panelId}
        className="flex w-full items-center justify-between gap-3 px-5 py-3.5 text-left"
      >
        <div className="min-w-0">
          <div className="text-text-standard text-sm font-semibold">
            {formatAmount(round.total, 2, round.decimals)} {round.symbol}
          </div>
          <div className="text-surface-grey text-xs">
            {fmtDate(round.timestamp)} · {shortChainName(round.chainId)} ·{" "}
            {round.recipients.length} recipient
            {round.recipients.length === 1 ? "" : "s"} ·{" "}
            {formatPercent(shareOfAllTime)} of everything distributed
          </div>
        </div>
        <CaretDown
          size={16}
          className={`text-surface-grey transition-transform ${open ? "rotate-180" : ""}`}
        />
      </button>
      {open && (
        <div id={panelId} className="border-paper-2 border-t px-5 py-3">
          <ul className="space-y-2.5">
            {round.recipients.map((x) => {
              // Exact bigint ratio (4-dp) — Number() on raw wei loses precision.
              const share =
                round.total > 0n
                  ? Number((x.amount * 10_000n) / round.total) / 10_000
                  : 0;
              return (
                <li key={x.recipient} className="text-sm">
                  <div className="flex items-center justify-between gap-3">
                    <a
                      href={addressUrl(x.recipient, round.chainId)}
                      target="_blank"
                      rel="noreferrer"
                      className="text-surface-grey-2 hover:text-core-orange font-mono text-xs"
                    >
                      {shortenAddress(x.recipient)}
                    </a>
                    <span className="text-text-standard">
                      {formatAmount(x.amount, 4, round.decimals)} {round.symbol}
                      <span className="text-surface-grey ml-2 text-xs tabular-nums">
                        {formatPercent(share)}
                      </span>
                    </span>
                  </div>
                  {/* Share of this round — same hand-rolled bar as "By chain". */}
                  <div className="bg-paper-2 mt-1 h-1.5 w-full overflow-hidden rounded-full">
                    <div
                      className="bg-core-orange h-full rounded-full"
                      style={{ width: `${Math.max(1, share * 100)}%` }}
                    />
                  </div>
                </li>
              );
            })}
          </ul>
          <a
            href={txUrl(round.txHash, round.chainId)}
            target="_blank"
            rel="noreferrer"
            className="text-core-orange mt-3 inline-flex items-center gap-1 text-xs font-semibold hover:underline"
          >
            View transaction <ArrowSquareOut size={12} />
          </a>
        </div>
      )}
    </Card>
  );
}
