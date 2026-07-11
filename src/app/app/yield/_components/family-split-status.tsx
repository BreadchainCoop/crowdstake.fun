"use client";

import { ArrowSquareOut, CheckCircle, Warning } from "@phosphor-icons/react";
import { Button, Caption } from "@breadcoop/ui";
import { shortChainName, txUrl } from "@/lib/chains";
import { useActiveChainId } from "@/components/instance-provider";
import { GasModeNote } from "@/components/dapp/gas-mode-note";
import type { FamilySplitRow } from "@/hooks/use-family-yield-split";

/**
 * Per-chain status list for the family yield-split fan-out: each sibling chain
 * shows its current split, whether it already matches the picked target (those
 * are skipped by the fan-out), unsupported/unreachable states, and an
 * independent Retry for failed chains.
 */
export function FamilySplitStatus({
  rows,
  targetKeepBps,
  onRetry,
}: {
  rows: FamilySplitRow[];
  targetKeepBps: number;
  onRetry: (chainId: number) => void;
}) {
  const activeChainId = useActiveChainId();
  if (rows.length === 0) return null;
  return (
    <div className="mt-5">
      <Caption className="text-surface-grey-2 block">
        Applies on every chain this community lives on
      </Caption>
      <div className="mt-1">
        <GasModeNote />
      </div>
      <ul className="mt-3 space-y-3">
        {rows.map((r) => (
          <ChainRow
            key={r.chainId}
            row={r}
            isActive={r.chainId === activeChainId}
            atTarget={r.keepBps !== undefined && r.keepBps === targetKeepBps}
            onRetry={() => onRetry(r.chainId)}
          />
        ))}
      </ul>
    </div>
  );
}

function ChainRow({
  row,
  isActive,
  atTarget,
  onRetry,
}: {
  row: FamilySplitRow;
  isActive: boolean;
  atTarget: boolean;
  onRetry: () => void;
}) {
  const busy = row.state === "setting" || row.state === "confirming";
  return (
    <li className="border-paper-2 flex items-start justify-between gap-3 border-t pt-3 first:border-t-0 first:pt-0">
      <div className="min-w-0">
        <div className="flex items-center gap-2">
          <span className="font-breadDisplay text-text-standard font-bold">
            {shortChainName(row.chainId)}
          </span>
          {isActive && (
            <Caption className="text-surface-grey">this chain</Caption>
          )}
          {row.supported !== false && !row.unreachable && atTarget && (
            <span className="bg-system-green/10 text-system-green rounded-full px-2 py-0.5 text-xs font-semibold">
              already set
            </span>
          )}
        </div>

        {row.unreachable ? (
          <Caption className="text-system-warning mt-0.5 block">
            couldn&apos;t reach chain
          </Caption>
        ) : row.supported === false ? (
          // The token there predates yield splits — the fan-out skips it.
          <Caption className="text-surface-grey-2 mt-0.5 block">
            not supported on this chain — its token predates splits
          </Caption>
        ) : (
          <Caption className="text-surface-grey-2 mt-0.5 block">
            {row.keepBps !== undefined
              ? `currently gives ${100 - row.keepBps / 100}% · keeps ${row.keepBps / 100}%`
              : "connect to see your current split"}
          </Caption>
        )}

        {busy && (
          <Caption className="text-surface-grey-2 mt-1 block">
            {row.state === "setting" ? "submitting…" : "confirming…"}
          </Caption>
        )}
        {row.state === "done" && (
          <Caption className="text-system-green mt-1 flex items-center gap-1">
            <CheckCircle size={13} weight="fill" /> split updated
            {row.txHash && (
              <a
                href={txUrl(row.txHash, row.chainId)}
                target="_blank"
                rel="noreferrer"
                className="text-core-orange inline-flex items-center gap-0.5 hover:underline"
              >
                View <ArrowSquareOut size={11} />
              </a>
            )}
          </Caption>
        )}
        {row.state === "failed" && row.error && (
          <Caption className="text-system-red mt-1 flex items-center gap-1">
            <Warning size={12} weight="fill" /> {row.error}
          </Caption>
        )}
      </div>

      {row.state === "failed" && (
        <Button
          app="fund"
          variant="secondary"
          size="sm"
          className="flex-none"
          isLoading={busy}
          onClick={onRetry}
        >
          Retry
        </Button>
      )}
    </li>
  );
}
