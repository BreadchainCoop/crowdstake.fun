"use client";

import { useEffect, useState } from "react";
import { Caption } from "@breadcoop/ui";
import { Card, PageHeader } from "@/components/dapp/ui";
import { AmountField } from "@/components/dapp/amount-field";
import { ActionButton } from "@/components/dapp/action-button";
import { TxStatus } from "@/components/dapp/tx-status";
import { formatAmount, parseAmount } from "@/lib/format";
import { useActiveChain, useNativeSymbol } from "@/hooks/use-chain";
import {
  useInstanceToken,
  useTokenBalance,
  useWithdraw,
} from "@/hooks/use-token";

function useRedeemSymbol() {
  const nativeSym = useNativeSymbol();
  const { yieldKind, wrappedSymbol } = useActiveChain();
  // Native instances redeem to the native currency; stable ones to the stablecoin.
  return yieldKind === "stable" ? wrappedSymbol : nativeSym;
}

export default function WithdrawPage() {
  const { symbol } = useInstanceToken();
  const redeemSym = useRedeemSymbol();
  return (
    <div className="mx-auto max-w-lg">
      <PageHeader
        title="Withdraw"
        subtitle={`Burn ${symbol} to redeem your ${redeemSym} principal 1:1. Your stake is always fully withdrawable.`}
      />
      <WithdrawForm />
    </div>
  );
}

function WithdrawForm() {
  const [amount, setAmount] = useState("");
  const { symbol, decimals } = useInstanceToken();
  const redeemSym = useRedeemSymbol();
  const balance = useTokenBalance();
  const { withdraw, ...tx } = useWithdraw();

  const parsed = parseAmount(amount, decimals);
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
        label="Amount to withdraw"
        value={amount}
        onChange={setAmount}
        balance={balance.data}
        symbol={symbol}
        decimals={decimals}
      />

      <div className="bg-paper-1 mt-4 flex items-center justify-between rounded-xl px-4 py-3">
        <Caption className="text-surface-grey-2">You receive</Caption>
        <span className="font-breadDisplay text-text-standard font-bold">
          {parsed ? formatAmount(parsed, 4, decimals) : "0"} {redeemSym}
        </span>
      </div>

      {overBalance && (
        <Caption className="text-system-red mt-2 block">
          Amount exceeds your {symbol} balance.
        </Caption>
      )}

      <div className="mt-6">
        <ActionButton
          isLoading={tx.isBusy}
          disabled={disabled}
          onClick={() => parsed && withdraw(parsed)}
        >
          Withdraw to {redeemSym}
        </ActionButton>
      </div>

      <TxStatus
        status={tx.status}
        hash={tx.hash}
        error={tx.error}
        successLabel="Withdrawal confirmed"
      />
    </Card>
  );
}
