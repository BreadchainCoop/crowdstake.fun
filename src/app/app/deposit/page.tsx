"use client";

import { useEffect, useState } from "react";
import { Body, Caption } from "@breadcoop/ui";
import { Card, PageHeader } from "@/components/dapp/ui";
import { AmountField } from "@/components/dapp/amount-field";
import { ActionButton } from "@/components/dapp/action-button";
import { TxStatus } from "@/components/dapp/tx-status";
import { cn } from "@/lib/utils";
import { formatAmount, parseAmount } from "@/lib/format";
import {
  useApproveWxdai,
  useDeposit,
  useInstanceToken,
  useNativeBalance,
  useTokenBalance,
  useWxdai,
} from "@/hooks/use-token";

export default function DepositPage() {
  const { symbol } = useInstanceToken();
  return (
    <div className="mx-auto max-w-lg">
      <PageHeader
        title="Deposit"
        subtitle={`Stake xDAI to mint ${symbol} 1:1. Your principal stays fully withdrawable — only the interest is distributed.`}
      />
      <DepositForm />
    </div>
  );
}

function DepositForm() {
  const [mode, setMode] = useState<"native" | "wxdai">("native");
  const [amount, setAmount] = useState("");

  const { symbol } = useInstanceToken();
  const native = useNativeBalance();
  const wxdai = useWxdai();
  const stake = useTokenBalance();
  const { deposit, ...depositTx } = useDeposit();
  const { approve, ...approveTx } = useApproveWxdai();

  const parsed = parseAmount(amount);
  // Native deposits pay gas in xDAI too, so reserve a little for gas — otherwise
  // a MAX deposit sends the whole balance as value and can't fund the tx.
  const GAS_RESERVE = 10n ** 16n; // ~0.01 xDAI
  const rawBalance = mode === "native" ? native.data?.value : wxdai.balance;
  const balance =
    mode === "native" && rawBalance !== undefined
      ? rawBalance > GAS_RESERVE
        ? rawBalance - GAS_RESERVE
        : 0n
      : rawBalance;
  const overBalance =
    parsed !== null && balance !== undefined && parsed > balance;
  const needsApproval =
    mode === "wxdai" && parsed !== null && (wxdai.allowance ?? 0n) < parsed;

  useEffect(() => {
    if (depositTx.isSuccess) {
      void native.refetch();
      wxdai.refetch();
      void stake.refetch();
      setAmount("");
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [depositTx.isSuccess]);

  useEffect(() => {
    if (approveTx.isSuccess) wxdai.refetch();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [approveTx.isSuccess]);

  const disabled = parsed === null || parsed === 0n || overBalance;

  return (
    <Card>
      <div className="border-paper-2 mb-5 inline-flex rounded-xl border p-1">
        {(["native", "wxdai"] as const).map((m) => (
          <button
            key={m}
            onClick={() => setMode(m)}
            className={cn(
              "rounded-lg px-4 py-1.5 text-sm font-semibold transition-colors",
              mode === m
                ? "bg-core-orange text-white"
                : "text-surface-grey-2 hover:text-text-standard",
            )}
          >
            {m === "native" ? "xDAI (native)" : "WXDAI"}
          </button>
        ))}
      </div>

      <AmountField
        label="Amount to deposit"
        value={amount}
        onChange={setAmount}
        balance={balance}
        symbol={mode === "native" ? "xDAI" : "WXDAI"}
      />

      <div className="bg-paper-1 mt-4 flex items-center justify-between rounded-xl px-4 py-3">
        <Caption className="text-surface-grey-2">You receive</Caption>
        <span className="font-breadDisplay text-text-standard font-bold">
          {parsed ? formatAmount(parsed) : "0"} {symbol}
        </span>
      </div>

      {overBalance && (
        <Caption className="text-system-red mt-2 block">
          Amount exceeds your balance.
        </Caption>
      )}

      <div className="mt-6">
        <ActionButton
          isLoading={needsApproval ? approveTx.isBusy : depositTx.isBusy}
          disabled={disabled}
          onClick={() => {
            if (!parsed) return;
            if (needsApproval) approve(parsed);
            else deposit({ amount: parsed, mode });
          }}
        >
          {needsApproval ? "Approve WXDAI" : "Deposit"}
        </ActionButton>
      </div>

      <TxStatus
        status={needsApproval ? approveTx.status : depositTx.status}
        hash={needsApproval ? approveTx.hash : depositTx.hash}
        error={needsApproval ? approveTx.error : depositTx.error}
        successLabel={needsApproval ? "Approved" : "Deposit confirmed"}
      />

      <Body className="text-surface-grey mt-6 text-sm">
        Your {symbol} balance:{" "}
        <span className="text-text-standard font-semibold">
          {formatAmount(stake.data)} {symbol}
        </span>
      </Body>
    </Card>
  );
}
