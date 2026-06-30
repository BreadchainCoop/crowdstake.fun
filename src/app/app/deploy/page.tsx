"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { keccak256, toHex, isAddress, type Address } from "viem";
import { useAccount } from "wagmi";
import { Body, Button, Caption } from "@breadcoop/ui";
import { ArrowRight, CheckCircle } from "@phosphor-icons/react";
import { Card, PageHeader } from "@/components/dapp/ui";
import { ConnectGate } from "@/components/dapp/connect-gate";
import { TxStatus } from "@/components/dapp/tx-status";
import { useDeployInstance } from "@/hooks/use-deploy";
import { useInstanceContext } from "@/components/instance-provider";
import { shortenAddress } from "@/lib/format";

export default function DeployPage() {
  return (
    <div className="mx-auto max-w-lg">
      <PageHeader
        title="Deploy your instance"
        subtitle="Launch a complete, self-owned Crowdstaking instance on Gnosis in one transaction. You become the admin of every contract."
      />
      <ConnectGate>
        <DeployForm />
      </ConnectGate>
    </div>
  );
}

function DeployForm() {
  const { address } = useAccount();
  const router = useRouter();
  const { addInstance } = useInstanceContext();
  const { deploy, instance, isBusy, isSuccess, error, hash } =
    useDeployInstance();

  const [name, setName] = useState("");
  const [symbol, setSymbol] = useState("");
  const [cycleLength, setCycleLength] = useState("17280");
  const [owner, setOwner] = useState("");

  const ownerValue = (owner || address || "") as string;
  const ownerValid = isAddress(ownerValue);
  const cycleValid = /^\d+$/.test(cycleLength) && BigInt(cycleLength) > 0n;
  const canDeploy =
    name.trim().length > 0 &&
    symbol.trim().length > 0 &&
    cycleValid &&
    ownerValid;

  const onDeploy = () => {
    if (!canDeploy) return;
    const salt = keccak256(toHex(`${symbol}-${cycleLength}-${ownerValue}`));
    void deploy({
      owner: ownerValue as Address,
      cycleLength: BigInt(cycleLength),
      tokenName: name.trim(),
      tokenSymbol: symbol.trim(),
      maxVotingPoints: 10_000n,
      salt,
    });
  };

  // Success — show the new instance and let the user switch to it.
  if (isSuccess && instance) {
    return (
      <Card>
        <p className="text-system-green flex items-center gap-2">
          <CheckCircle size={22} weight="fill" />
          <span className="font-breadDisplay text-lg font-bold">
            Instance deployed!
          </span>
        </p>
        <dl className="mt-4 space-y-2">
          {(
            [
              ["Token", instance.token],
              ["Distribution Manager", instance.distributionManager],
              ["Cycle Module", instance.cycleModule],
              ["Voting Module", instance.votingModule],
              ["Recipient Registry", instance.recipientRegistry],
            ] as const
          ).map(([label, addr]) => (
            <div
              key={label}
              className="border-paper-2 flex items-center justify-between border-t pt-2"
            >
              <Caption className="text-surface-grey">{label}</Caption>
              <span className="text-text-standard font-mono text-sm">
                {shortenAddress(addr, 6)}
              </span>
            </div>
          ))}
        </dl>
        <Button
          app="fund"
          variant="primary"
          className="mt-6 w-full"
          rightIcon={<ArrowRight weight="bold" />}
          onClick={() => {
            addInstance({
              label: symbol.trim() || "New instance",
              addresses: instance,
            });
            router.push("/app");
          }}
        >
          Use this instance
        </Button>
      </Card>
    );
  }

  return (
    <Card>
      <Field label="Token name">
        <Input
          value={name}
          onChange={setName}
          placeholder="Acme Community Stake"
        />
      </Field>
      <Field label="Token symbol">
        <Input value={symbol} onChange={setSymbol} placeholder="ACME" />
      </Field>
      <Field label="Cycle length (blocks, ~5s each on Gnosis)">
        <Input
          value={cycleLength}
          onChange={setCycleLength}
          placeholder="17280"
        />
        {!cycleValid && cycleLength !== "" && (
          <Caption className="text-system-red mt-1 block">
            Must be a positive integer.
          </Caption>
        )}
      </Field>
      <Field label="Owner / admin (defaults to you)">
        <Input
          value={owner}
          onChange={setOwner}
          placeholder={address ?? "0x…"}
          mono
        />
        {!ownerValid && (
          <Caption className="text-system-red mt-1 block">
            Not a valid address.
          </Caption>
        )}
      </Field>

      <Button
        app="fund"
        variant="primary"
        className="mt-2 w-full"
        isLoading={isBusy}
        onClick={onDeploy}
        {...(!canDeploy ? { disabled: true } : {})}
      >
        Deploy instance
      </Button>

      <TxStatus
        status={isBusy ? "confirming" : error ? "error" : "idle"}
        hash={hash}
        error={error}
      />

      <Body className="text-surface-grey mt-6 text-sm">
        Deploys the full system — token, cycle module, voting module + power,
        recipient registry, and a vote-driven distribution manager — wired and
        owned by you. Yield is distributed proportionally to community votes.
      </Body>
    </Card>
  );
}

function Field({
  label,
  children,
}: {
  label: string;
  children: React.ReactNode;
}) {
  return (
    <div className="mb-4">
      <Caption className="text-surface-grey-2 mb-1.5 block">{label}</Caption>
      {children}
    </div>
  );
}

function Input({
  value,
  onChange,
  placeholder,
  mono,
}: {
  value: string;
  onChange: (v: string) => void;
  placeholder?: string;
  mono?: boolean;
}) {
  return (
    <input
      value={value}
      onChange={(e) => onChange(e.target.value)}
      placeholder={placeholder}
      className={`border-paper-2 bg-paper-main text-text-standard focus:border-core-orange w-full rounded-xl border px-4 py-3 outline-none ${
        mono ? "font-mono text-sm" : ""
      }`}
    />
  );
}
