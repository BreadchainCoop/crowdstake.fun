"use client";

import { ArrowSquareOut, CheckCircle } from "@phosphor-icons/react";
import { Button, Caption } from "@breadcoop/ui";
import { Card } from "@/components/dapp/ui";
import { ActionButton } from "@/components/dapp/action-button";
import { shortChainName, txUrl } from "@/lib/chains";
import { useActiveChainId } from "@/components/instance-provider";
import { useAmountFormatter18 } from "@/components/demo-mode-provider";
import { GasModeNote } from "@/components/dapp/gas-mode-note";
import { useInstanceToken } from "@/hooks/use-token";
import {
  useFamilyDistribute,
  type FamilyDistributeRow,
} from "@/hooks/use-family-distribute";
import type { FamilyState } from "@/hooks/use-family";

/**
 * The family's per-chain distribution checklist — yield accrues and distributes
 * independently on every chain, so each row shows that chain's pot, cycle, and
 * readiness with its own Distribute button (a public keeper action).
 */
export function FamilyDistributeCard({ family }: { family: FamilyState }) {
  const activeChainId = useActiveChainId();
  const { rows, distributeOn, distributeAll, anyBusy } =
    useFamilyDistribute(family);
  // Only rows the contract itself reports ready — the walk re-checks each one.
  const readyCount = rows.filter((r) => r.isReady === true).length;

  if (rows.length === 0) return null;

  return (
    <Card className="mb-6">
      <Caption className="text-surface-grey-2 block">
        Your community across chains — yield accrues and distributes per chain
      </Caption>
      <div className="mt-3">
        {/* chainless: the walk targets each chain itself, so no
            switch-to-active-chain gating — only connect gating. */}
        <ActionButton
          chainless
          isLoading={anyBusy}
          disabled={readyCount === 0 || anyBusy}
          onClick={() => void distributeAll()}
        >
          Distribute on all ready chains
        </ActionButton>
      </div>
      <div className="mt-1">
        <GasModeNote />
      </div>
      <ul className="mt-3 space-y-3">
        {rows.map((r) => (
          <ChainRow
            key={r.chainId}
            row={r}
            isActive={r.chainId === activeChainId}
            onDistribute={() => void distributeOn(r.chainId)}
          />
        ))}
      </ul>
    </Card>
  );
}

function ChainRow({
  row,
  isActive,
  onDistribute,
}: {
  row: FamilyDistributeRow;
  isActive: boolean;
  onDistribute: () => void;
}) {
  const fmt18 = useAmountFormatter18();
  const { symbol } = useInstanceToken();
  const busy = row.state === "distributing" || row.state === "confirming";

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
          {row.isReady && (
            <span className="bg-system-green/10 text-system-green rounded-full px-2 py-0.5 text-xs font-semibold">
              ready
            </span>
          )}
        </div>

        {row.unreachable ? (
          <Caption className="text-system-warning mt-0.5 block">
            couldn&apos;t reach chain
          </Caption>
        ) : (
          <Caption className="text-surface-grey-2 mt-0.5 block">
            {fmt18(row.accrued18)} {symbol} accrued · cycle #
            {row.cycleNumber?.toString() ?? "—"}
            {row.isReady === false &&
              (row.isComplete ? " · complete, not ready" : " · in progress")}
          </Caption>
        )}

        {row.state === "done" && (
          <Caption className="text-system-green mt-1 flex items-center gap-1">
            <CheckCircle size={13} weight="fill" /> distributed — cycle advanced
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
          <Caption className="text-system-red mt-1 block">{row.error}</Caption>
        )}
      </div>

      <Button
        app="fund"
        variant="secondary"
        size="sm"
        className="flex-none"
        isLoading={busy}
        onClick={onDistribute}
        {...(!row.isReady && !busy ? { disabled: true } : {})}
      >
        {row.state === "failed" ? "Retry" : "Distribute"}
      </Button>
    </li>
  );
}
