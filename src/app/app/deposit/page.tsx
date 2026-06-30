"use client";

import { useEffect, useState } from "react";
import { Body, Button, Caption } from "@breadcoop/ui";
import { Card, PageHeader } from "@/components/dapp/ui";
import { ConnectGate } from "@/components/dapp/connect-gate";
import { AmountField } from "@/components/dapp/amount-field";
import { TxStatus } from "@/components/dapp/tx-status";
import { cn } from "@/lib/utils";
import { formatAmount, parseAmount } from "@/lib/format";
import { TOKEN_SYMBOL } from "@/lib/constants";
import {
  useApproveWxdai,
  useDeposit,
  useNativeBalance,
  useTokenBalance,
  useWxdai,
} from "@/hooks/use-token";

export default function DepositPage() {
  return (
    <div className="mx-auto max-w-lg">
      <PageHeader
        title="Deposit"
        subtitle={`Stake xDAI to mint ${TOKEN_SYMBOL} 1:1. Your principal stays fully withdrawable — only the interest is distributed.`}
      />
      <ConnectGate>
        <DepositForm />
      </ConnectGate>
    </div>
  );
}

function DepositForm() {
  const [mode, setMode] = useState<"native" | "wxdai">("native");
  const [amount, setAmount] = useState("");

  const native = useNativeBalance();
  const wxdai = useWxdai();
  const stake = useTokenBalance();
  const { deposit, ...depositTx } = useDeposit();
  const { approve, ...approveTx } = useApproveWxdai();

  const parsed = parseAmount(amount);
  const balance = mode === "native" ? native.data?.value : wxdai.balance;
  const overBalance =
    parsed !== null && balance !== undefined && parsed > balance;
  const needsApproval =
    mode === "wxdai" && parsed !== null && (wxdai.allowance ?? 0n) < parsed;

  // Refresh balances after a confirmed deposit.
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
      {/* Source toggle */}
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
          {parsed ? formatAmount(parsed) : "0"} {TOKEN_SYMBOL}
        </span>
      </div>

      {overBalance && (
        <Caption className="text-system-red mt-2 block">
          Amount exceeds your balance.
        </Caption>
      )}

      <div className="mt-6">
        {needsApproval ? (
          <Button
            app="fund"
            variant="primary"
            className="w-full"
            isLoading={approveTx.isBusy}
            onClick={() => parsed && approve(parsed)}
          >
            Approve WXDAI
          </Button>
        ) : (
          <Button
            app="fund"
            variant="primary"
            className="w-full"
            isLoading={depositTx.isBusy}
            onClick={() => parsed && deposit({ amount: parsed, mode })}
            withBorder={false}
            {...(disabled ? { disabled: true } : {})}
          >
            Deposit
          </Button>
        )}
      </div>

      <TxStatus
        status={
          approveTx.status === "idle" ? depositTx.status : approveTx.status
        }
        hash={approveTx.hash ?? depositTx.hash}
        error={depositTx.error ?? approveTx.error}
        successLabel={depositTx.isSuccess ? "Deposit confirmed" : "Approved"}
      />

      <Body className="text-surface-grey mt-6 text-sm">
        Your {TOKEN_SYMBOL} balance:{" "}
        <span className="text-text-standard font-semibold">
          {formatAmount(stake.data)} {TOKEN_SYMBOL}
        </span>
      </Body>
    </Card>
  );
}
