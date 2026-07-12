"use client";

import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import {
  keccak256,
  toHex,
  isAddress,
  zeroAddress,
  type Address,
  type Hex,
} from "viem";
import { useAccount, useChainId, useSwitchChain } from "wagmi";
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
import { InstanceShareCard } from "@/components/dapp/instance-share-card";
import { DurationInput } from "@/components/dapp/duration-input";
import { useDeployInstance } from "@/hooks/use-deploy";
import {
  useDeployFamily,
  usePendingFamily,
  type FamilyDeployConfig,
} from "@/hooks/use-deploy-family";
import { useInstanceContext } from "@/components/instance-provider";
import { durationToBlocks, shortenAddress } from "@/lib/format";
import { instanceShareUrl } from "@/lib/instance";
import {
  CHAINS,
  DEFAULT_CHAIN_ID,
  chainConfig,
  deployableChainIds,
  isSupportedChain,
  shortChainName,
} from "@/lib/chains";
import { familyIdForConfig, loadFamilyDeployParams } from "@/lib/families";
import { MAX_POINTS } from "@/lib/constants";
import { isValidImageUri } from "@/lib/metadata";
import { SafeImage } from "@/components/dapp/safe-image";
import { ChainSelect } from "./_components/chain-select";
import { ChainChecklist } from "./_components/chain-checklist";
import { FamilySuccessCard } from "./_components/family-success-card";

export default function DeployPage() {
  return (
    <div className="mx-auto max-w-lg">
      <PageHeader
        title="Deploy your instance"
        subtitle="Launch a complete, self-owned staking instance in one transaction. Pick one chain, or several to form a cross-chain community that shares one signed ballot. You become the admin of every contract."
      />
      <DeployForm />
    </div>
  );
}

