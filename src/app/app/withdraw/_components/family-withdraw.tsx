"use client";

import { useEffect, useState } from "react";
import { formatUnits } from "viem";
import { useAccount } from "wagmi";
import {
  ArrowSquareOut,
  CheckCircle,
  Globe,
  Warning,
} from "@phosphor-icons/react";
import { Body, Button, Caption } from "@breadcoop/ui";
import { Card } from "@/components/dapp/ui";
import { GasModeNote } from "@/components/dapp/gas-mode-note";
import { formatAmount, parseAmount } from "@/lib/format";
import { shortChainName, txUrl } from "@/lib/chains";
import { useActiveChainId } from "@/components/instance-provider";
import { useWalletActions } from "@/components/wallet/wallet-actions";
import { useInstanceToken } from "@/hooks/use-token";
import {
  useFamilyWithdraw,
  type FamilyWithdrawRow,
} from "@/hooks/use-family-withdraw";
import type { FamilyState } from "@/hooks/use-family";

/**
 * Family-wide withdraw: the token lives independently on every sibling chain,
 * so redeeming the full position means one burn per chain. One row per chain
 * with the wallet's LOCAL balance there and its own amount + Withdraw button —
 * no network switching needed (the wallet layer targets each chain).
 */
export function FamilyWithdraw({ family }: { family: FamilyState }) {
  const activeChainId = useActiveChainId();
  const { isConnected } = useAccount();
  const { connect } = useWalletActions();
  const { symbol } = useInstanceToken();
  const { rows, withdrawOn } = useFamilyWithdraw(family);
  // Per-chain amount inputs, parsed with THAT chain's token decimals.
  const [amounts, setAmounts] = useState<Record<number, string>>({});

  // Clear a row's input once its withdrawal lands (the state machine passes
  // through "withdrawing" between runs, so each completion clears once).
  const doneKey = rows
    .filter((r) => r.state === "done")
    .map((r) => r.chainId)
    .join(",");
  useEffect(() => {
    if (!doneKey) return;
    const done = new Set(doneKey.split(",").map(Number));
    setAmounts((prev) => {
      const next = { ...prev };
      for (const id of done) delete next[id];
      return next;
    });
  }, [doneKey]);

  if (rows.length === 0) {
    return (
      <Card>
        <Body className="text-surface-grey-2">
          Reading the community&apos;s chains…
        </Body>
      </Card>
    );
  }

  return (
    <Card>
      <Caption className="text-surface-grey-2 flex items-center gap-1.5">
        <Globe size={14} weight="fill" className="text-core-orange" />
        Withdraw {symbol} across your chains
      </Caption>
      <div className="mt-1">
        <GasModeNote />
      </div>

      <ul className="mt-4 space-y-4">
        {rows.map((r) => (
          <ChainRow
            key={r.chainId}
            row={r}
            symbol={symbol}
            isActive={r.chainId === activeChainId}
            amount={amounts[r.chainId] ?? ""}
            onAmount={(v) =>
              setAmounts((prev) => ({ ...prev, [r.chainId]: v }))
            }
            onWithdraw={(raw) => void withdrawOn(r.chainId, raw)}
          />
        ))}
      </ul>

      {!isConnected && (
        <div className="mt-5">
          <Button
            app="fund"
            variant="primary"
            className="w-full"
            onClick={connect}
          >
            Connect wallet
          </Button>
        </div>
      )}

      <Body className="text-surface-grey mt-6 text-sm">
        Each withdrawal burns {symbol} on that chain and sends you its base
        asset 1:1. Your principal is always fully withdrawable.
      </Body>
    </Card>
  );
}

function ChainRow({
  row,
  symbol,
  isActive,
  amount,
  onAmount,
  onWithdraw,
}: {
  row: FamilyWithdrawRow;
  symbol: string;
  isActive: boolean;
  amount: string;
  onAmount: (v: string) => void;
  onWithdraw: (raw: bigint) => void;
}) {
  const { isConnected } = useAccount();
  const busy = row.state === "withdrawing" || row.state === "confirming";
  // Parse with THIS chain's decimals (6-dp USDC mirrors vs 18-dp native).
  const parsed =
    row.decimals !== undefined ? parseAmount(amount, row.decimals) : null;
  const over =
    parsed !== null && row.balance !== undefined && parsed > row.balance;
  const disabled =
    !isConnected ||
    busy ||
    parsed === null ||
    parsed === 0n ||
    row.balance === undefined ||
    over;

  return (
    <li className="border-paper-2 border-t pt-4 first:border-t-0 first:pt-0">
      <div className="flex items-center gap-2">
        <span className="font-breadDisplay text-text-standard font-bold">
          {shortChainName(row.chainId)}
        </span>
        {isActive && (
          <Caption className="text-surface-grey">this chain</Caption>
        )}
      </div>

      <div className="mt-2 flex items-center gap-2">
        <div className="border-paper-2 bg-paper-main focus-within:border-core-orange flex flex-1 items-center gap-2 rounded-xl border px-3 py-2">
          <input
            inputMode="decimal"
            placeholder="0.0"
            value={amount}
            onChange={(e) => onAmount(e.target.value)}
            className="font-breadDisplay text-text-standard placeholder:text-surface-grey w-full bg-transparent text-lg font-bold outline-none"
          />
          <span className="text-surface-grey-2 text-sm font-bold">
            {symbol}
          </span>
        </div>
        <button
          type="button"
          onClick={() => {
            // MAX = the full local balance, in this chain's own decimals.
            if (row.balance !== undefined && row.decimals !== undefined) {
              onAmount(formatUnits(row.balance, row.decimals));
            }
          }}
          className="text-core-orange text-xs font-semibold hover:underline"
        >
          MAX
        </button>
        <Button
          app="fund"
          variant="secondary"
          size="sm"
          className="flex-none"
          isLoading={busy}
          onClick={() => parsed && onWithdraw(parsed)}
          {...(disabled && !busy ? { disabled: true } : {})}
        >
          {row.state === "failed" ? "Retry" : "Withdraw"}
        </Button>
      </div>

      <div className="mt-1 flex items-center justify-between">
        {row.unreachable ? (
          <Caption className="text-system-warning">
            couldn&apos;t reach chain
          </Caption>
        ) : (
          <Caption className="text-surface-grey">
            Balance:{" "}
            {row.balance !== undefined && row.decimals !== undefined
              ? `${formatAmount(row.balance, 4, row.decimals)} ${symbol}`
              : "—"}
          </Caption>
        )}
        {over && <Caption className="text-system-red">Exceeds balance</Caption>}
        {!over &&
          parsed !== null &&
          parsed > 0n &&
          row.decimals !== undefined && (
            <Caption className="text-surface-grey-2">
              → {formatAmount(parsed, 4, row.decimals)} {row.redeemSymbol}
            </Caption>
          )}
      </div>

      {row.state === "done" && (
        <Caption className="text-system-green mt-1 flex items-center gap-1">
          <CheckCircle size={13} weight="fill" /> withdrawn
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
    </li>
  );
}
