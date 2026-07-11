"use client";

import { useMemo, useState } from "react";
import { formatUnits } from "viem";
import { Body, Button, Caption } from "@breadcoop/ui";
import {
  ArrowClockwise,
  ArrowSquareOut,
  CheckCircle,
  Globe,
  SpinnerGap,
  Warning,
} from "@phosphor-icons/react";
import { Card } from "@/components/dapp/ui";
import { cn } from "@/lib/utils";
import { formatAmount, parseAmount } from "@/lib/format";
import { shortChainName, txUrl } from "@/lib/chains";
import { useWalletActions } from "@/components/wallet/wallet-actions";
import type { FamilyState } from "@/hooks/use-family";
import {
  useFamilyDeposit,
  type DepositAllocation,
  type DepositRow,
  type FamilyDepositChain,
} from "@/hooks/use-family-deposit";

const GAS_RESERVE = 10n ** 16n; // ~0.01 native, kept back to pay gas (self-paid)
// Native deposits are the one SELF-PAID case even for sponsored wallets
// (Privy's sponsorship simulation rejects value-carrying ops — see
// privy-wallet-actions.tsx), so MAX keeps a sliver back for their gas
// (a mint is ~350k gas; cheap-native chains only).
const SPONSORED_NATIVE_RESERVE = 10n ** 15n; // ~0.001 native

/**
 * Multi-asset family mint: deposit into a community token across every chain it
 * lives on, in whatever asset you hold on each. One panel, per-chain amounts.
 */
