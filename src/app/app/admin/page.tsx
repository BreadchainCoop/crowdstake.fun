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
  useInstanceMetadata,
  useSetInstanceMetadata,
} from "@/hooks/use-instance-metadata";
import { isValidImageUri } from "@/lib/metadata";
import { SafeImage } from "@/components/dapp/safe-image";
import {
  useUpdateCycleLength,
  useYieldClaimer,
  useYieldClaimerAdmin,
} from "@/hooks/use-admin";
import {
  shortenAddress,
  blocksToDuration,
  durationToBlocks,
} from "@/lib/format";
import { DurationInput } from "@/components/dapp/duration-input";
import { useActiveChain } from "@/hooks/use-chain";

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
      <InstanceMetadataCard />
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

function InstanceMetadataCard() {
  const meta = useInstanceMetadata();
  const { set, ...tx } = useSetInstanceMetadata();
  const [tokenImg, setTokenImg] = useState("");
  const [bannerImg, setBannerImg] = useState("");
  const [dirty, setDirty] = useState(false);

  // Seed the inputs from the current on-chain values until the user edits.
  useEffect(() => {
    if (!dirty) {
      setTokenImg(meta.tokenImageURI ?? "");
      setBannerImg(meta.bannerImageURI ?? "");
    }
  }, [meta.tokenImageURI, meta.bannerImageURI, dirty]);

  useEffect(() => {
    if (tx.isSuccess) {
      meta.refetch();
      setDirty(false);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tx.isSuccess]);

  const tokenValid = tokenImg.trim() === "" || isValidImageUri(tokenImg.trim());
  const bannerValid =
    bannerImg.trim() === "" || isValidImageUri(bannerImg.trim());
  const inputClass =
    "border-paper-2 bg-paper-main text-text-standard focus:border-core-orange w-full rounded-xl border px-4 py-2.5 font-mono text-sm outline-none";

  return (
    <Card>
      <Caption className="text-surface-grey-2">Instance artwork</Caption>
      <Body className="text-surface-grey mt-1 text-sm">
        Token + header images shown across the app for this instance.
      </Body>
      <div className="mt-3 flex items-start gap-3">
        <SafeImage
          uri={tokenImg}
          alt="Token image"
          className="border-paper-2 h-11 w-11 flex-none rounded-full border object-cover"
          fallback={
            <div className="border-paper-2 bg-paper-1 h-11 w-11 flex-none rounded-full border" />
          }
        />
        <input
          value={tokenImg}
          onChange={(e) => {
            setDirty(true);
            setTokenImg(e.target.value);
          }}
          placeholder="Token image — https:// or ipfs://"
          className={inputClass}
        />
      </div>
      {!tokenValid && (
        <Caption className="text-system-red mt-1 block">
          Use an https:// or ipfs:// image URL.
        </Caption>
      )}
      <input
        value={bannerImg}
        onChange={(e) => {
          setDirty(true);
          setBannerImg(e.target.value);
        }}
        placeholder="Header/banner image — https:// or ipfs://"
        className={`${inputClass} mt-3`}
      />
      {!bannerValid && (
        <Caption className="text-system-red mt-1 block">
          Use an https:// or ipfs:// image URL.
        </Caption>
      )}
      {bannerValid && bannerImg.trim() !== "" && (
        <SafeImage
          uri={bannerImg}
          alt="Banner"
          className="border-paper-2 mt-2 h-20 w-full rounded-xl border object-cover"
        />
      )}
      <Button
        app="fund"
        variant="primary"
        className="mt-4"
        isLoading={tx.isBusy}
        onClick={() => set(tokenImg.trim(), bannerImg.trim())}
        {...(!tokenValid || !bannerValid ? { disabled: true } : {})}
      >
        Update images
      </Button>
      <TxStatus
        status={tx.status}
        hash={tx.hash}
        error={tx.error}
        successLabel="Artwork updated"
      />
    </Card>
  );
}

function CycleLength() {
  const cycle = useCycle();
  const { blockTimeSeconds } = useActiveChain();
  const { update, ...tx } = useUpdateCycleLength();
  const [seconds, setSeconds] = useState(0);
  const blocks = durationToBlocks(seconds, blockTimeSeconds);
  const valid = blocks > 0n;

  useEffect(() => {
    if (tx.isSuccess) cycle.refetch();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tx.isSuccess]);

  return (
    <Card>
      <Caption className="text-surface-grey-2">Cycle length</Caption>
      <Body className="text-surface-grey-2 mt-1">
        Current:{" "}
        <span className="text-text-standard font-semibold">
          {cycle.cycleLength
            ? blocksToDuration(cycle.cycleLength, blockTimeSeconds)
            : "—"}
        </span>
      </Body>
      <div className="mt-3">
        <DurationInput onChange={setSeconds} disabled={tx.isBusy} />
      </div>
      {valid && (
        <Caption className="text-surface-grey mt-1 block">
          ≈ {blocks.toString()} blocks at {blockTimeSeconds}s/block.
        </Caption>
      )}
      <Button
        app="fund"
        variant="primary"
        className="mt-3"
        isLoading={tx.isBusy}
        onClick={() => valid && update(blocks)}
        {...(!valid ? { disabled: true } : {})}
      >
        Update
      </Button>
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
