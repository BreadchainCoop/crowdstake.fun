"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useAccount } from "wagmi";
import { Body, Caption } from "@breadcoop/ui";
import { Card, GateSkeleton, PageHeader } from "@/components/dapp/ui";
import { AmountField } from "@/components/dapp/amount-field";
import { ActionButton } from "@/components/dapp/action-button";
import { TxStatus } from "@/components/dapp/tx-status";
import { cn } from "@/lib/utils";
import { parseAmount } from "@/lib/format";
import { useWalletActions } from "@/components/wallet/wallet-actions";
import { useAmountFormatter } from "@/components/demo-mode-provider";
import { useActiveChain, useNativeSymbol } from "@/hooks/use-chain";
import { useFamily } from "@/hooks/use-family";
import { useInstanceKind } from "@/hooks/use-instance-kind";
import { FamilyDeposit } from "@/app/app/deposit/_components/family-deposit";
import {
  useApproveWrapped,
  useDeposit,
  useInstanceToken,
  useNativeBalance,
  useTokenBalance,
  useWrapped,
  useYieldSplit,
} from "@/hooks/use-token";

export default function DepositPage() {
  const { symbol } = useInstanceToken();
  // Pool mode: nothing is minted — a deposit is just a deposit.
  const { isPool } = useInstanceKind();
  const native = useNativeSymbol();
  const { yieldKind, wrappedSymbol } = useActiveChain();
  const family = useFamily();
  const depositSym = yieldKind === "stable" ? wrappedSymbol : native;
  const isFamily = family.isFamily && !family.isLoading;
  // familyId not yet known — don't render (and then swap) the wrong mode.
  const resolving = family.familyId === null && family.isLoading;

  return (
    <div className="mx-auto max-w-lg">
      <PageHeader
        title="Deposit"
        subtitle={
          isPool
            ? isFamily
              ? "Deposit across the chains this community lives on — whatever you hold on each. Your principal stays withdrawable; only the interest is distributed."
              : `Deposit ${depositSym} — your principal stays fully withdrawable, only the interest is distributed.`
            : resolving
              ? `Deposit to mint ${symbol} 1:1. Your principal stays fully withdrawable — only the interest is distributed.`
              : isFamily
                ? `Mint ${symbol} across the chains this community lives on — deposit whatever you hold on each. Your principal stays withdrawable; only the interest is distributed.`
                : `Stake ${depositSym} to mint ${symbol} 1:1. Your principal stays fully withdrawable — only the interest is distributed.`
        }
      />
      {resolving ? (
        <GateSkeleton />
      ) : isFamily ? (
        <>
          <FamilyDeposit family={family} tokenSymbol={symbol} />
          <details className="mt-4">
            <summary className="text-surface-grey-2 hover:text-text-standard cursor-pointer text-sm font-medium">
              Or deposit on just this chain
            </summary>
            <div className="mt-3">
              <DepositForm />
            </div>
          </details>
        </>
      ) : (
        <DepositForm />
      )}
    </div>
  );
}

