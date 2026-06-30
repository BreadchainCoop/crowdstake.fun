"use client";

import { useEffect, useState } from "react";
import { isAddress, type Address } from "viem";
import { Body, Button, Caption } from "@breadcoop/ui";
import { Plus, Trash, ArrowsClockwise } from "@phosphor-icons/react";
import { Card, EmptyState, PageHeader } from "@/components/dapp/ui";
import { ConnectGate } from "@/components/dapp/connect-gate";
import { TxStatus } from "@/components/dapp/tx-status";
import {
  useProcessQueue,
  useQueueRecipientAddition,
  useQueueRecipientRemoval,
  useRecipients,
  useRegistryOwner,
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
      <ConnectGate>
        <Recipients />
      </ConnectGate>
    </div>
  );
}

function Recipients() {
  const { isAdmin } = useRegistryOwner();
  const { recipients, queuedAdditions, queuedRemovals, refetch } =
    useRecipients();
  const [newAddr, setNewAddr] = useState("");

  const addTx = useQueueRecipientAddition();
  const removeTx = useQueueRecipientRemoval();
  const processTx = useProcessQueue();

  const valid = isAddress(newAddr);
  const alreadyKnown =
    valid &&
    [...recipients, ...queuedAdditions].some(
      (r) => r.toLowerCase() === newAddr.toLowerCase(),
    );

  useEffect(() => {
    if (addTx.isSuccess || removeTx.isSuccess || processTx.isSuccess) {
      refetch();
      if (addTx.isSuccess) setNewAddr("");
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [addTx.isSuccess, removeTx.isSuccess, processTx.isSuccess]);

  return (
    <div className="space-y-6">
      {!isAdmin && (
        <Caption className="bg-paper-1 text-surface-grey-2 block rounded-lg px-4 py-3">
          You are viewing as a non-admin. Only the registry admin can queue or
          process recipient changes.
        </Caption>
      )}

      {isAdmin && (
        <Card>
          <Caption className="text-surface-grey-2">Add a recipient</Caption>
          <div className="mt-3 flex flex-col gap-3 sm:flex-row">
            <input
              placeholder="0x… recipient address"
              value={newAddr}
              onChange={(e) => setNewAddr(e.target.value)}
              className="border-paper-2 bg-paper-main text-text-standard focus:border-core-orange w-full rounded-xl border px-4 py-3 font-mono text-sm outline-none"
            />
            <Button
              app="fund"
              variant="primary"
              leftIcon={<Plus weight="bold" />}
              isLoading={addTx.isBusy}
              onClick={() => valid && addTx.queue(newAddr as Address)}
              {...(!valid || alreadyKnown ? { disabled: true } : {})}
            >
              Queue
            </Button>
          </div>
          {newAddr && !valid && (
            <Caption className="text-system-red mt-2 block">
              Not a valid address.
            </Caption>
          )}
          {alreadyKnown && (
            <Caption className="text-system-warning mt-2 block">
              Already a recipient or queued.
            </Caption>
          )}
          <TxStatus
            status={addTx.status}
            hash={addTx.hash}
            error={addTx.error}
            successLabel="Queued for addition"
          />
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
                (x) => x.toLowerCase() === r.toLowerCase(),
              );
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
                        variant="destructive"
                        size="sm"
                        leftIcon={<Trash />}
                        isLoading={removeTx.isBusy}
                        onClick={() => removeTx.queue(r)}
                      >
                        Remove
                      </Button>
                    ))}
                </Card>
              );
            })}
          </div>
        )}
      </div>

      {/* Pending queue */}
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
                successLabel="Queue processed"
              />
            </>
          )}
        </Card>
      )}

      <Body className="text-surface-grey text-sm">
        Note: queued changes only take effect after “Process queue”. Recipients
        must be active before they appear on the vote page.
      </Body>
    </div>
  );
}
