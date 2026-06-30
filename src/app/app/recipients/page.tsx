"use client";

import { useEffect, useState } from "react";
import { isAddress, zeroAddress, type Address } from "viem";
import { useAccount } from "wagmi";
import { Body, Button, Caption } from "@breadcoop/ui";
import { Plus, Trash, ArrowsClockwise, X } from "@phosphor-icons/react";
import { Card, EmptyState, PageHeader } from "@/components/dapp/ui";
import { TxStatus } from "@/components/dapp/tx-status";
import {
  useClearQueue,
  useProcessQueue,
  useQueueRecipientAddition,
  useQueueRecipientRemoval,
  useRecipients,
  useRegistryOwner,
  useTransferAdmin,
} from "@/hooks/use-recipients";
import { shortenAddress } from "@/lib/format";
import { addressUrl } from "@/lib/constants";

export default function RecipientsPage() {
  return (
    <div className="mx-auto max-w-2xl">
      <PageHeader
        title="Recipients"
        subtitle="Funding recipients receive distributed yield. Changes are queued, then applied with “Process queue”."
      />
      <Recipients />
    </div>
  );
}

const lc = (a: string) => a.toLowerCase();
// The registry requires each queued change to be strictly ascending by
// uint160(address); sorting the batch client-side satisfies that invariant.
const sortAsc = (arr: Address[]) =>
  [...arr].sort((a, b) =>
    BigInt(a) < BigInt(b) ? -1 : BigInt(a) > BigInt(b) ? 1 : 0,
  );

function Recipients() {
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
                    href={addressUrl(r)}
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
