"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { keccak256, toHex, isAddress, zeroAddress, type Address } from "viem";
import { useAccount } from "wagmi";
import { Body, Button, Caption } from "@breadcoop/ui";
import {
  ArrowRight,
  CaretDown,
  CaretRight,
  CheckCircle,
} from "@phosphor-icons/react";
import { Card, PageHeader } from "@/components/dapp/ui";
import { ActionButton } from "@/components/dapp/action-button";
import { TxStatus } from "@/components/dapp/tx-status";
import { useDeployInstance } from "@/hooks/use-deploy";
import { useInstanceContext } from "@/components/instance-provider";
import { shortenAddress } from "@/lib/format";
import { MAX_POINTS } from "@/lib/constants";
import { isValidImageUri } from "@/lib/metadata";
import { SafeImage } from "@/components/dapp/safe-image";

export default function DeployPage() {
  return (
    <div className="mx-auto max-w-lg">
      <PageHeader
        title="Deploy your instance"
        subtitle="Launch a complete, self-owned Crowdstaking instance on Gnosis in one transaction. You become the admin of every contract."
      />
      <DeployForm />
    </div>
  );
}

function DeployForm() {
  const { address } = useAccount();
  const router = useRouter();
  const { addInstance } = useInstanceContext();
  const { deploy, instance, status, isBusy, isSuccess, error, hash } =
    useDeployInstance();

  const [name, setName] = useState("");
  const [symbol, setSymbol] = useState("");
  const [cycleLength, setCycleLength] = useState("17280");
  const [owner, setOwner] = useState("");

  const [advanced, setAdvanced] = useState(false);
  const [maxPoints, setMaxPoints] = useState(MAX_POINTS.toString());
  const [customSalt, setCustomSalt] = useState("");

  const [tokenImg, setTokenImg] = useState("");
  const [bannerImg, setBannerImg] = useState("");
  const tokenImgValid =
    tokenImg.trim() === "" || isValidImageUri(tokenImg.trim());
  const bannerImgValid =
    bannerImg.trim() === "" || isValidImageUri(bannerImg.trim());

  // Democratic (V2-only): registry kind, founding recipients, proposal window.
  const [registryKind, setRegistryKind] = useState<"admin" | "voting">("admin");
  const [foundersText, setFoundersText] = useState("");
  const [expiryDays, setExpiryDays] = useState("7");

  const ownerValue = (owner.trim() || address || "") as string;
  const cleanCycle = cycleLength.trim();
  const cleanPoints = maxPoints.trim();
  const ownerValid = isAddress(ownerValue);
  const cycleValid = /^\d+$/.test(cleanCycle) && BigInt(cleanCycle || "0") > 0n;
  const pointsValid =
    /^\d+$/.test(cleanPoints) && BigInt(cleanPoints || "0") > 0n;

  const democratic = registryKind === "voting";
  const typedFounders = foundersText
    .split(/[\s,]+/)
    .map((s) => s.trim())
    .filter(Boolean);
  // Default the founding cohort to the owner if none typed.
  const founders =
    typedFounders.length > 0 ? typedFounders : ownerValid ? [ownerValue] : [];
  const foundersValid =
    founders.length > 0 &&
    founders.every((f) => isAddress(f) && f.toLowerCase() !== zeroAddress) &&
    new Set(founders.map((f) => f.toLowerCase())).size === founders.length;
  const cleanExpiry = expiryDays.trim();
  const expiryValid = /^\d+$/.test(cleanExpiry) && Number(cleanExpiry) > 0;

  const canDeploy =
    name.trim().length > 0 &&
    symbol.trim().length > 0 &&
    cycleValid &&
    pointsValid &&
    ownerValid &&
    tokenImgValid &&
    bannerImgValid &&
    (!democratic || (foundersValid && expiryValid));

  const onDeploy = () => {
    if (!canDeploy) return;
    // A custom salt makes the instance address deterministic; otherwise mix in
    // name + per-attempt entropy so re-deploying the same config can't collide
    // on the factory's CREATE2 (Create2Failed).
    const salt = customSalt.trim()
      ? keccak256(toHex(customSalt.trim()))
      : keccak256(
          toHex(
            `${name.trim()}|${symbol.trim()}|${cleanCycle}|${ownerValue}|${crypto.randomUUID()}`,
          ),
        );
    void deploy({
      owner: ownerValue as Address,
      cycleLength: BigInt(cleanCycle),
      tokenName: name.trim(),
      tokenSymbol: symbol.trim(),
      maxVotingPoints: BigInt(cleanPoints),
      salt,
      registryKind: democratic ? 1 : 0,
      initialRecipients: democratic ? (founders as Address[]) : [],
      proposalExpiry: democratic ? BigInt(Number(cleanExpiry) * 86400) : 0n,
      tokenImageURI: tokenImg.trim(),
      bannerImageURI: bannerImg.trim(),
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
              ["Distribution Strategy", instance.distributionStrategy],
              ["Voting Power Strategy", instance.votingPowerStrategy],
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
        {owner !== "" && !isAddress(owner) && (
          <Caption className="text-system-red mt-1 block">
            Not a valid address.
          </Caption>
        )}
      </Field>

      <div className="mb-4">
        <Caption className="text-surface-grey-2 mb-1.5 block">
          Recipient governance
        </Caption>
        <div className="border-paper-2 inline-flex rounded-xl border p-1">
          {(["admin", "voting"] as const).map((k) => (
            <button
              key={k}
              type="button"
              onClick={() => setRegistryKind(k)}
              className={`rounded-lg px-4 py-1.5 text-sm font-semibold transition-colors ${
                registryKind === k
                  ? "bg-core-orange text-white"
                  : "text-surface-grey-2 hover:text-text-standard"
              }`}
            >
              {k === "admin" ? "Admin-managed" : "Democratic"}
            </button>
          ))}
        </div>
        {democratic && (
          <div className="mt-4 space-y-4">
            <Field label="Founding recipients (one address per line)">
              <textarea
                value={foundersText}
                onChange={(e) => setFoundersText(e.target.value)}
                placeholder={address ?? "0x…"}
                rows={3}
                className="border-paper-2 bg-paper-main text-text-standard focus:border-core-orange w-full rounded-xl border px-4 py-3 font-mono text-sm outline-none"
              />
              {foundersText.trim() !== "" && !foundersValid && (
                <Caption className="text-system-red mt-1 block">
                  Enter unique, valid, non-zero addresses.
                </Caption>
              )}
              <Caption className="text-surface-grey mt-1 block">
                These members vote to add/remove future recipients (additions
                need everyone&apos;s vote). Blank defaults to you. The owner
                can&apos;t add recipients directly.
              </Caption>
            </Field>
            <Field label="Proposal expiry (days)">
              <Input
                value={expiryDays}
                onChange={setExpiryDays}
                placeholder="7"
              />
              {!expiryValid && expiryDays !== "" && (
                <Caption className="text-system-red mt-1 block">
                  Must be a positive integer.
                </Caption>
              )}
            </Field>
          </div>
        )}
      </div>

      <ArtworkFields
        tokenImg={tokenImg}
        setTokenImg={setTokenImg}
        bannerImg={bannerImg}
        setBannerImg={setBannerImg}
        tokenImgValid={tokenImgValid}
        bannerImgValid={bannerImgValid}
      />

      <button
        type="button"
        onClick={() => setAdvanced((a) => !a)}
        className="text-surface-grey-2 hover:text-core-orange mb-4 flex items-center gap-1 text-sm font-medium"
      >
        {advanced ? <CaretDown weight="bold" /> : <CaretRight weight="bold" />}
        Advanced
      </button>
      {advanced && (
        <div className="border-paper-2 mb-4 space-y-4 rounded-xl border border-dashed p-4">
          <Field label="Max voting points per recipient (basis points)">
            <Input
              value={maxPoints}
              onChange={setMaxPoints}
              placeholder="10000"
            />
            {!pointsValid && maxPoints !== "" && (
              <Caption className="text-system-red mt-1 block">
                Must be a positive integer (10000 = 100%).
              </Caption>
            )}
          </Field>
          <Field label="Custom CREATE2 salt (optional — deterministic address)">
            <Input
              value={customSalt}
              onChange={setCustomSalt}
              placeholder="leave blank for a fresh random salt"
              mono
            />
            <Caption className="text-surface-grey mt-1 block">
              Blank uses random entropy so repeat deploys never collide. A fixed
              value makes the instance address reproducible.
            </Caption>
          </Field>
        </div>
      )}

      <div className="mt-2">
        <ActionButton
          isLoading={isBusy}
          disabled={!canDeploy}
          onClick={onDeploy}
        >
          Deploy instance
        </ActionButton>
      </div>

      <TxStatus
        status={status}
        hash={hash}
        error={error}
        successLabel="Instance deployed"
      />
      {isSuccess && !instance && (
        <Caption className="text-system-warning mt-2 block">
          The deploy transaction confirmed, but the instance addresses
          couldn&apos;t be decoded. Check the transaction, and don&apos;t
          re-submit (it may have already deployed).
        </Caption>
      )}

      <Body className="text-surface-grey mt-6 text-sm">
        Deploys the full system — token, cycle module, voting module + power,
        recipient registry, and a vote-driven distribution manager — wired and
        owned by you. Yield is distributed proportionally to community votes.
      </Body>
    </Card>
  );
}

function ArtworkFields({
  tokenImg,
  setTokenImg,
  bannerImg,
  setBannerImg,
  tokenImgValid,
  bannerImgValid,
}: {
  tokenImg: string;
  setTokenImg: (v: string) => void;
  bannerImg: string;
  setBannerImg: (v: string) => void;
  tokenImgValid: boolean;
  bannerImgValid: boolean;
}) {
  return (
    <div className="mb-4">
      <Caption className="text-surface-grey-2 mb-1.5 block">
        Instance artwork (optional)
      </Caption>
      <div className="flex items-start gap-3">
        <SafeImage
          uri={tokenImg}
          alt="Token image preview"
          className="border-paper-2 h-12 w-12 flex-none rounded-full border object-cover"
          fallback={
            <div className="border-paper-2 bg-paper-1 h-12 w-12 flex-none rounded-full border" />
          }
        />
        <div className="flex-1">
          <Input
            value={tokenImg}
            onChange={setTokenImg}
            placeholder="Token image — https:// or ipfs://"
            mono
          />
          {!tokenImgValid && (
            <Caption className="text-system-red mt-1 block">
              Use an https:// or ipfs:// image URL.
            </Caption>
          )}
        </div>
      </div>
      <div className="mt-3">
        <Input
          value={bannerImg}
          onChange={setBannerImg}
          placeholder="Header/banner image — https:// or ipfs://"
          mono
        />
        {!bannerImgValid && (
          <Caption className="text-system-red mt-1 block">
            Use an https:// or ipfs:// image URL.
          </Caption>
        )}
        {bannerImgValid && bannerImg.trim() !== "" && (
          <SafeImage
            uri={bannerImg}
            alt="Banner preview"
            className="border-paper-2 mt-2 h-20 w-full rounded-xl border object-cover"
          />
        )}
      </div>
      <Caption className="text-surface-grey mt-2 block">
        Shown across the app for this instance. You can change these later from
        the Admin page.
      </Caption>
    </div>
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
