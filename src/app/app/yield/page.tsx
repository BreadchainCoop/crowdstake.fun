"use client";

import { useEffect, useState } from "react";
import { Body, Caption } from "@breadcoop/ui";
import { Card, PageHeader } from "@/components/dapp/ui";
import { ActionButton } from "@/components/dapp/action-button";
import { TxStatus } from "@/components/dapp/tx-status";
import { cn } from "@/lib/utils";
import { shortChainName } from "@/lib/chains";
import { useActiveChainId } from "@/components/instance-provider";
import { useAmountFormatter } from "@/components/demo-mode-provider";
import { useBaseAssetSymbol } from "@/hooks/use-chain";
import { useFamily } from "@/hooks/use-family";
import {
  useClaimKeptYield,
  useInstanceToken,
  useKeptYield,
  useSetYieldSplit,
  useTokenBalance,
  useYieldSplit,
} from "@/hooks/use-token";

const GIVE_PRESETS = [100, 75, 50, 25, 0] as const;

export default function YieldPage() {
  return (
    <div className="mx-auto max-w-lg">
      <PageHeader
        title="Yield split"
        subtitle="Choose how much of the yield your stake earns goes to the community's recipients and how much you keep for yourself."
      />
      <FamilySplitNote />
      <SplitForm />
      <KeptYieldCard />
    </div>
  );
}

/** Family mode: the split is a per-chain token setting — say so honestly. */
function FamilySplitNote() {
  const family = useFamily();
  const chainId = useActiveChainId();
  if (!family.isFamily) return null;
  return (
    <Card className="mb-6">
      <Body className="text-surface-grey-2 text-sm">
        Your yield split applies per chain. You&apos;re setting it for{" "}
        <span className="text-text-standard font-semibold">
          {shortChainName(chainId)}
        </span>
        ; switch chains in the instance picker to set it elsewhere.
      </Body>
    </Card>
  );
}

function SplitForm() {
  const { keepBps, supported, refetch } = useYieldSplit();
  const { setSplit, ...tx } = useSetYieldSplit();
  // The slider anchors on the on-chain split until the user drags it.
  const [draftGive, setDraftGive] = useState<number | null>(null);

  const chainGive = keepBps !== undefined ? 100 - keepBps / 100 : 100;
  const give = draftGive ?? chainGive;
  const keep = 100 - give;
  const dirty = draftGive !== null && draftGive !== chainGive;

  useEffect(() => {
    if (tx.isSuccess) {
      void refetch();
      setDraftGive(null);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tx.isSuccess]);

  if (supported === false) {
    return (
      <Card>
        <Body className="text-surface-grey-2">
          This instance&apos;s token predates yield splitting — all yield goes
          to the community pool. A token upgrade is required to enable
          per-staker splits.
        </Body>
      </Card>
    );
  }

  return (
    <Card>
      <div className="flex items-baseline justify-between">
        <Caption className="text-surface-grey-2">Give to recipients</Caption>
        <span className="font-breadDisplay text-text-standard text-2xl font-bold">
          {give}%
        </span>
      </div>

      {/* Proportion bar: orange = given, grey = kept. */}
      <div className="bg-paper-2 mt-3 flex h-3 w-full overflow-hidden rounded-full">
        <div
          className="bg-core-orange h-full transition-all"
          style={{ width: `${give}%` }}
        />
      </div>

      <input
        type="range"
        min={0}
        max={100}
        step={1}
        value={give}
        onChange={(e) => setDraftGive(Number(e.target.value))}
        aria-label="Share of your yield given to recipients, percent"
        aria-valuetext={`Give ${give} percent, keep ${keep} percent`}
        className="bg-paper-2 accent-core-orange mt-4 h-2 w-full cursor-pointer appearance-none rounded-full"
      />

      <div className="mt-3 flex gap-2">
        {GIVE_PRESETS.map((p) => (
          <button
            key={p}
            onClick={() => setDraftGive(p)}
            className={cn(
              "rounded-lg border px-3 py-1.5 text-xs font-semibold transition-colors",
              give === p
                ? "border-core-orange bg-core-orange text-white"
                : "border-paper-2 text-surface-grey-2 hover:text-text-standard",
            )}
          >
            {p === 100 ? "Give all" : p === 0 ? "Keep all" : `${p}%`}
          </button>
        ))}
      </div>

      <div className="bg-paper-1 mt-4 flex items-center justify-between rounded-xl px-4 py-3">
        <Caption className="text-surface-grey-2">You keep</Caption>
        <span className="font-breadDisplay text-text-standard font-bold">
          {keep}% of your yield
        </span>
      </div>

      <div className="mt-6">
        <ActionButton
          isLoading={tx.isBusy}
          disabled={!dirty || supported === undefined}
          onClick={() => setSplit((100 - give) * 100)}
        >
          Update split
        </ActionButton>
      </div>

      <TxStatus
        status={tx.status}
        hash={tx.hash}
        error={tx.error}
        successLabel="Split updated"
      />

      <Body className="text-surface-grey mt-6 text-sm">
        Applies from now on — yield already earned keeps your previous split.
        Your voting power and withdrawable principal are unaffected.
      </Body>
    </Card>
  );
}

function KeptYieldCard() {
  const { symbol } = useInstanceToken();
  const baseSym = useBaseAssetSymbol();
  const { supported } = useYieldSplit();
  const kept = useKeptYield();
  const balance = useTokenBalance();
  const { claim, ...tx } = useClaimKeptYield();
  const fmt = useAmountFormatter();

  useEffect(() => {
    if (tx.isSuccess) {
      void kept.refetch();
      void balance.refetch();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tx.isSuccess]);

  if (supported === false) return null;

  return (
    <Card className="mt-6">
      <Caption className="text-surface-grey-2">Your kept yield</Caption>
      <div className="font-breadDisplay text-text-standard mt-1 text-3xl font-bold">
        {fmt(kept.data)} {symbol}
      </div>

      <div className="mt-6">
        <ActionButton
          isLoading={tx.isBusy}
          disabled={!kept.data}
          onClick={() => claim()}
        >
          Claim to wallet
        </ActionButton>
      </div>

      <TxStatus
        status={tx.status}
        hash={tx.hash}
        error={tx.error}
        successLabel="Yield claimed"
      />

      <Body className="text-surface-grey mt-6 text-sm">
        Claiming mints your kept yield as {symbol}, redeemable 1:1 for {baseSym}{" "}
        on the withdraw page.
      </Body>
    </Card>
  );
}
