"use client";

import { useEffect, useRef, useState } from "react";
import { isAddress, zeroAddress, type Address } from "viem";
import { useAccount } from "wagmi";
import { Body, Button, Caption } from "@breadcoop/ui";
import {
  Plus,
  Trash,
  ArrowsClockwise,
  X,
  CheckCircle,
  Globe,
} from "@phosphor-icons/react";
import {
  Card,
  EmptyState,
  PageHeader,
  ProgressBar,
} from "@/components/dapp/ui";
import { TxStatus } from "@/components/dapp/tx-status";
import {
  useClearQueue,
  useIsRecipient,
  useProcessQueue,
  useQueueRecipientAddition,
  useQueueRecipientRemoval,
  useRecipients,
  useRegistryOwner,
  useTransferAdmin,
} from "@/hooks/use-recipients";
import {
  useExecuteProposal,
  useProposalExpiry,
  useProposals,
  useProposalsMeta,
  useProposeRecipient,
  useRegistryKind,
  useSetProposalExpiry,
  useVoteOnProposal,
  type Proposal,
} from "@/hooks/use-recipient-voting";
import { shortenAddress } from "@/lib/format";
import { addressUrl, shortChainName } from "@/lib/chains";
import { useActiveChainId, useInstance } from "@/components/instance-provider";
import { publicClientFor } from "@/lib/instance";
import { recipientRegistryAbi } from "@/lib/abis";
import { useFamily, type FamilyState } from "@/hooks/use-family";
import { useCrossChainRegistryUpdate } from "@/hooks/use-cross-chain-registry-update";
import {
  useCrossChainProposals,
  useSiblingProposalExpiry,
  type CrossChainProposal,
} from "@/hooks/use-cross-chain-proposals";
import { MultiChainActionStatus } from "@/components/dapp/multi-chain-action-status";
import { GasModeNote } from "@/components/dapp/gas-mode-note";
import type { ChainActionRow } from "@/lib/cross-chain-action";

export default function RecipientsPage() {
  return (
    <div className="mx-auto max-w-2xl">
      <PageHeader
        title="Recipients"
        subtitle="Funding recipients receive distributed yield. How they change depends on the instance — admin-managed or democratically voted."
      />
      <RecipientsRouter />
    </div>
  );
}

/** Render the admin or democratic flow based on the instance's registry type. */
function RecipientsRouter() {
  const { kind, isLoading } = useRegistryKind();
  const family = useFamily();
  // familyId not yet known — hold the skeleton so we never flash the wrong mode.
  if (kind === "unknown" || isLoading || family.isLoading) {
    return (
      <Card>
        <Caption className="text-surface-grey-2">
          Detecting registry type…
        </Caption>
      </Card>
    );
  }
  if (kind === "voting") {
    // Democratic family instances propose + vote sign-once cross-chain; classic
    // democratic instances keep the single-chain flow unchanged.
    return family.isFamily ? (
      <FamilyDemocraticRecipients family={family} />
    ) : (
      <DemocraticRecipients />
    );
  }
  return <AdminRecipients family={family} />;
}

const lc = (a: string) => a.toLowerCase();
// The registry requires each queued change to be strictly ascending by
// uint160(address); sorting the batch client-side satisfies that invariant.
const sortAsc = (arr: Address[]) =>
  [...arr].sort((a, b) =>
    BigInt(a) < BigInt(b) ? -1 : BigInt(a) > BigInt(b) ? 1 : 0,
  );

/** Per-chain copy for the family auto-sync (same grammar as the Admin page). */
function syncStateLabel(row: ChainActionRow): string {
  switch (row.state) {
    case "confirmed":
      return "Synced";
    case "superseded":
      return "Superseded by a newer sync";
    case "recipient_mismatch":
      return "Recipient list out of sync";
    case "unreachable":
      return "Couldn't reach chain";
    case "failed":
      return row.error ?? "Delivery failed";
    case "submitted":
      return "Submitted — confirming…";
    case "relaying":
      return "Submitting…";
    case "signing":
      return "Waiting for your signature…";
    default:
      return "Waiting…";
  }
}