export function FamilyDeposit({
  family,
  tokenSymbol,
}: {
  family: FamilyState;
  tokenSymbol: string;
}) {
  const { sponsored } = useWalletActions();
  const dep = useFamilyDeposit(family);
  // Per-chain input + asset mode (native chains can pick native or wrapped).
  const [amounts, setAmounts] = useState<Record<number, string>>({});
  const [modes, setModes] = useState<Record<number, "native" | "wrapped">>({});

  const modeFor = (c: FamilyDepositChain): "native" | "wrapped" =>
    modes[c.chainId] ?? (c.yieldKind === "stable" ? "wrapped" : "native");

  const decimalsFor = (c: FamilyDepositChain, mode: "native" | "wrapped") =>
    mode === "native" ? 18 : c.wrappedDecimals;

  // Balance available for a row's chosen asset. Native rows always hold back a
  // reserve: gas for self-paying wallets, simulation headroom for sponsored.
  const availableFor = (c: FamilyDepositChain, mode: "native" | "wrapped") => {
    if (mode === "wrapped") return c.wrappedBalance;
    const reserve = sponsored ? SPONSORED_NATIVE_RESERVE : GAS_RESERVE;
    return c.nativeBalance > reserve ? c.nativeBalance - reserve : 0n;
  };

  const rowByChain = (chainId: number): DepositRow | undefined =>
    dep.rows.find((r) => r.chainId === chainId);

  const allocations: DepositAllocation[] = useMemo(
    () =>
      dep.chains.map((c) => {
        const mode = modeFor(c);
        const parsed = parseAmount(
          amounts[c.chainId] ?? "",
          decimalsFor(c, mode),
        );
        return { chainId: c.chainId, amount: parsed ?? 0n, mode };
      }),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [dep.chains, amounts, modes],
  );

  // Total minted ≈ sum of per-chain deposit amounts, normalized to decimals.
  const totalNormalized = allocations.reduce((sum, a) => {
    const c = dep.chains.find((x) => x.chainId === a.chainId);
    if (!c || a.amount <= 0n) return sum;
    return sum + Number(formatUnits(a.amount, decimalsFor(c, a.mode)));
  }, 0);

  const activeCount = allocations.filter((a) => a.amount > 0n).length;
  const anyOver = allocations.some((a) => {
    const c = dep.chains.find((x) => x.chainId === a.chainId);
    return c && a.amount > availableFor(c, a.mode);
  });
  const anyFailed = dep.rows.some((r) => r.state === "failed");
  const settled =
    dep.rows.length > 0 &&
    dep.rows.every((r) => r.state === "confirmed" || r.state === "failed");

  if (dep.isLoading && dep.chains.length === 0) {
    return (
      <Card>
        <Body className="text-surface-grey-2">
          Reading your balances on each chain…
        </Body>
      </Card>
    );
  }

  return (
    <Card>
      <Caption className="text-surface-grey-2 flex items-center gap-1.5">
        <Globe size={14} weight="fill" className="text-core-orange" />
        Mint {tokenSymbol} across your chains
      </Caption>
      <Body className="text-surface-grey mt-1 text-sm">
        Deposit whatever you hold on each chain — you mint {tokenSymbol} on
        every chain from your local balance there.
      </Body>

      <ul className="mt-4 space-y-4">
        {dep.chains.map((c) => {
          const mode = modeFor(c);
          const dec = decimalsFor(c, mode);
          const avail = availableFor(c, mode);
          const parsed = parseAmount(amounts[c.chainId] ?? "", dec);
          const over = parsed !== null && parsed > avail;
          const canToggle = c.yieldKind === "native" && c.wrapped !== null;
          const symbol = mode === "native" ? c.nativeSymbol : c.wrappedSymbol;
          const row = rowByChain(c.chainId);
          return (
            <li
              key={c.chainId}
              className="border-paper-2 border-t pt-4 first:border-t-0 first:pt-0"
            >
              <div className="flex items-center justify-between">
                <span className="text-text-standard font-breadDisplay font-bold">
                  {shortChainName(c.chainId)}
                </span>
                {canToggle && (
                  <div className="border-paper-2 inline-flex rounded-lg border p-0.5">
                    {(["native", "wrapped"] as const).map((m) => (
                      <button
                        key={m}
                        type="button"
                        onClick={() =>
                          setModes((p) => ({ ...p, [c.chainId]: m }))
                        }
                        className={cn(
                          "rounded-md px-2.5 py-1 text-xs font-semibold",
                          mode === m
                            ? "bg-core-orange text-white"
                            : "text-surface-grey-2",
                        )}
                      >
                        {m === "native" ? c.nativeSymbol : c.wrappedSymbol}
                      </button>
                    ))}
                  </div>
                )}
              </div>

              <div className="mt-2 flex items-center gap-2">
                <div className="border-paper-2 bg-paper-main focus-within:border-core-orange flex flex-1 items-center gap-2 rounded-xl border px-3 py-2">
                  <input
                    inputMode="decimal"
                    placeholder="0.0"
                    value={amounts[c.chainId] ?? ""}
                    onChange={(e) =>
                      setAmounts((p) => ({ ...p, [c.chainId]: e.target.value }))
                    }
                    className="font-breadDisplay text-text-standard placeholder:text-surface-grey w-full bg-transparent text-lg font-bold outline-none"
                  />
                  <span className="text-surface-grey-2 text-sm font-bold">
                    {symbol}
                  </span>
                </div>
                <button
                  type="button"
                  onClick={() =>
                    setAmounts((p) => ({
                      ...p,
                      [c.chainId]: formatUnits(avail, dec),
                    }))
                  }
                  className="text-core-orange text-xs font-semibold hover:underline"
                >
                  MAX
                </button>
              </div>

              <div className="mt-1 flex items-center justify-between">
                <Caption className="text-surface-grey">
                  Balance: {formatAmount(avail, 4, dec)} {symbol}
                </Caption>
                {over && (
                  <Caption className="text-system-red">Exceeds balance</Caption>
                )}
                {row && <DepositRowStatus row={row} />}
              </div>
            </li>
          );
        })}
      </ul>

      <div className="bg-paper-1 mt-5 flex items-center justify-between rounded-xl px-4 py-3">
        <Caption className="text-surface-grey-2">
          You mint{" "}
          {activeCount > 0
            ? `on ${activeCount} chain${activeCount === 1 ? "" : "s"}`
            : "—"}
        </Caption>
        <span className="font-breadDisplay text-text-standard font-bold">
          ≈{" "}
          {totalNormalized.toLocaleString("en-US", {
            maximumFractionDigits: 2,
          })}{" "}
          {tokenSymbol}
        </span>
      </div>

      <Caption className="text-surface-grey mt-3 block">
        {sponsored
          ? "Gasless — each chain's deposit is submitted for you, no network switching."
          : "You'll confirm one transaction per chain (a network switch + a deposit, plus an approval for ERC-20 assets) and need a little gas on each."}
      </Caption>

      <div className="mt-4 flex flex-wrap gap-3">
        <Button
          app="fund"
          variant="primary"
          isLoading={dep.isBusy}
          onClick={() => void dep.mint(allocations)}
          {...(activeCount === 0 || anyOver || dep.isBusy
            ? { disabled: true }
            : {})}
        >
          {activeCount > 1 ? `Mint on ${activeCount} chains` : "Mint"}
        </Button>
        {settled && anyFailed && (
          <Button
            app="fund"
            variant="secondary"
            isLoading={dep.isBusy}
            onClick={() => void dep.retryFailed(allocations)}
            leftIcon={<ArrowClockwise weight="bold" />}
          >
            Retry failed
          </Button>
        )}
      </div>
    </Card>
  );
}

function DepositRowStatus({ row }: { row: DepositRow }) {
  if (row.state === "approving")
    return (
      <Caption className="text-surface-grey-2 flex items-center gap-1">
        <SpinnerGap size={12} className="animate-spin" /> Approving…
      </Caption>
    );
  if (row.state === "depositing")
    return (
      <Caption className="text-surface-grey-2 flex items-center gap-1">
        <SpinnerGap size={12} className="animate-spin" /> Depositing…
      </Caption>
    );
  if (row.state === "confirmed")
    return (
      <a
        href={row.txHash ? txUrl(row.txHash, row.chainId) : "#"}
        target="_blank"
        rel="noreferrer"
        className="text-system-green flex items-center gap-1 text-xs font-semibold hover:underline"
      >
        <CheckCircle size={13} weight="fill" /> Minted{" "}
        <ArrowSquareOut size={11} />
      </a>
    );
  if (row.state === "failed")
    return (
      <Caption className="text-system-red flex items-center gap-1">
        <Warning size={12} weight="fill" /> {row.error ?? "Failed"}
      </Caption>
    );
  return null;
}
