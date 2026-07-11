"use client";

import { formatEther } from "viem";
import {
  CheckCircle,
  Warning,
  SpinnerGap,
  MinusCircle,
  Circle,
} from "@phosphor-icons/react";
import { Button, Caption } from "@breadcoop/ui";
import { CHAINS, shortChainName, yieldFlavorLabel } from "@/lib/chains";
import { useWalletActions } from "@/components/wallet/wallet-actions";
import type { FamilyDeployRow } from "@/hooks/use-deploy-family";

function StateIcon({ state }: { state: FamilyDeployRow["state"] }) {
  switch (state) {
    case "deployed":
      return (
        <CheckCircle size={20} weight="fill" className="text-system-green" />
      );
    case "failed":
      return <Warning size={20} weight="fill" className="text-system-red" />;
    case "skipped":
      return <MinusCircle size={20} className="text-surface-grey" />;
    case "idle":
      return <Circle size={20} className="text-surface-grey" />;
    default:
      return (
        <SpinnerGap size={20} className="text-surface-grey-2 animate-spin" />
      );
  }
}

function stateText(state: FamilyDeployRow["state"]): string {
  switch (state) {
    case "checking":
      return "Checking…";
    case "signing":
      return "Confirm in your wallet…";
    case "confirming":
      return "Deploying…";
    case "deployed":
      return "Deployed";
    case "skipped":
      return "Skipped";
    case "failed":
      return "Failed";
    default:
      return "Not deployed";
  }
}

/**
 * Per-chain deploy checklist — independent Deploy / Retry / Skip per row (not a
 * rigid pipeline). Each row shows the chain's yield flavor, its cycle length in
 * blocks (from ONE duration), and a low-gas warning from a native-balance
 * preflight. On-chain discovery marks already-deployed chains ✓ before any tx.
 */
export function ChainChecklist({
  rows,
  cycleSeconds,
  busy,
  onDeploy,
  onSkip,
  onUnskip,
}: {
  rows: FamilyDeployRow[];
  cycleSeconds: number;
  busy: boolean;
  onDeploy: (chainId: number) => void;
  onSkip: (chainId: number) => void;
  onUnskip: (chainId: number) => void;
}) {
  // Sponsored (embedded) wallets deploy gaslessly — the native-balance
  // preflight warnings only apply to self-paying wallets.
  const { sponsored } = useWalletActions();
  return (
    <ul className="space-y-3">
      {rows.map((row) => {
        const cfg = CHAINS[row.chainId];
        const blocks = BigInt(
          Math.max(1, Math.ceil(cycleSeconds / (cfg?.blockTimeSeconds ?? 5))),
        );
        const lowGas =
          !sponsored && row.balanceWei !== undefined && row.balanceWei === 0n;
        const inFlight =
          row.state === "checking" ||
          row.state === "signing" ||
          row.state === "confirming";
        return (
          <li
            key={row.chainId}
            className="border-paper-2 flex items-start gap-3 rounded-xl border p-3"
          >
            <span className="mt-0.5 flex-none">
              <StateIcon state={row.state} />
            </span>
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-2">
                <span className="font-breadDisplay text-text-standard font-bold">
                  {shortChainName(row.chainId)}
                </span>
                <Caption className="text-surface-grey">
                  {yieldFlavorLabel(row.chainId)}
                </Caption>
              </div>
              <Caption className="text-surface-grey-2 mt-0.5 block">
                {stateText(row.state)} · ≈ {blocks.toString()} blocks (
                {cfg?.blockTimeSeconds ?? 5}s/block)
              </Caption>
              {row.state === "failed" && row.error && (
                <Caption className="text-system-red mt-0.5 block">
                  {row.error}
                </Caption>
              )}
              {lowGas &&
                row.state !== "deployed" &&
                row.state !== "skipped" && (
                  <Caption className="text-system-warning mt-0.5 block">
                    No {cfg?.chain.nativeCurrency.symbol} for gas on this chain
                    — fund the wallet before deploying.
                  </Caption>
                )}
              {!sponsored &&
                row.balanceWei !== undefined &&
                row.balanceWei > 0n &&
                row.state === "idle" && (
                  <Caption className="text-surface-grey mt-0.5 block">
                    {Number(formatEther(row.balanceWei)).toFixed(4)}{" "}
                    {cfg?.chain.nativeCurrency.symbol} available for gas.
                  </Caption>
                )}
            </div>

            {row.state !== "deployed" && (
              <div className="flex flex-none flex-col gap-1.5">
                <Button
                  app="fund"
                  variant="primary"
                  className="px-3 py-1 text-xs"
                  isLoading={inFlight}
                  onClick={() => onDeploy(row.chainId)}
                  {...(busy && !inFlight ? { disabled: true } : {})}
                >
                  {row.state === "failed"
                    ? "Retry"
                    : row.state === "skipped"
                      ? "Deploy"
                      : "Deploy"}
                </Button>
                {row.state === "skipped" ? (
                  <button
                    type="button"
                    onClick={() => onUnskip(row.chainId)}
                    className="text-surface-grey hover:text-text-standard text-xs"
                  >
                    Un-skip
                  </button>
                ) : (
                  !inFlight && (
                    <button
                      type="button"
                      onClick={() => onSkip(row.chainId)}
                      className="text-surface-grey hover:text-text-standard text-xs"
                    >
                      Skip
                    </button>
                  )
                )}
              </div>
            )}
          </li>
        );
      })}
    </ul>
  );
}