function AdminRecipients({ family }: { family: FamilyState }) {
  const chainId = useActiveChainId();
  const instance = useInstance();
  const { isConnected } = useAccount();
  const { isAdmin } = useRegistryOwner();
  const { recipients, queuedAdditions, queuedRemovals, refetch } =
    useRecipients();

  const [newAddr, setNewAddr] = useState("");
  const [pendingAdds, setPendingAdds] = useState<Address[]>([]);
  const [pendingRemoves, setPendingRemoves] = useState<Address[]>([]);

  const addTx = useQueueRecipientAddition();
  const removeTx = useQueueRecipientRemoval();
  const processTx = useProcessQueue();
  const clearTx = useClearQueue();
  const transferTx = useTransferAdmin();

  // Family auto-sync (admin registries — this component only renders for that
  // kind): after a local membership change lands, push the new set to every
  // sibling with the same sign-once flow as the Admin page's manual button.
  const sync = useCrossChainRegistryUpdate(family);
  const siblingCount = family.perChain.filter(
    (c) => c.status === "found" && c.chainId !== chainId,
  ).length;
  // Queuing adds/removes doesn't change getRecipients — membership only moves
  // on processQueue, so that's the sync trigger. Keyed on the tx hash so one
  // completed change fires exactly one sync.
  const lastSyncedHashRef = useRef<string | null>(null);
  useEffect(() => {
    if (!processTx.isSuccess || !processTx.hash) return;
    // A sign() already fanning out must finish first — re-entering swaps the
    // shared payload under its loop. isBusy is in the deps, so the skipped
    // sync fires as soon as the running one settles.
    if (sync.isBusy) return;
    if (!family.isFamily || siblingCount === 0 || !isAdmin) return;
    if (lastSyncedHashRef.current === processTx.hash) return;
    lastSyncedHashRef.current = processTx.hash;
    void (async () => {
      try {
        // Read the just-processed membership straight from the chain — the
        // wagmi cache may still hold the pre-process list.
        const fresh = await publicClientFor(chainId).readContract({
          address: instance.recipientRegistry,
          abi: recipientRegistryAbi,
          functionName: "getRecipients",
        });
        await sync.sign(fresh);
      } catch {
        /* best-effort — the Admin page's manual sync remains available */
      }
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [processTx.isSuccess, processTx.hash, sync.isBusy]);

  const knownAdds = new Set(
    [...recipients, ...queuedAdditions, ...pendingAdds].map(lc),
  );
  const addrValid = isAddress(newAddr) && lc(newAddr) !== zeroAddress;
  const addrDup = addrValid && knownAdds.has(lc(newAddr));

  const stageAdd = () => {
    if (!addrValid || addrDup) return;
    setPendingAdds((p) => [...p, newAddr as Address]);
    setNewAddr("");
  };
  const unstageAdd = (a: Address) =>
    setPendingAdds((p) => p.filter((x) => lc(x) !== lc(a)));
  const toggleRemove = (r: Address) =>
    setPendingRemoves((p) =>
      p.some((x) => lc(x) === lc(r))
        ? p.filter((x) => lc(x) !== lc(r))
        : [...p, r],
    );

  useEffect(() => {
    if (addTx.isSuccess) {
      refetch();
      setPendingAdds([]);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [addTx.isSuccess]);
  useEffect(() => {
    if (removeTx.isSuccess) {
      refetch();
      setPendingRemoves([]);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [removeTx.isSuccess]);
  useEffect(() => {
    if (processTx.isSuccess || clearTx.isSuccess || transferTx.isSuccess)
      refetch();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [processTx.isSuccess, clearTx.isSuccess, transferTx.isSuccess]);

  const additionQueueBusy = queuedAdditions.length > 0;
  const removalQueueBusy = queuedRemovals.length > 0;

  return (
    <div className="space-y-6">
      {!isConnected && (
        <Caption className="bg-paper-1 text-surface-grey-2 block rounded-lg px-4 py-3">
          You&apos;re viewing the public recipient registry. Connect as the
          registry admin to queue or process changes.
        </Caption>
      )}
      {isConnected && !isAdmin && (
        <Caption className="bg-paper-1 text-surface-grey-2 block rounded-lg px-4 py-3">
          You are viewing as a non-admin. Only the registry admin can queue or
          process recipient changes.
        </Caption>
      )}

      {/* Add recipients (staged locally, then queued as one sorted batch) */}
      {isAdmin && (
        <Card>
          <Caption className="text-surface-grey-2">Add recipients</Caption>
          <div className="mt-3 flex flex-col gap-3 sm:flex-row">
            <input
              placeholder="0x… recipient address"
              value={newAddr}
              onChange={(e) => setNewAddr(e.target.value)}
              onKeyDown={(e) => e.key === "Enter" && stageAdd()}
              className="border-paper-2 bg-paper-main text-text-standard focus:border-core-orange w-full rounded-xl border px-4 py-3 font-mono text-sm outline-none"
            />
            <Button
              app="fund"
              variant="secondary"
              leftIcon={<Plus weight="bold" />}
              onClick={stageAdd}
              {...(!addrValid || addrDup ? { disabled: true } : {})}
            >
              Add
            </Button>
          </div>
          {newAddr && !addrValid && (
            <Caption className="text-system-red mt-2 block">
              Not a valid address.
            </Caption>
          )}
          {addrDup && (
            <Caption className="text-system-warning mt-2 block">
              Already a recipient or staged.
            </Caption>
          )}

          {pendingAdds.length > 0 && (
            <div className="mt-4">
              <Caption className="text-surface-grey-2 mb-2 block">
                Staged additions ({pendingAdds.length})
              </Caption>
              <ul className="space-y-1.5">
                {pendingAdds.map((a) => (
                  <li
                    key={a}
                    className="bg-paper-1 flex items-center justify-between rounded-lg px-3 py-2"
                  >
                    <span className="text-system-green font-mono text-sm">
                      + {shortenAddress(a, 8)}
                    </span>
                    <button
                      onClick={() => unstageAdd(a)}
                      className="text-surface-grey hover:text-system-red"
                      aria-label="Remove from batch"
                    >
                      <X size={16} weight="bold" />
                    </button>
                  </li>
                ))}
              </ul>
              <Button
                app="fund"
                variant="primary"
                className="mt-3"
                isLoading={addTx.isBusy}
                onClick={() => addTx.queueMany(sortAsc(pendingAdds))}
                {...(additionQueueBusy ? { disabled: true } : {})}
              >
                Queue additions
              </Button>
              {additionQueueBusy && (
                <Caption className="text-system-warning mt-2 block">
                  Process or clear the pending additions below first.
                </Caption>
              )}
              <TxStatus
                status={addTx.status}
                hash={addTx.hash}
                error={addTx.error}
                successLabel="Additions queued"
              />
            </div>
          )}
        </Card>
      )}

      {/* Active recipients */}
      <div>
        <Caption className="text-surface-grey-2 mb-3 block">
          Active recipients ({recipients.length})
        </Caption>
        {recipients.length === 0 ? (
          <EmptyState>No active recipients yet.</EmptyState>
        ) : (
          <div className="space-y-2">
            {recipients.map((r) => {
              const queuedForRemoval = queuedRemovals.some(
                (x) => lc(x) === lc(r),
              );
              const staged = pendingRemoves.some((x) => lc(x) === lc(r));
              return (
                <Card
                  key={r}
                  className="flex items-center justify-between py-3"
                >
                  <a
                    href={addressUrl(r, chainId)}
                    target="_blank"
                    rel="noreferrer"
                    className="text-text-standard hover:text-core-orange font-mono text-sm"
                  >
                    {shortenAddress(r, 8)}
                  </a>
                  {isAdmin &&
                    (queuedForRemoval ? (
                      <Caption className="text-system-warning">
                        Queued for removal
                      </Caption>
                    ) : (
                      <Button
                        app="fund"
                        variant={staged ? "secondary" : "destructive"}
                        size="sm"
                        leftIcon={staged ? undefined : <Trash />}
                        onClick={() => toggleRemove(r)}
                      >
                        {staged ? "Undo" : "Remove"}
                      </Button>
                    ))}
                </Card>
              );
            })}
          </div>
        )}
        {isAdmin && pendingRemoves.length > 0 && (
          <div className="mt-3">
            <Button
              app="fund"
              variant="primary"
              isLoading={removeTx.isBusy}
              onClick={() => removeTx.queueMany(sortAsc(pendingRemoves))}
              {...(removalQueueBusy ? { disabled: true } : {})}
            >
              Queue {pendingRemoves.length} removal
              {pendingRemoves.length > 1 ? "s" : ""}
            </Button>
            {removalQueueBusy && (
              <Caption className="text-system-warning mt-2 block">
                Process or clear the pending removals below first.
              </Caption>
            )}
            <TxStatus
              status={removeTx.status}
              hash={removeTx.hash}
              error={removeTx.error}
              successLabel="Removals queued"
            />
          </div>
        )}
      </div>

      {/* Pending on-chain queue */}
      {(queuedAdditions.length > 0 || queuedRemovals.length > 0) && (
        <Card className="border-core-orange/40 bg-core-orange/5">
          <Caption className="text-surface-grey-2">Pending changes</Caption>
          <ul className="mt-2 space-y-1">
            {queuedAdditions.map((a) => (
              <li
                key={`a-${a}`}
                className="text-system-green font-mono text-sm"
              >
                + {shortenAddress(a, 8)}
              </li>
            ))}
            {queuedRemovals.map((a) => (
              <li key={`r-${a}`} className="text-system-red font-mono text-sm">
                − {shortenAddress(a, 8)}
              </li>
            ))}
          </ul>
          {isAdmin && (
            <>
              <div className="mt-4 flex flex-wrap gap-2">
                <Button
                  app="fund"
                  variant="primary"
                  leftIcon={<ArrowsClockwise weight="bold" />}
                  isLoading={processTx.isBusy}
                  onClick={() => processTx.process()}
                >
                  Process queue
                </Button>
                {queuedAdditions.length > 0 && (
                  <Button
                    app="fund"
                    variant="secondary"
                    isLoading={clearTx.isBusy}
                    onClick={() => clearTx.clearAdditions()}
                  >
                    Clear additions
                  </Button>
                )}
                {queuedRemovals.length > 0 && (
                  <Button
                    app="fund"
                    variant="secondary"
                    isLoading={clearTx.isBusy}
                    onClick={() => clearTx.clearRemovals()}
                  >
                    Clear removals
                  </Button>
                )}
              </div>
              <TxStatus
                status={processTx.status}
                hash={processTx.hash}
                error={processTx.error}
                successLabel="Queue processed"
              />
              <TxStatus
                status={clearTx.status}
                hash={clearTx.hash}
                error={clearTx.error}
                successLabel="Queue cleared"
              />
            </>
          )}
        </Card>
      )}

      {/* Family auto-sync delivery status. Local success stands on its own —
          a failed sibling delivery is shown (and retryable) without blocking. */}
      {(sync.phase !== "idle" || sync.error) && (
        <Card>
          <Caption className="text-text-standard flex items-center gap-1.5 font-semibold">
            <Globe size={16} weight="fill" className="text-core-orange" />
            Syncing recipients everywhere
          </Caption>
          {sync.isBusy && (
            <Caption className="text-surface-grey-2 mt-1 block">
              Syncing membership to {siblingCount} sibling chain
              {siblingCount === 1 ? "" : "s"}…
            </Caption>
          )}
          {sync.error && (
            <Caption className="text-system-red mt-2 block">
              {sync.error}
            </Caption>
          )}
          <MultiChainActionStatus
            rows={sync.rows}
            phase={sync.phase}
            submitting={sync.submitting}
            payload={sync.payload}
            onSubmitOnChain={sync.submitOnChain}
            onRetryFailed={sync.retryFailed}
            copy={{
              stateLabel: syncStateLabel,
              aggregate: ({ counted, total, phase }) =>
                phase === "signing"
                  ? "Confirm in your wallet…"
                  : phase === "done"
                    ? `Synced on ${counted} of ${total} chain${
                        total === 1 ? "" : "s"
                      }`
                    : `Syncing ${total} chain${total === 1 ? "" : "s"}…`,
              copyLabel: "Copy signed sync",
              copyHint: "Anyone can deliver this — paste it to your community.",
            }}
          />
        </Card>
      )}

      {isAdmin && <TransferAdmin transferTx={transferTx} />}

      <Body className="text-surface-grey text-sm">
        Note: queued changes only take effect after “Process queue”. Recipients
        must be active before they appear on the vote page.
      </Body>
    </div>
  );
}

function TransferAdmin({
  transferTx,
}: {
  transferTx: ReturnType<typeof useTransferAdmin>;
}) {
  const [addr, setAddr] = useState("");
  const valid = isAddress(addr) && addr.toLowerCase() !== zeroAddress;

  useEffect(() => {
    if (transferTx.isSuccess) setAddr("");
  }, [transferTx.isSuccess]);

  return (
    <Card>
      <Caption className="text-surface-grey-2">Transfer admin</Caption>
      <Body className="text-surface-grey mt-1 text-sm">
        Hand registry ownership to another address. This is irreversible — you
        lose admin control immediately.
      </Body>
      <div className="mt-3 flex gap-2">
        <input
          value={addr}
          onChange={(e) => setAddr(e.target.value)}
          placeholder="0x… new admin"
          className="border-paper-2 bg-paper-main text-text-standard focus:border-core-orange w-full rounded-xl border px-4 py-2.5 font-mono text-sm outline-none"
        />
        <Button
          app="fund"
          variant="destructive"
          isLoading={transferTx.isBusy}
          onClick={() => valid && transferTx.transferAdmin(addr as Address)}
          {...(!valid ? { disabled: true } : {})}
        >
          Transfer
        </Button>
      </div>
      <TxStatus
        status={transferTx.status}
        hash={transferTx.hash}
        error={transferTx.error}
        successLabel="Admin transferred"
      />
    </Card>
  );
}

/* ===================== Democratic (vote-controlled) ===================== */

function DemocraticRecipients() {
  const chainId = useActiveChainId();
  const { isConnected, address } = useAccount();
  const {
    recipients,
    queuedAdditions,
    queuedRemovals,
    refetch: refetchRecipients,
  } = useRecipients();
  const { isAdmin } = useRegistryOwner();
  const isRec = useIsRecipient();
  const amRecipient = Boolean(isRec.data);
  const { proposals, refetch: refetchProposals } = useProposals();
  const meta = useProposalsMeta(proposals, address);
  const expiry = useProposalExpiry();
  const propose = useProposeRecipient();
  const voteTx = useVoteOnProposal();
  const execTx = useExecuteProposal();
  const processTx = useProcessQueue();
  const clearTx = useClearQueue();

  const [newAddr, setNewAddr] = useState("");
  const valid = isAddress(newAddr) && lc(newAddr) !== zeroAddress;
  const dup = valid && recipients.some((r) => lc(r) === lc(newAddr));

  const refetchAll = () => {
    refetchProposals();
    refetchRecipients();
  };
  useEffect(() => {
    if (propose.isSuccess) {
      setNewAddr("");
      refetchAll();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [propose.isSuccess]);
  useEffect(() => {
    if (
      voteTx.isSuccess ||
      execTx.isSuccess ||
      processTx.isSuccess ||
      clearTx.isSuccess
    )
      refetchAll();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [
    voteTx.isSuccess,
    execTx.isSuccess,
    processTx.isSuccess,
    clearTx.isSuccess,
  ]);

  const now = Math.floor(Date.now() / 1000);
  const expirySec = expiry !== undefined ? Number(expiry) : undefined;
  const isExpired = (p: Proposal) =>
    expirySec !== undefined && now > Number(p.createdAt) + expirySec;
  const open = proposals.filter((p) => !p.executed && !isExpired(p));
  const resolved = proposals.filter((p) => p.executed || isExpired(p));
  const expiryDays = expirySec ? Math.round(expirySec / 86400) : null;

  return (
    <div className="space-y-6">
      <Caption className="bg-paper-1 text-surface-grey-2 block rounded-lg px-4 py-3">
        Democratic registry — current recipients vote to add (unanimous) or
        remove (everyone except the candidate).{" "}
        {expiryDays !== null && `Proposals expire after ${expiryDays} days. `}
        {isConnected &&
          !amRecipient &&
          "You can view proposals, but only recipients can propose or vote."}
        {!isConnected && "Connect as a recipient to propose and vote."}
      </Caption>

      <Card>
        <Caption className="text-surface-grey-2">
          Propose a new recipient
        </Caption>
        <div className="mt-3 flex flex-col gap-3 sm:flex-row">
          <input
            placeholder="0x… candidate address"
            value={newAddr}
            disabled={!amRecipient}
            onChange={(e) => setNewAddr(e.target.value)}
            className="border-paper-2 bg-paper-main text-text-standard focus:border-core-orange w-full rounded-xl border px-4 py-3 font-mono text-sm outline-none disabled:opacity-50"
          />
          <Button
            app="fund"
            variant="primary"
            leftIcon={<Plus weight="bold" />}
            isLoading={propose.isBusy}
            onClick={() =>
              amRecipient &&
              valid &&
              !dup &&
              propose.proposeAdd(newAddr as Address)
            }
            {...(!amRecipient || !valid || dup ? { disabled: true } : {})}
          >
            Propose
          </Button>
        </div>
        {!amRecipient && (
          <Caption className="text-system-warning mt-2 block">
            {isConnected
              ? "Only current recipients can propose. You aren't a recipient of this instance yet."
              : "Connect as a current recipient to propose new members."}
          </Caption>
        )}
        {amRecipient && newAddr && !valid && (
          <Caption className="text-system-red mt-2 block">
            Not a valid address.
          </Caption>
        )}
        {amRecipient && dup && (
          <Caption className="text-system-warning mt-2 block">
            Already a recipient.
          </Caption>
        )}
        <Caption className="text-surface-grey mt-2 block">
          Adding a recipient needs all {recipients.length} current recipient
          {recipients.length === 1 ? "" : "s"} to vote — you auto-vote for your
          own proposal, and it applies once everyone has voted.
        </Caption>
        <TxStatus
          status={propose.status}
          hash={propose.hash}
          error={propose.error}
          successLabel="Proposal created"
        />
      </Card>

      <div>
        <Caption className="text-surface-grey-2 mb-3 block">
          Active recipients ({recipients.length})
        </Caption>
        {recipients.length === 0 ? (
          <EmptyState>No active recipients yet.</EmptyState>
        ) : (
          <div className="space-y-2">
            {recipients.map((r) => (
              <Card key={r} className="flex items-center justify-between py-3">
                <a
                  href={addressUrl(r, chainId)}
                  target="_blank"
                  rel="noreferrer"
                  className="text-text-standard hover:text-core-orange font-mono text-sm"
                >
                  {shortenAddress(r, 8)}
                </a>
                {amRecipient && address && lc(r) !== lc(address) && (
                  <Button
                    app="fund"
                    variant="destructive"
                    size="sm"
                    leftIcon={<Trash />}
                    isLoading={propose.isBusy}
                    onClick={() => propose.proposeRemove(r)}
                  >
                    Propose removal
                  </Button>
                )}
              </Card>
            ))}
          </div>
        )}
      </div>

      <div>
        <Caption className="text-surface-grey-2 mb-3 block">
          Open proposals ({open.length})
        </Caption>
        {open.length === 0 ? (
          <EmptyState>No open proposals.</EmptyState>
        ) : (
          <div className="space-y-3">
            {open.map((p) => (
              <ProposalCard
                key={p.id}
                p={p}
                meta={meta.get(p.id)}
                amRecipient={amRecipient}
                expirySec={expirySec}
                voteTx={voteTx}
                execTx={execTx}
              />
            ))}
          </div>
        )}
        {(voteTx.status !== "idle" || execTx.status !== "idle") && (
          <TxStatus
            status={execTx.status !== "idle" ? execTx.status : voteTx.status}
            hash={execTx.hash ?? voteTx.hash}
            error={execTx.error ?? voteTx.error}
            successLabel="Done"
          />
        )}
      </div>

      {(queuedAdditions.length > 0 || queuedRemovals.length > 0) && (
        <Card className="border-core-orange/40 bg-core-orange/5">
          <Caption className="text-surface-grey-2">
            Approved — pending application
          </Caption>
          <ul className="mt-2 space-y-1">
            {queuedAdditions.map((a) => (
              <li
                key={`a-${a}`}
                className="text-system-green font-mono text-sm"
              >
                + {shortenAddress(a, 8)}
              </li>
            ))}
            {queuedRemovals.map((a) => (
              <li key={`r-${a}`} className="text-system-red font-mono text-sm">
                − {shortenAddress(a, 8)}
              </li>
            ))}
          </ul>
          <Button
            app="fund"
            variant="primary"
            className="mt-4"
            leftIcon={<ArrowsClockwise weight="bold" />}
            isLoading={processTx.isBusy}
            onClick={() => processTx.process()}
          >
            Process queue
          </Button>
          <TxStatus
            status={processTx.status}
            hash={processTx.hash}
            error={processTx.error}
            successLabel="Applied"
          />
          <Caption className="text-surface-grey mt-2 block">
            Anyone can apply approved changes — new recipients then appear on
            the vote page.
          </Caption>
        </Card>
      )}

      {resolved.length > 0 && (
        <details>
          <summary className="text-surface-grey-2 hover:text-text-standard cursor-pointer text-sm font-medium">
            Resolved &amp; expired proposals ({resolved.length})
          </summary>
          <div className="mt-3 space-y-2">
            {resolved.map((p) => (
              <Card
                key={p.id}
                className="flex items-center justify-between py-2.5"
              >
                <a
                  href={addressUrl(p.candidate, chainId)}
                  target="_blank"
                  rel="noreferrer"
                  className="text-surface-grey-2 font-mono text-sm"
                >
                  {p.isAddition ? "+" : "−"} {shortenAddress(p.candidate, 6)}
                </a>
                <Caption
                  className={
                    p.executed ? "text-system-green" : "text-surface-grey"
                  }
                >
                  {p.executed ? "Executed" : "Expired"}
                </Caption>
              </Card>
            ))}
          </div>
        </details>
      )}

      {isAdmin && (
        <DemocraticAdmin
          expiry={expiry}
          clearTx={clearTx}
          queuedAdditions={queuedAdditions}
          queuedRemovals={queuedRemovals}
          onChanged={refetchAll}
        />
      )}
    </div>
  );
}

function ProposalCard({
  p,
  meta,
  amRecipient,
  expirySec,
  voteTx,
  execTx,
}: {
  p: Proposal;
  meta?: { hasVoted: boolean; eligible: boolean };
  amRecipient: boolean;
  expirySec?: number;
  voteTx: ReturnType<typeof useVoteOnProposal>;
  execTx: ReturnType<typeof useExecuteProposal>;
}) {
  const chainId = useActiveChainId();
  const pct =
    p.requiredVotes > 0n
      ? Number((p.voteCount * 1000n) / p.requiredVotes) / 1000
      : 0;
  const canExecute = p.voteCount >= p.requiredVotes;
  const now = Math.floor(Date.now() / 1000);
  const endsIn =
    expirySec !== undefined ? Number(p.createdAt) + expirySec - now : null;
  return (
    <Card>
      <div className="flex items-center justify-between">
        <a
          href={addressUrl(p.candidate, chainId)}
          target="_blank"
          rel="noreferrer"
          className="font-breadDisplay text-text-standard hover:text-core-orange font-bold"
        >
          {shortenAddress(p.candidate, 6)}
        </a>
        <span
          className={`rounded-full px-2 py-0.5 text-xs font-semibold ${
            p.isAddition
              ? "bg-system-green/10 text-system-green"
              : "bg-system-red/10 text-system-red"
          }`}
        >
          {p.isAddition ? "Add" : "Remove"}
        </span>
      </div>
      <div className="mt-3 flex items-center justify-between text-sm">
        <span className="text-text-standard font-semibold">
          {p.voteCount.toString()} / {p.requiredVotes.toString()} votes
        </span>
        {endsIn !== null && (
          <Caption className="text-surface-grey-2">
            {endsIn > 0 ? `${Math.ceil(endsIn / 86400)}d left` : "expired"}
          </Caption>
        )}
      </div>
      <div className="mt-2">
        <ProgressBar value={Math.min(1, pct)} />
      </div>
      <div className="mt-3">
        {canExecute ? (
          <Button
            app="fund"
            variant="primary"
            size="sm"
            isLoading={execTx.isBusy}
            onClick={() => execTx.execute(p.id)}
          >
            Execute
          </Button>
        ) : meta?.hasVoted ? (
          <Caption className="text-system-green flex items-center gap-1">
            <CheckCircle weight="fill" size={16} /> You voted
          </Caption>
        ) : !amRecipient ? (
          <Caption className="text-surface-grey">
            Only recipients can vote.
          </Caption>
        ) : !meta?.eligible ? (
          <Caption className="text-surface-grey">
            Not eligible — you joined after this proposal.
          </Caption>
        ) : (
          <Button
            app="fund"
            variant="primary"
            size="sm"
            isLoading={voteTx.isBusy}
            onClick={() => voteTx.vote(p.id)}
          >
            Vote
          </Button>
        )}
      </div>
    </Card>
  );
}

function DemocraticAdmin({
  expiry,
  clearTx,
  queuedAdditions,
  queuedRemovals,
  onChanged,
}: {
  expiry?: bigint;
  clearTx: ReturnType<typeof useClearQueue>;
  queuedAdditions: readonly Address[];
  queuedRemovals: readonly Address[];
  onChanged: () => void;
}) {
  const setExpiryTx = useSetProposalExpiry();
  const [days, setDays] = useState("");
  const valid = /^\d+$/.test(days.trim()) && Number(days.trim()) > 0;
  useEffect(() => {
    if (setExpiryTx.isSuccess) {
      setDays("");
      onChanged();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [setExpiryTx.isSuccess]);

  return (
    <Card>
      <Caption className="text-surface-grey-2">
        Registry admin (emergency)
      </Caption>
      <Body className="text-surface-grey mt-1 text-sm">
        The registry owner can tune the proposal window and clear a stuck queue,
        but cannot add or remove recipients directly — that requires recipient
        votes.
      </Body>
      <Caption className="text-surface-grey-2 mt-4 block">
        Proposal expiry (days)
      </Caption>
      <div className="mt-2 flex gap-2">
        <input
          value={days}
          onChange={(e) => setDays(e.target.value)}
          placeholder={
            expiry ? String(Math.round(Number(expiry) / 86400)) : "7"
          }
          className="border-paper-2 bg-paper-main text-text-standard focus:border-core-orange w-full rounded-xl border px-4 py-2.5 outline-none"
        />
        <Button
          app="fund"
          variant="secondary"
          isLoading={setExpiryTx.isBusy}
          onClick={() =>
            valid && setExpiryTx.setExpiry(BigInt(Number(days.trim()) * 86400))
          }
          {...(!valid ? { disabled: true } : {})}
        >
          Update
        </Button>
      </div>
      <TxStatus
        status={setExpiryTx.status}
        hash={setExpiryTx.hash}
        error={setExpiryTx.error}
        successLabel="Expiry updated"
      />
      {(queuedAdditions.length > 0 || queuedRemovals.length > 0) && (
        <div className="mt-4 flex flex-wrap gap-2">
          {queuedAdditions.length > 0 && (
            <Button
              app="fund"
              variant="secondary"
              size="sm"
              isLoading={clearTx.isBusy}
              onClick={() => clearTx.clearAdditions()}
            >
              Clear additions
            </Button>
          )}
          {queuedRemovals.length > 0 && (
            <Button
              app="fund"
              variant="secondary"
              size="sm"
              isLoading={clearTx.isBusy}
              onClick={() => clearTx.clearRemovals()}
            >
              Clear removals
            </Button>
          )}
        </div>
      )}
    </Card>
  );
}

/* ============ Democratic (family — sign-once cross-chain) ============ */

/** Human copy for each per-chain state of a cross-chain proposal / vote. */
function proposalStateLabel(row: ChainActionRow): string {
  switch (row.state) {
    case "confirmed":
      return "Landed";
    case "superseded":
      return "Superseded";
    case "recipient_mismatch":
      return "Recipient list out of sync here";
    case "unreachable":
      return "Couldn't reach chain";
    case "failed":
      return row.error ?? "Delivery failed";
    case "submitted":
      return "Submitted — confirming…";
    case "relaying":
      return "Submitting…";
    case "signing":
      return "Waiting for your signature…";
    default:
      return "Waiting…";
  }
}

/**
 * Democratic recipient governance for a multi-chain family. Proposals and votes
 * are signed ONCE and replayed on every sibling chain (the proposalKey is the
 * EIP-712 struct hash, so the same proposal exists everywhere). The signed
 * electorate must match each chain's recipient set — drift is surfaced so the
 * admin can sync it first. Settlement is per chain, confirmed on-chain.
 */
function FamilyDemocraticRecipients({
  family,
}: {
  family: ReturnType<typeof useFamily>;
}) {
  const chainId = useActiveChainId();
  const { isConnected, address } = useAccount();
  const { recipients } = useRecipients();
  const isRec = useIsRecipient();
  const amRecipient = Boolean(isRec.data);
  const cc = useCrossChainProposals(family);
  const minExpiry = useSiblingProposalExpiry(family);

  const [newAddr, setNewAddr] = useState("");
  const valid = isAddress(newAddr) && lc(newAddr) !== zeroAddress;
  const dup = valid && recipients.some((r) => lc(r) === lc(newAddr));

  // Any sibling whose recipient membership differs blocks proposal delivery there.
  const anyDrift = family.perChain.some((c) => c.drift);
  const electorate = recipients as readonly Address[];

  // now + min(sibling proposalExpiry): the on-chain ceiling on every chain.
  const expiresAt =
    minExpiry !== undefined
      ? BigInt(Math.floor(Date.now() / 1000)) + minExpiry
      : undefined;
  const expiryDays =
    minExpiry !== undefined ? Math.round(Number(minExpiry) / 86400) : null;

  useEffect(() => {
    if (cc.phase === "done") {
      cc.refetch();
      family.refetch();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [cc.phase]);

  const canPropose =
    amRecipient && valid && !dup && !anyDrift && expiresAt !== undefined;

  const now = Math.floor(Date.now() / 1000);
  const isExpired = (p: CrossChainProposal) => now > Number(p.expiresAt);
  const open = cc.proposals.filter((p) => !p.executedAnywhere && !isExpired(p));
  const resolved = cc.proposals.filter(
    (p) => p.executedAnywhere || isExpired(p),
  );

  return (
    <div className="space-y-6">
      <Caption className="bg-paper-1 text-surface-grey-2 block rounded-lg px-4 py-3">
        Democratic multi-chain registry — recipients propose and vote to add
        (unanimous) or remove (everyone except the candidate). You sign once and
        it counts on every chain.{" "}
        {expiryDays !== null && `Proposals expire after ${expiryDays} days. `}
        {isConnected &&
          !amRecipient &&
          "You can view proposals, but only recipients can propose or vote."}
        {!isConnected && "Connect as a recipient to propose and vote."}
      </Caption>

      {anyDrift && (
        <Card className="border-system-warning/40 bg-system-warning/5">
          <Caption className="text-system-warning">
            Recipient lists are out of sync across chains
          </Caption>
          <Body className="text-surface-grey mt-1 text-sm">
            A cross-chain proposal only lands on a chain whose recipient set
            matches the signed electorate. Sync the memberships from the Admin
            page before proposing.
          </Body>
        </Card>
      )}

      <Card>
        <Caption className="text-surface-grey-2">
          Propose a new recipient
        </Caption>
        <div className="mt-3 flex flex-col gap-3 sm:flex-row">
          <input
            placeholder="0x… candidate address"
            value={newAddr}
            disabled={!amRecipient}
            onChange={(e) => setNewAddr(e.target.value)}
            className="border-paper-2 bg-paper-main text-text-standard focus:border-core-orange w-full rounded-xl border px-4 py-3 font-mono text-sm outline-none disabled:opacity-50"
          />
          <Button
            app="fund"
            variant="primary"
            leftIcon={<Plus weight="bold" />}
            isLoading={cc.isBusy && cc.actionKind === "proposal"}
            onClick={() =>
              canPropose &&
              expiresAt !== undefined &&
              cc.propose(newAddr as Address, true, electorate, expiresAt)
            }
            {...(!canPropose ? { disabled: true } : {})}
          >
            Propose
          </Button>
        </div>
        {amRecipient && (
          <div className="mt-2">
            <GasModeNote />
          </div>
        )}
        {!amRecipient && (
          <Caption className="text-system-warning mt-2 block">
            {isConnected
              ? "Only current recipients can propose. You aren't a recipient of this instance yet."
              : "Connect as a current recipient to propose new members."}
          </Caption>
        )}
        {amRecipient && newAddr && !valid && (
          <Caption className="text-system-red mt-2 block">
            Not a valid address.
          </Caption>
        )}
        {amRecipient && dup && (
          <Caption className="text-system-warning mt-2 block">
            Already a recipient.
          </Caption>
        )}
        <Caption className="text-surface-grey mt-2 block">
          One signature creates this proposal on every chain — adding needs all{" "}
          {recipients.length} current recipient
          {recipients.length === 1 ? "" : "s"} to vote (you auto-vote for your
          own proposal). Anyone can deliver a signed proposal or vote.
        </Caption>
      </Card>

      <div>
        <Caption className="text-surface-grey-2 mb-3 block">
          Active recipients ({recipients.length})
        </Caption>
        {recipients.length === 0 ? (
          <EmptyState>No active recipients yet.</EmptyState>
        ) : (
          <div className="space-y-2">
            {recipients.map((r) => (
              <Card key={r} className="flex items-center justify-between py-3">
                <a
                  href={addressUrl(r, chainId)}
                  target="_blank"
                  rel="noreferrer"
                  className="text-text-standard hover:text-core-orange font-mono text-sm"
                >
                  {shortenAddress(r, 8)}
                </a>
                {amRecipient && address && lc(r) !== lc(address) && (
                  <Button
                    app="fund"
                    variant="destructive"
                    size="sm"
                    leftIcon={<Trash />}
                    isLoading={cc.isBusy && cc.actionKind === "proposal"}
                    onClick={() =>
                      !anyDrift &&
                      expiresAt !== undefined &&
                      cc.propose(r, false, electorate, expiresAt)
                    }
                    {...(anyDrift || expiresAt === undefined
                      ? { disabled: true }
                      : {})}
                  >
                    Propose removal
                  </Button>
                )}
              </Card>
            ))}
          </div>
        )}
      </div>

      <div>
        <Caption className="text-surface-grey-2 mb-3 block">
          Open proposals ({open.length})
        </Caption>
        {open.length === 0 ? (
          <EmptyState>No open proposals.</EmptyState>
        ) : (
          <div className="space-y-3">
            {open.map((p) => (
              <CrossChainProposalCard
                key={p.proposalKey}
                p={p}
                amRecipient={amRecipient}
                busy={cc.isBusy && cc.actionKind === "proposal-vote"}
                onVote={() => cc.voteOnProposal(p.proposalKey)}
              />
            ))}
          </div>
        )}
      </div>

      <MultiChainActionStatus
        rows={cc.rows}
        phase={cc.phase}
        submitting={cc.submitting}
        payload={cc.payload}
        onSubmitOnChain={cc.submitOnChain}
        onRetryFailed={cc.retryFailed}
        copy={{
          stateLabel: proposalStateLabel,
          aggregate: ({ counted, total, phase }) =>
            phase === "signing"
              ? "Confirm in your wallet…"
              : phase === "done"
                ? `Landed on ${counted} of ${total} chain${
                    total === 1 ? "" : "s"
                  }`
                : `Submitting to ${total} chain${total === 1 ? "" : "s"}…`,
          copyLabel: "Copy signed payload",
          copyHint: "Anyone can deliver this — paste it to your community.",
        }}
      />

      {cc.error && (
        <Caption className="text-system-red block">{cc.error}</Caption>
      )}

      {resolved.length > 0 && (
        <details>
          <summary className="text-surface-grey-2 hover:text-text-standard cursor-pointer text-sm font-medium">
            Resolved &amp; expired proposals ({resolved.length})
          </summary>
          <div className="mt-3 space-y-2">
            {resolved.map((p) => (
              <Card
                key={p.proposalKey}
                className="flex items-center justify-between py-2.5"
              >
                <a
                  href={addressUrl(p.candidate, chainId)}
                  target="_blank"
                  rel="noreferrer"
                  className="text-surface-grey-2 font-mono text-sm"
                >
                  {p.isAddition ? "+" : "−"} {shortenAddress(p.candidate, 6)}
                </a>
                <Caption
                  className={
                    p.executedAnywhere
                      ? "text-system-green"
                      : "text-surface-grey"
                  }
                >
                  {p.executedAnywhere ? "Executed" : "Expired"}
                </Caption>
              </Card>
            ))}
          </div>
        </details>
      )}

      <Body className="text-surface-grey text-sm">
        Proposals and votes are chain-agnostic: one signature is replayed on
        every family chain. A proposal executes on each chain independently once
        it reaches the vote threshold there.
      </Body>
    </div>
  );
}

function CrossChainProposalCard({
  p,
  amRecipient,
  busy,
  onVote,
}: {
  p: CrossChainProposal;
  amRecipient: boolean;
  busy: boolean;
  onVote: () => void;
}) {
  const chainId = useActiveChainId();
  const pct =
    p.requiredVotes > 0n
      ? Number((p.voteCount * 1000n) / p.requiredVotes) / 1000
      : 0;
  const now = Math.floor(Date.now() / 1000);
  const endsIn = Number(p.expiresAt) - now;
  return (
    <Card>
      <div className="flex items-center justify-between">
        <a
          href={addressUrl(p.candidate, chainId)}
          target="_blank"
          rel="noreferrer"
          className="font-breadDisplay text-text-standard hover:text-core-orange font-bold"
        >
          {shortenAddress(p.candidate, 6)}
        </a>
        <span
          className={`rounded-full px-2 py-0.5 text-xs font-semibold ${
            p.isAddition
              ? "bg-system-green/10 text-system-green"
              : "bg-system-red/10 text-system-red"
          }`}
        >
          {p.isAddition ? "Add" : "Remove"}
        </span>
      </div>
      <div className="mt-3 flex items-center justify-between text-sm">
        <span className="text-text-standard font-semibold">
          {p.voteCount.toString()} / {p.requiredVotes.toString()} votes
        </span>
        <Caption className="text-surface-grey-2">
          {endsIn > 0 ? `${Math.ceil(endsIn / 86400)}d left` : "expired"}
        </Caption>
      </div>
      <div className="mt-2">
        <ProgressBar value={Math.min(1, pct)} />
      </div>

      {/* Per-chain landing status. */}
      <ul className="mt-3 space-y-1">
        {p.perChain.map((c) => (
          <li
            key={c.chainId}
            className="text-surface-grey-2 flex items-center justify-between text-xs"
          >
            <span>{shortChainName(c.chainId)}</span>
            <span>
              {!c.exists
                ? "not delivered yet"
                : c.executed
                  ? "executed"
                  : `${c.voteCount.toString()}/${c.requiredVotes.toString()} votes`}
            </span>
          </li>
        ))}
      </ul>

      <div className="mt-3">
        {p.votedHere ? (
          <Caption className="text-system-green flex items-center gap-1">
            <CheckCircle weight="fill" size={16} /> You voted
          </Caption>
        ) : !amRecipient ? (
          <Caption className="text-surface-grey">
            Only recipients can vote.
          </Caption>
        ) : !p.eligibleHere ? (
          <Caption className="text-surface-grey">
            Not eligible — you joined after this proposal.
          </Caption>
        ) : (
          <Button
            app="fund"
            variant="primary"
            size="sm"
            isLoading={busy}
            onClick={onVote}
          >
            Vote
          </Button>
        )}
      </div>
    </Card>
  );
}
