"use client";

import { useEffect, useState } from "react";
import { Button, Caption } from "@breadcoop/ui";
import { Card, PageHeader } from "@/components/dapp/ui";
import { ConnectGate } from "@/components/dapp/connect-gate";
import { AmountField } from "@/components/dapp/amount-field";
import { TxStatus } from "@/components/dapp/tx-status";
import { formatAmount, parseAmount } from "@/lib/format";
import { TOKEN_SYMBOL } from "@/lib/constants";
import { useTokenBalance, useWithdraw } from "@/hooks/use-token";

export default function WithdrawPage() {
  return (
    <div className="mx-auto max-w-lg">
      <PageHeader
        title="Withdraw"
        subtitle={`Burn ${TOKEN_SYMBOL} to redeem your xDAI principal 1:1. Your stake is always fully withdrawable.`}
      />
      <ConnectGate>
        <WithdrawForm />
      </ConnectGate>
    </div>
  );
}

function WithdrawForm() {
  const [amount, setAmount] = useState("");
  const balance = useTokenBalance();
  const { withdraw, ...tx } = useWithdraw();

  const parsed = parseAmount(amount);
  const overBalance =
    parsed !== null && balance.data !== undefined && parsed > balance.data;
  const disabled = parsed === null || parsed === 0n || overBalance;

  useEffect(() => {
    if (tx.isSuccess) {
      void balance.refetch();
      setAmount("");
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tx.isSuccess]);

  return (
    <Card>
      <AmountField
        label={`Amount to withdraw`}
        value={amount}
        onChange={setAmount}
        balance={balance.data}
        symbol={TOKEN_SYMBOL}
      />

      <div className="bg-paper-1 mt-4 flex items-center justify-between rounded-xl px-4 py-3">
        <Caption className="text-surface-grey-2">You receive</Caption>
        <span className="font-breadDisplay text-text-standard font-bold">
          {parsed ? formatAmount(parsed) : "0"} xDAI
        </span>
      </div>

      {overBalance && (
        <Caption className="text-system-red mt-2 block">
          Amount exceeds your {TOKEN_SYMBOL} balance.
        </Caption>
      )}

      <Button
        app="fund"
        variant="primary"
        className="mt-6 w-full"
        isLoading={tx.isBusy}
        onClick={() => parsed && withdraw(parsed)}
        {...(disabled ? { disabled: true } : {})}
      >
        Withdraw to xDAI
      </Button>

      <TxStatus
        status={tx.status}
        hash={tx.hash}
        error={tx.error}
        successLabel="Withdrawal confirmed"
      />
    </Card>
  );
}