function DepositForm() {
  const { yieldKind, wrappedToken, wrappedSymbol } = useActiveChain();
  const isStable = yieldKind === "stable";
  // Stable instances deposit an ERC-20 stablecoin (USDC); there is no native
  // path. Native instances offer native + wrapped.
  const [mode, setMode] = useState<"native" | "wrapped">(
    isStable ? "wrapped" : "native",
  );
  const [amount, setAmount] = useState("");

  const { symbol, decimals } = useInstanceToken();
  // Pool mode: no token arrives — hide the "You receive" framing entirely.
  const { isPool } = useInstanceKind();
  const nativeSym = useNativeSymbol();
  const hasWrapped = Boolean(wrappedToken);
  // The native toggle only makes sense when the instance accepts native.
  const showModeToggle = hasWrapped && !isStable;
  const fmt = useAmountFormatter();
  const native = useNativeBalance();
  const wrapped = useWrapped();
  const stake = useTokenBalance();
  const { deposit, ...depositTx } = useDeposit();
  const { approve, ...approveTx } = useApproveWrapped();

  // Native is always 18-dp; the wrapped/stable asset uses the token's decimals.
  const depositDecimals = mode === "native" ? 18 : decimals;
  const parsed = parseAmount(amount, depositDecimals);
  // Native deposits always hold back a gas reserve: they're self-paid even on
  // sponsored wallets (Privy's sponsorship simulation rejects value-carrying
  // ops — see privy-wallet-actions.tsx). Sponsored wallets need only a sliver
  // (~350k-gas mint on a cheap-native chain); self-paying external wallets
  // keep the roomier classic reserve.
  const { sponsored } = useWalletActions();
  const GAS_RESERVE = 10n ** 16n; // ~0.01 of the native token (self-paid)
  const SPONSORED_NATIVE_RESERVE = 10n ** 15n; // ~0.001 (sponsored)
  const reserve = sponsored ? SPONSORED_NATIVE_RESERVE : GAS_RESERVE;
  const rawBalance = mode === "native" ? native.data?.value : wrapped.balance;
  const balance =
    mode === "native" && rawBalance !== undefined
      ? rawBalance > reserve
        ? rawBalance - reserve
        : 0n
      : rawBalance;
  const overBalance =
    parsed !== null && balance !== undefined && parsed > balance;
  const needsApproval =
    mode === "wrapped" && parsed !== null && (wrapped.allowance ?? 0n) < parsed;

  useEffect(() => {
    if (depositTx.isSuccess) {
      void native.refetch();
      wrapped.refetch();
      void stake.refetch();
      setAmount("");
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [depositTx.isSuccess]);

  useEffect(() => {
    if (approveTx.isSuccess) wrapped.refetch();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [approveTx.isSuccess]);

  const disabled = parsed === null || parsed === 0n || overBalance;

  return (
    <Card>
      {showModeToggle && (
        <div className="border-paper-2 mb-5 inline-flex rounded-xl border p-1">
          {(["native", "wrapped"] as const).map((m) => (
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
              {m === "native" ? `${nativeSym} (native)` : wrappedSymbol}
            </button>
          ))}
        </div>
      )}

      <AmountField
        label="Amount to deposit"
        value={amount}
        onChange={setAmount}
        balance={balance}
        symbol={mode === "native" ? nativeSym : wrappedSymbol}
        decimals={depositDecimals}
      />

      {/* Pools mint nothing back — a deposit is a deposit, so no receive row. */}
      {!isPool && (
        <div className="bg-paper-1 mt-4 flex items-center justify-between rounded-xl px-4 py-3">
          <Caption className="text-surface-grey-2">You receive</Caption>
          <span className="font-breadDisplay text-text-standard font-bold">
            {parsed ? fmt(parsed) : "0"} {symbol}
          </span>
        </div>
      )}

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
          {needsApproval ? `Approve ${wrappedSymbol}` : "Deposit"}
        </ActionButton>
      </div>

      <TxStatus
        status={needsApproval ? approveTx.status : depositTx.status}
        hash={needsApproval ? approveTx.hash : depositTx.hash}
        error={needsApproval ? approveTx.error : depositTx.error}
        successLabel={needsApproval ? "Approved" : "Deposit confirmed"}
      />

      <Body className="text-surface-grey mt-6 text-sm">
        {isPool ? "Your deposit:" : `Your ${symbol} balance:`}{" "}
        <span className="text-text-standard font-semibold">
          {fmt(stake.data)} {symbol}
        </span>
      </Body>

      <YieldSplitHint />
    </Card>
  );
}

/** Reminds depositors of their current yield split, when the token supports it. */
function YieldSplitHint() {
  const { keepBps, supported } = useYieldSplit();
  const { isConnected } = useAccount();
  if (!supported || !isConnected || keepBps === undefined) return null;
  const give = 100 - keepBps / 100;
  return (
    <Caption className="text-surface-grey mt-2 block">
      Yield split: you give {give}% of your yield to recipients
      {keepBps > 0 ? ` and keep ${100 - give}%` : ""} —{" "}
      <Link href="/app/yield" className="text-core-orange underline">
        adjust
      </Link>
    </Caption>
  );
}
