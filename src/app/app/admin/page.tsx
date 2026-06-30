"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { isAddress, zeroAddress, type Address } from "viem";
import { useAccount } from "wagmi";
import { Body, Button, Caption } from "@breadcoop/ui";
import { ArrowRight } from "@phosphor-icons/react";
import { Card, PageHeader } from "@/components/dapp/ui";
import { ConnectGate } from "@/components/dapp/connect-gate";
import { TxStatus } from "@/components/dapp/tx-status";
import { useCycle } from "@/hooks/use-cycle";
import { useDelegate, useDelegateVotes } from "@/hooks/use-token";
import { useRegistryOwner } from "@/hooks/use-recipients";
import {
  useUpdateCycleLength,
  useYieldClaimer,
  useYieldClaimerAdmin,
} from "@/hooks/use-admin";
import { shortenAddress, blocksToDuration } from "@/lib/format";

export default function AdminPage() {
  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <PageHeader
        title="Admin"
        subtitle="Manage this instance: voting delegation, cycle length, and the yield-claimer role."
      />
      <ConnectGate>
        <Delegation />
        <AdminOnly />
      </ConnectGate>
    </div>
  );
}

function Delegation() {
  const { address } = useAccount();
  const delegate = useDelegate();
  const { delegate: doDelegate, ...tx } = useDelegateVotes();
  const [to, setTo] = useState("");
  const toValid = isAddress(to) && to.toLowerCase() !== zeroAddress;
  const delegatedToSelf =
    delegate.data &&
    address &&
    delegate.data.toLowerCase() === address.toLowerCase();

  useEffect(() => {
    if (tx.isSuccess) {
      delegate.refetch();
      setTo("");
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tx.isSuccess]);

  return (
    <Card>
      <Caption className="text-surface-grey-2">Voting delegation</Caption>
      <Body className="text-surface-grey-2 mt-1">
        Current delegate:{" "}
        <span className="text-text-standard font-mono">
          {delegate.data ? shortenAddress(delegate.data, 6) : "none"}
        </span>
        {delegatedToSelf ? " (you)" : ""}
      </Body>
      <Body className="text-surface-grey mt-2 text-sm">
        Deposits auto-delegate to you. Re-delegate your voting power to yourself
        or to another address.
      </Body>
      <div className="mt-4 flex flex-wrap gap-2">
        <Button
          app="fund"
          variant="secondary"
          isLoading={tx.isBusy}
          onClick={() => doDelegate()}
        >
          Delegate to myself
        </Button>
      </div>
      <div className="mt-3 flex gap-2">
        <input
          value={to}
          onChange={(e) => setTo(e.target.value)}
          placeholder="0x… delegate to address"
          className="border-paper-2 bg-paper-main text-text-standard focus:border-core-orange w-full rounded-xl border px-4 py-2.5 font-mono text-sm outline-none"
        />
        <Button
          app="fund"
          variant="secondary"
          isLoading={tx.isBusy}
          onClick={() => toValid && doDelegate(to as Address)}
          {...(!toValid ? { disabled: true } : {})}
        >
          Delegate
        </Button>
      </div>
      <TxStatus
        status={tx.status}
        hash={tx.hash}
        error={tx.error}
        successLabel="Delegated"
      />
    </Card>
  );
}

function AdminOnly() {
  const { isAdmin } = useRegistryOwner();
  if (!isAdmin) {
    return (
      <Caption className="bg-paper-1 text-surface-grey-2 block rounded-lg px-4 py-3">
        Owner-only controls (cycle length, yield claimer) are hidden — connect
        as this instance&apos;s admin to manage them.
      </Caption>
    );
  }
  return (
    <>
      <CycleLength />
      <YieldClaimer />
      <Card>
        <Caption className="text-surface-grey-2">Recipients</Caption>
        <Body className="text-surface-grey-2 mt-1">
          Add, remove, and process funding recipients.
        </Body>
        <Button
          app="fund"
          variant="secondary"
          as={Link}
          href="/app/recipients"
          className="mt-4"
          rightIcon={<ArrowRight weight="bold" />}
        >
          Manage recipients
        </Button>
      </Card>
    </>
  );
}

function CycleLength() {
  const cycle = useCycle();
  const { update, ...tx } = useUpdateCycleLength();
  const [blocks, setBlocks] = useState("");
  const valid =
    /^\d+$/.test(blocks.trim()) && BigInt(blocks.trim() || "0") > 0n;

  useEffect(() => {
    if (tx.isSuccess) {
      cycle.refetch();
      setBlocks("");
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tx.isSuccess]);

  return (
    <Card>
      <Caption className="text-surface-grey-2">Cycle length</Caption>
      <Body className="text-surface-grey-2 mt-1">
        Current:{" "}
        <span className="text-text-standard font-semibold">
          {cycle.cycleLength?.toString() ?? "—"} blocks
        </span>{" "}
        ({cycle.cycleLength ? blocksToDuration(cycle.cycleLength) : "—"})
      </Body>
      <div className="mt-3 flex gap-2">
        <input
          value={blocks}
          onChange={(e) => setBlocks(e.target.value)}
          placeholder="new length in blocks"
          className="border-paper-2 bg-paper-main text-text-standard focus:border-core-orange w-full rounded-xl border px-4 py-2.5 outline-none"
        />
        <Button
          app="fund"
          variant="primary"
          isLoading={tx.isBusy}
          onClick={() => valid && update(BigInt(blocks.trim()))}
          {...(!valid ? { disabled: true } : {})}
        >
          Update
        </Button>
      </div>
      <Caption className="text-surface-grey mt-1 block">
        Applies immediately — it changes when the current cycle ends.
      </Caption>
      <TxStatus
        status={tx.status}
        hash={tx.hash}
        error={tx.error}
        successLabel="Cycle length updated"
      />
    </Card>
  );
}

function YieldClaimer() {
  const claimer = useYieldClaimer();
  const { prepare, finalize, ...tx } = useYieldClaimerAdmin();
  const [addr, setAddr] = useState("");
  const valid = isAddress(addr) && addr.toLowerCase() !== zeroAddress;
  const hasPending = claimer.pending && claimer.pending !== zeroAddress;
  const unlockMs =
    claimer.pendingFinishedAt !== undefined
      ? Number(claimer.pendingFinishedAt) * 1000
      : undefined;
  const canFinalize =
    hasPending && unlockMs !== undefined && Date.now() >= unlockMs;

  useEffect(() => {
    if (tx.isSuccess) {
      claimer.refetch();
      setAddr("");
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tx.isSuccess]);

  return (
    <Card>
      <Caption className="text-surface-grey-2">Yield claimer</Caption>
      <Body className="text-surface-grey-2 mt-1">
        Current:{" "}
        <span className="text-text-standard font-mono">
          {claimer.current ? shortenAddress(claimer.current, 6) : "—"}
        </span>
      </Body>
      <Body className="text-surface-grey mt-2 text-sm">
        The yield claimer (the distribution manager) is what claims accrued
        yield on distribution. Rotating it uses a 14-day timelock.
      </Body>
      {hasPending && (
        <Caption className="text-system-warning mt-2 block">
          Pending: {shortenAddress(claimer.pending!, 6)} —{" "}
          {canFinalize
            ? "ready to finalize."
            : unlockMs !== undefined
              ? `finalizable on ${new Date(unlockMs).toLocaleString()}.`
              : "finalizable after the 14-day timelock."}
        </Caption>
      )}
      <div className="mt-3 flex gap-2">
        <input
          value={addr}
          onChange={(e) => setAddr(e.target.value)}
          placeholder="0x… new claimer"
          disabled={Boolean(hasPending)}
          className="border-paper-2 bg-paper-main text-text-standard focus:border-core-orange w-full rounded-xl border px-4 py-2.5 font-mono text-sm outline-none disabled:opacity-50"
        />
        <Button
          app="fund"
          variant="secondary"
          isLoading={tx.isBusy}
          onClick={() => valid && !hasPending && prepare(addr as Address)}
          {...(!valid || hasPending ? { disabled: true } : {})}
        >
          Prepare
        </Button>
      </div>
      {hasPending && (
        <Button
          app="fund"
          variant="primary"
          className="mt-3"
          isLoading={tx.isBusy}
          onClick={() => canFinalize && finalize()}
          {...(!canFinalize ? { disabled: true } : {})}
        >
          {canFinalize ? "Finalize rotation" : "Timelock not elapsed"}
        </Button>
      )}
      <TxStatus
        status={tx.status}
        hash={tx.hash}
        error={tx.error}
        successLabel="Done"
      />
    </Card>
  );
}