function DeployForm() {
  const { address, isConnected } = useAccount();
  const router = useRouter();
  const walletChainId = useChainId();
  const { switchChain, isPending: switching } = useSwitchChain();
  const { addInstance } = useInstanceContext();

  // Single-chain (classic) deploy on the wallet's current chain.
  const single = useDeployInstance();

  const [name, setName] = useState("");
  const [symbol, setSymbol] = useState("");
  // Pool (no token) vs classic token instance. POOL IS THE DEFAULT: most
  // communities just want a shared deposit pot, and a transferable ERC-20 is
  // the opt-in. The mode is NOT committed into the familyId, so a multi-chain
  // run keeps every sibling consistent by feeding this ONE flag to each
  // chain's deploy (see use-deploy-family) — consistency is enforced here.
  const [issueToken, setIssueToken] = useState(false);
  const [cycleSeconds, setCycleSeconds] = useState(0);
  const [owner, setOwner] = useState("");

  const [advanced, setAdvanced] = useState(false);
  const [maxPoints, setMaxPoints] = useState(MAX_POINTS.toString());
  const [customSalt, setCustomSalt] = useState("");

  // "Add a chain" flow: /app/deploy?family=<id> prefills the exact config of an
  // existing family so the deterministic familyId still matches. When set, the
  // salt and creator are LOCKED to the stored record (any drift = orphan family).
  const [extend, setExtend] = useState<{
    familyId: Hex;
    salt: Hex;
    creator: Address;
  } | null>(null);

  const [tokenImg, setTokenImg] = useState("");
  const [bannerImg, setBannerImg] = useState("");
  const tokenImgValid =
    tokenImg.trim() === "" || isValidImageUri(tokenImg.trim());
  const bannerImgValid =
    bannerImg.trim() === "" || isValidImageUri(bannerImg.trim());

  // Chain selection: preselect the wallet's chain (if deployable), else home.
  const [selectedChains, setSelectedChains] = useState<number[]>([]);
  const [multiReady, setMultiReady] = useState(false);
  useEffect(() => {
    const deployable = deployableChainIds();
    const preferred =
      isSupportedChain(walletChainId) && deployable.includes(walletChainId)
        ? walletChainId
        : (deployable[0] ?? DEFAULT_CHAIN_ID);
    setSelectedChains([preferred]);
  }, [walletChainId]);

  // "Add a chain": prefill from ?family=<id>. Client-only (static export) — read
  // the query the same way instance.ts does. Missing/unknown ids just no-op.
  useEffect(() => {
    if (typeof window === "undefined") return;
    const raw = new URLSearchParams(window.location.search).get("family");
    if (!raw) return;
    const record = loadFamilyDeployParams(raw as Hex);
    if (!record) return;
    const p = record.params;
    setName(p.tokenName);
    setSymbol(p.tokenSymbol);
    // Records saved before pool mode existed were all token deploys — a
    // missing flag means TRUE here (new deploys default to pool = false).
    setIssueToken(p.issueToken ?? true);
    setOwner(p.owner);
    setMaxPoints(p.maxVotingPoints);
    setCycleSeconds(p.cycleSeconds);
    setTokenImg(p.tokenImageURI);
    setBannerImg(p.bannerImageURI);
    setRegistryKind(p.registryKind === 1 ? "voting" : "admin");
    // Democratic families: founders + expiry are committed into the familyId
    // (votingFamilyIdOf) — dropping them here would mint an orphan family.
    if (p.registryKind === 1) {
      setFoundersText(p.initialRecipients.join(", "));
      setExpiryDays(String(Number(p.proposalExpiry) / 86400));
    }
    setDistributionKind(
      p.distributionKind === 1
        ? "equal"
        : p.distributionKind === 2
          ? "split"
          : "proportional",
    );
    setAdvanced(true);
    setMultiReady(true);
    setExtend({
      familyId: record.familyId,
      salt: record.salt,
      creator: p.creator,
    });
  }, []);

  const toggleChain = (chainId: number) =>
    setSelectedChains((prev) =>
      prev.includes(chainId)
        ? prev.filter((c) => c !== chainId)
        : [...prev, chainId],
    );

  // More than one chain (or the explicit toggle) makes it a cross-chain family.
  const isMultiChain = selectedChains.length > 1 || multiReady;

  // Recipient governance: registry kind, founding recipients, proposal window.
  // Democratic registries are now multi-chain viable — proposals and votes are
  // signed once and replayed cross-chain, and the founding cohort is committed
  // into the familyId so every sibling starts from the same electorate.
  const [registryKind, setRegistryKind] = useState<"admin" | "voting">("admin");
  const [foundersText, setFoundersText] = useState("");
  const [expiryDays, setExpiryDays] = useState("7");
  const democratic = registryKind === "voting";

  // Yield distribution: how each cycle's yield is split among recipients.
  const [distributionKind, setDistributionKind] = useState<
    "proportional" | "equal" | "split"
  >("proportional");
  const distributionCode =
    distributionKind === "equal" ? 1 : distributionKind === "split" ? 2 : 0;

  const ownerValue = (owner.trim() || address || "") as string;
  const cleanPoints = maxPoints.trim();
  const ownerValid = isAddress(ownerValue);
  const cycleValid = cycleSeconds > 0;
  const pointsValid =
    /^\d+$/.test(cleanPoints) && BigInt(cleanPoints || "0") > 0n;

  const typedFounders = foundersText
    .split(/[\s,]+/)
    .map((s) => s.trim())
    .filter(Boolean);
  const founders =
    typedFounders.length > 0 ? typedFounders : ownerValid ? [ownerValue] : [];
  const foundersValid =
    founders.length > 0 &&
    founders.every((f) => isAddress(f) && f.toLowerCase() !== zeroAddress) &&
    new Set(founders.map((f) => f.toLowerCase())).size === founders.length;
  const cleanExpiry = expiryDays.trim();
  const expiryValid = /^\d+$/.test(cleanExpiry) && Number(cleanExpiry) > 0;

  const registryCode = democratic ? 1 : 0;

  // Democratic families commit their founding cohort + expiry into the familyId
  // (and pass them to deploy); admin families use [] / 0 (byte-identical to old).
  // Memoized so the derived familyId/config don't churn every keystroke.
  const foundersKey = founders.join(",");
  const initialRecipients = useMemo<Address[]>(
    () => (democratic ? (founders as Address[]) : []),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [democratic, foundersKey],
  );
  const proposalExpirySeconds = useMemo(
    () =>
      democratic && expiryValid ? BigInt(Number(cleanExpiry) * 86400) : 0n,
    [democratic, expiryValid, cleanExpiry],
  );

  // Pool mode issues no token: the pool's symbol() is the UNDERLYING asset's
  // (WXDAI/USDC), so the wizard hides the symbol field and passes "" in the
  // struct — a deterministic value, keeping salts and familyIds stable.
  const effectiveSymbol = issueToken ? symbol.trim() : "";

  // Shared salt for the whole run — deterministic default, custom override.
  // When extending an existing family, the salt is LOCKED to the stored value so
  // the deterministic familyId matches its siblings.
  const salt = useMemo(() => {
    if (extend) return extend.salt;
    if (customSalt.trim()) return keccak256(toHex(customSalt.trim()));
    // A stable default keyed on the config so re-mounts don't reshuffle it, plus
    // per-form entropy so distinct deploys never collide on the factory CREATE2.
    return keccak256(
      toHex(`${name.trim()}|${effectiveSymbol}|${cycleSeconds}|${ownerValue}`),
    );
  }, [extend, customSalt, name, effectiveSymbol, cycleSeconds, ownerValue]);

  // familyId is CREATOR-scoped on-chain (CrowdStakeDeployer.deploy derives it
  // from msg.sender), so the creator dimension is the CONNECTED WALLET — never
  // the custom owner. A cross-chain deploy therefore requires a connected wallet.
  const familyId = useMemo(() => {
    if (!ownerValid || !address) return null;
    return familyIdForConfig({
      creator: address,
      salt,
      tokenName: name.trim(),
      tokenSymbol: effectiveSymbol,
      maxVotingPoints: pointsValid ? BigInt(cleanPoints) : 0n,
      registryKind: registryCode,
      distributionKind: distributionCode,
      initialRecipients,
      proposalExpiry: proposalExpirySeconds,
    });
  }, [
    ownerValid,
    address,
    salt,
    name,
    effectiveSymbol,
    pointsValid,
    cleanPoints,
    registryCode,
    distributionCode,
    initialRecipients,
    proposalExpirySeconds,
  ]);

  const familyConfig: FamilyDeployConfig | null = useMemo(() => {
    // A cross-chain deploy needs a connected wallet: familyId (and the CREATE2
    // base salt) are msg.sender-scoped on-chain, so `creator` MUST be the
    // connected wallet, independent of any custom owner override.
    if (!isMultiChain || !ownerValid || !address || selectedChains.length === 0)
      return null;
    return {
      creator: address,
      owner: ownerValue as Address,
      tokenName: name.trim(),
      tokenSymbol: effectiveSymbol,
      maxVotingPoints: pointsValid ? BigInt(cleanPoints) : 0n,
      registryKind: registryCode,
      distributionKind: distributionCode,
      initialRecipients,
      proposalExpiry: proposalExpirySeconds,
      tokenImageURI: tokenImg.trim(),
      bannerImageURI: bannerImg.trim(),
      issueToken,
      cycleSeconds,
      salt,
      chainIds: selectedChains,
      primaryChainId: selectedChains.includes(walletChainId)
        ? walletChainId
        : selectedChains[0],
    };
  }, [
    isMultiChain,
    ownerValid,
    address,
    ownerValue,
    name,
    effectiveSymbol,
    issueToken,
    pointsValid,
    cleanPoints,
    registryCode,
    distributionCode,
    initialRecipients,
    proposalExpirySeconds,
    tokenImg,
    bannerImg,
    cycleSeconds,
    salt,
    selectedChains,
    walletChainId,
  ]);

  const family = useDeployFamily(familyConfig);

  // Extending a family only works from the wallet that created it: familyId is
  // msg.sender-scoped, so a different signer would silently mint an orphan.
  const extendWalletMismatch =
    extend !== null &&
    isConnected &&
    address?.toLowerCase() !== extend.creator.toLowerCase();

  const commonValid =
    name.trim().length > 0 &&
    // Pools have no ticker of their own — the symbol field is hidden.
    (!issueToken || symbol.trim().length > 0) &&
    cycleValid &&
    pointsValid &&
    ownerValid &&
    tokenImgValid &&
    bannerImgValid &&
    selectedChains.length > 0 &&
    !extendWalletMismatch;

  const singleChainId = selectedChains[0] ?? DEFAULT_CHAIN_ID;
  const singleDeployable = Boolean(CHAINS[singleChainId]?.deployer);

  // Democratic deploys (single- or multi-chain) also need valid founders + expiry.
  const democraticValid = !democratic || (foundersValid && expiryValid);

  const canDeploySingle = commonValid && singleDeployable && democraticValid;

  // Family success (all deployed / partial) → dedicated card.
  if (isMultiChain && family.deployedCount > 0 && family.done) {
    return (
      <FamilySuccessCard
        deployedRows={family.deployedRows}
        chainCount={family.chainCount}
        primaryChainId={familyConfig?.primaryChainId ?? singleChainId}
      />
    );
  }

  // Single-chain success — the classic card.
  if (!isMultiChain && single.isSuccess && single.instance) {
    const inst = single.instance;
    return (
      <Card>
        <p className="text-system-green flex items-center gap-2">
          <CheckCircle size={22} weight="fill" />
          <span className="font-breadDisplay text-lg font-bold">
            Your instance is live!
          </span>
        </p>
        <Body className="text-surface-grey-2 mt-1 text-sm">
          Send the link below to your community — it opens straight into this
          instance, ready to deposit, vote, and watch the yield grow.
        </Body>

        <div className="mt-4">
          <InstanceShareCard
            distributionManager={inst.distributionManager}
            chainId={single.chainId}
          />
        </div>

        <Button
          app="fund"
          variant="primary"
          className="mt-4 w-full"
          rightIcon={<ArrowRight weight="bold" />}
          onClick={() => {
            addInstance({
              // Pools have no ticker — label them by community name.
              label:
                (issueToken ? symbol.trim() : name.trim()) || "New instance",
              chainId: single.chainId,
              addresses: inst,
            });
            router.push(
              instanceShareUrl(inst.distributionManager, single.chainId),
            );
          }}
        >
          Use this instance
        </Button>

        <details className="group mt-6">
          <summary className="text-surface-grey-2 hover:text-text-standard flex cursor-pointer items-center gap-1 text-sm font-medium select-none">
            <CaretRight
              size={14}
              weight="bold"
              className="transition-transform group-open:rotate-90"
            />
            Contract addresses
          </summary>
          <dl className="mt-3 space-y-2">
            {(
              [
                [issueToken ? "Token" : "Pool", inst.token],
                ["Distribution Manager", inst.distributionManager],
                ["Cycle Module", inst.cycleModule],
                ["Voting Module", inst.votingModule],
                ["Recipient Registry", inst.recipientRegistry],
                ["Distribution Strategy", inst.distributionStrategy],
                ["Voting Power Strategy", inst.votingPowerStrategy],
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
        </details>
      </Card>
    );
  }

  const onDeploySingle = () => {
    if (!canDeploySingle) return;
    // Classic deploys mix per-attempt entropy into the salt so re-deploying the
    // same config can't collide on the factory CREATE2 (Create2Failed).
    const classicSalt = customSalt.trim()
      ? keccak256(toHex(customSalt.trim()))
      : keccak256(
          toHex(
            `${name.trim()}|${effectiveSymbol}|${cycleSeconds}|${ownerValue}|${crypto.randomUUID()}`,
          ),
        );
    void single.deploy({
      owner: ownerValue as Address,
      cycleLength: durationToBlocks(
        cycleSeconds,
        CHAINS[singleChainId]?.blockTimeSeconds ?? 5,
      ),
      tokenName: name.trim(),
      tokenSymbol: effectiveSymbol,
      maxVotingPoints: BigInt(cleanPoints),
      salt: classicSalt,
      registryKind: registryCode,
      initialRecipients: democratic ? (founders as Address[]) : [],
      proposalExpiry: democratic ? BigInt(Number(cleanExpiry) * 86400) : 0n,
      distributionKind: distributionCode,
      tokenImageURI: tokenImg.trim(),
      bannerImageURI: bannerImg.trim(),
      crossChain: false,
      issueToken,
    });
  };

  return (
    <Card>
      <PendingFamilyResume onResume={() => setMultiReady(true)} />

      {extend && (
        <div className="border-core-orange/30 bg-core-orange/5 mb-4 rounded-xl border p-4">
          <Caption className="text-text-standard font-semibold">
            Extending {name.trim() || "your community"}
          </Caption>
          <Body className="text-surface-grey-2 mt-1 text-sm">
            Config is locked to the existing family so the new chain joins it.
            Pick the chain(s) to add below, then deploy from the creator wallet
            ({shortenAddress(extend.creator, 4)}).
          </Body>
          {extendWalletMismatch && (
            <Caption className="text-system-warning mt-2 block">
              Connected wallet doesn&apos;t match — switch to{" "}
              {shortenAddress(extend.creator, 4)} to extend this family.
            </Caption>
          )}
        </div>
      )}

      <div className="mb-4">
        <Caption className="text-surface-grey-2 mb-1.5 block">
          Staking mode
        </Caption>
        <div className="border-paper-2 inline-flex rounded-xl border p-1">
          {(
            [
              [false, "No token (pool)"],
              [true, "Issue a token"],
            ] as const
          ).map(([mode, label]) => (
            <button
              key={label}
              type="button"
              onClick={() => setIssueToken(mode)}
              className={`rounded-lg px-4 py-1.5 text-sm font-semibold transition-colors ${
                issueToken === mode
                  ? "bg-core-orange text-white"
                  : "text-surface-grey-2 hover:text-text-standard"
              }`}
            >
              {label}
            </button>
          ))}
        </div>
        <Caption className="text-surface-grey mt-1.5 block">
          {issueToken
            ? "Depositors receive a transferable ERC-20, redeemable 1:1 for the deposit asset."
            : "No token is issued — deposits are simply tracked, withdrawable any time."}
        </Caption>
      </div>

      <Field label={issueToken ? "Token name" : "Community name"}>
        <Input
          value={name}
          onChange={setName}
          placeholder="Acme Community Stake"
        />
      </Field>
      {issueToken && (
        <Field label="Token symbol">
          <Input value={symbol} onChange={setSymbol} placeholder="ACME" />
        </Field>
      )}

      <div className="mb-4">
        <Caption className="text-surface-grey-2 mb-1.5 block">Chains</Caption>
        <ChainSelect selected={selectedChains} onToggle={toggleChain} />
        {selectedChains.length === 1 && (
          <label className="text-surface-grey-2 mt-2 flex items-center gap-2 text-sm">
            <input
              type="checkbox"
              checked={multiReady}
              onChange={(e) => setMultiReady(e.target.checked)}
              className="accent-core-orange"
            />
            Make this a multi-chain community (add more chains later)
          </label>
        )}
        {isMultiChain && (
          <Caption className="text-surface-grey mt-1.5 block">
            Cross-chain community: one signed ballot lands on every chain, the
            same ballot weighted by each member&apos;s stake on each chain.
          </Caption>
        )}
      </div>

      <Field label="Cycle length">
        <DurationInput onChange={setCycleSeconds} />
        {cycleValid ? (
          <div className="mt-1 space-y-0.5">
            {selectedChains.map((chainId) => {
              const cfg = chainConfig(chainId);
              const blocks = durationToBlocks(
                cycleSeconds,
                cfg.blockTimeSeconds,
              );
              return (
                <Caption key={chainId} className="text-surface-grey block">
                  ≈ {blocks.toString()} blocks on {shortChainName(chainId)} (
                  {cfg.blockTimeSeconds}s/block)
                </Caption>
              );
            })}
          </div>
        ) : (
          cycleSeconds > 0 && (
            <Caption className="text-system-red mt-1 block">
              Enter a positive duration.
            </Caption>
          )
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
        {isMultiChain && democratic && (
          <Caption className="text-surface-grey mt-1.5 block">
            Cross-chain democratic community: the founding recipients are shared
            on every chain, and proposals + votes are signed once and replayed
            across chains — no per-chain re-signing.
          </Caption>
        )}
        {isMultiChain && !democratic && (
          <Caption className="text-surface-grey mt-1.5 block">
            Admin-managed recipients — sync the list across chains with one
            signature from the Admin page.
          </Caption>
        )}
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

      <div className="mb-4">
        <Caption className="text-surface-grey-2 mb-1.5 block">
          Yield distribution
        </Caption>
        <div className="border-paper-2 inline-flex flex-wrap rounded-xl border p-1">
          {(
            [
              ["proportional", "By votes"],
              ["equal", "Equally"],
              ["split", "Half & half"],
            ] as const
          ).map(([k, label]) => (
            <button
              key={k}
              type="button"
              onClick={() => setDistributionKind(k)}
              className={`rounded-lg px-4 py-1.5 text-sm font-semibold transition-colors ${
                distributionKind === k
                  ? "bg-core-orange text-white"
                  : "text-surface-grey-2 hover:text-text-standard"
              }`}
            >
              {label}
            </button>
          ))}
        </div>
        <Caption className="text-surface-grey mt-1.5 block">
          {distributionKind === "proportional"
            ? "Each cycle's yield is split in proportion to community votes. Recipients with more votes get more."
            : distributionKind === "equal"
              ? "Each cycle's yield is split evenly across all recipients, regardless of votes."
              : "Half of each cycle's yield is split by votes, the other half evenly across all recipients."}
        </Caption>
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
          <Field label="Shared CREATE2 salt (optional — deterministic address)">
            <Input
              value={customSalt}
              onChange={setCustomSalt}
              placeholder="leave blank for a fresh random salt"
              mono
            />
            <Caption className="text-surface-grey mt-1 block">
              Blank uses random entropy so repeat deploys never collide. A fixed
              value makes the instance address reproducible across chains.
            </Caption>
          </Field>
          {isMultiChain && familyId && (
            <div>
              <Caption className="text-surface-grey-2 block">Family ID</Caption>
              <Caption className="text-surface-grey mt-0.5 block font-mono break-all">
                {familyId}
              </Caption>
            </div>
          )}
        </div>
      )}

      {isMultiChain ? (
        <FamilyDeploySection
          canStart={commonValid && democraticValid && isConnected}
          needsWallet={!isConnected}
          family={family}
          cycleSeconds={cycleSeconds}
          onUseFamily={() => {
            const primaryChainId =
              familyConfig?.primaryChainId ?? singleChainId;
            // Pools have no ticker — label them by community name.
            const label =
              (issueToken ? symbol.trim() : name.trim()) || "New family";
            const withInstances = family.deployedRows.filter((r) => r.instance);
            const primary =
              withInstances.find((r) => r.chainId === primaryChainId) ??
              withInstances[0];
            if (!primary?.instance || !family.familyId) return;
            // Register every sibling with family metadata so the switcher groups
            // them; add the primary LAST so it becomes the active instance.
            for (const r of withInstances) {
              if (r.chainId === primary.chainId) continue;
              addInstance({
                label,
                chainId: r.chainId,
                addresses: r.instance!,
                familyId: family.familyId,
                primaryChainId,
              });
            }
            addInstance({
              label,
              chainId: primary.chainId,
              addresses: primary.instance,
              familyId: family.familyId,
              primaryChainId,
            });
            family.finish();
            router.push(
              instanceShareUrl(
                primary.instance.distributionManager,
                primary.chainId,
              ),
            );
          }}
        />
      ) : (
        <>
          {!singleDeployable && (
            <Caption className="text-system-warning mt-4 block">
              Deploys aren&apos;t available on {shortChainName(singleChainId)}{" "}
              yet — pick a supported chain.
            </Caption>
          )}
          <div className="mt-2">
            {isConnected && walletChainId !== singleChainId ? (
              // Classic deploy runs on the wallet's chain — switch it to the
              // selected chain first (ActionButton gates on the active INSTANCE
              // chain, which isn't the deploy target here).
              <Button
                app="fund"
                variant="primary"
                className="w-full"
                isLoading={switching}
                onClick={() => switchChain({ chainId: singleChainId })}
              >
                Switch to {shortChainName(singleChainId)}
              </Button>
            ) : (
              <ActionButton
                chainless
                isLoading={single.isBusy}
                disabled={!canDeploySingle}
                onClick={onDeploySingle}
              >
                Deploy instance
              </ActionButton>
            )}
          </div>
          <TxStatus
            status={single.status}
            hash={single.hash}
            error={single.error}
            successLabel="Instance deployed"
          />
          {single.isSuccess && !single.instance && (
            <Caption className="text-system-warning mt-2 block">
              The deploy transaction confirmed, but the instance addresses
              couldn&apos;t be decoded. Check the transaction, and don&apos;t
              re-submit (it may have already deployed).
            </Caption>
          )}
        </>
      )}

      <Body className="text-surface-grey mt-6 text-sm">
        Deploys the full system — {issueToken ? "token" : "deposit pool"}, cycle
        module, voting module + power, recipient registry, and a distribution
        manager — wired and owned by you. Yield is distributed{" "}
        {distributionKind === "proportional"
          ? "proportionally to community votes"
          : distributionKind === "equal"
            ? "equally across all recipients"
            : "half by votes and half equally"}
        .
      </Body>
    </Card>
  );
}

/** The cross-chain deploy checklist + start/finish controls. */
function FamilyDeploySection({
  canStart,
  needsWallet,
  family,
  cycleSeconds,
  onUseFamily,
}: {
  canStart: boolean;
  needsWallet: boolean;
  family: ReturnType<typeof useDeployFamily>;
  cycleSeconds: number;
  onUseFamily: () => void;
}) {
  const started = family.rows.some((r) => r.state !== "idle");
  return (
    <div className="mt-4">
      <Caption className="text-surface-grey-2 mb-2 block">
        Deploy on each chain — independently retryable, resumable anytime
      </Caption>
      {needsWallet && (
        <Caption className="text-system-warning mb-2 block">
          Connect a wallet to start — cross-chain deploys are keyed to the
          creating wallet, so every chain must be deployed from the same
          account.
        </Caption>
      )}
      <ChainChecklist
        rows={family.rows}
        cycleSeconds={cycleSeconds}
        busy={family.anyBusy}
        onDeploy={(c) => void family.deployChain(c)}
        onSkip={family.skipChain}
        onUnskip={family.unskipChain}
      />
      <div className="mt-4">
        <ActionButton
          chainless
          isLoading={family.anyBusy}
          disabled={!canStart || family.done}
          onClick={() => void family.deployAll()}
        >
          {started
            ? "Deploy remaining chains"
            : "Deploy on all selected chains"}
        </ActionButton>
      </div>
      {family.done && family.deployedCount > 0 && (
        <Button
          app="fund"
          variant="secondary"
          className="mt-3 w-full"
          rightIcon={<ArrowRight weight="bold" />}
          onClick={onUseFamily}
        >
          Use this community
        </Button>
      )}
    </div>
  );
}

/** Resume banner when a multi-chain deploy was left unfinished. */
function PendingFamilyResume({ onResume }: { onResume: () => void }) {
  const pending = usePendingFamily();
  const { address } = useAccount();
  if (!pending) return null;
  const remaining = Object.values(pending.chains).filter(
    (c) => c.status !== "deployed",
  ).length;
  if (remaining === 0) return null;
  const isCreator =
    Boolean(address) &&
    address?.toLowerCase() === pending.params.creator.toLowerCase();

  return (
    <div className="border-core-orange/30 bg-core-orange/5 mb-4 rounded-xl border p-4">
      <Caption className="text-text-standard font-semibold">
        Finish deploying {pending.params.tokenName || "your community"}
      </Caption>
      <Body className="text-surface-grey-2 mt-1 text-sm">
        {remaining} chain{remaining === 1 ? "" : "s"} left. Cross-chain deploys
        are creator-scoped — resume from the same wallet.
      </Body>
      {isCreator ? (
        <Button
          app="fund"
          variant="secondary"
          className="mt-3"
          onClick={onResume}
        >
          Resume
        </Button>
      ) : (
        <Caption className="text-system-warning mt-2 block">
          Connect the creator wallet (
          {shortenAddress(pending.params.creator, 4)}) to finish.
        </Caption>
      )}
    </div>
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
