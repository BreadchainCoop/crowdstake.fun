"use client";

import { useState } from "react";
import Link from "next/link";
import { useChainId } from "wagmi";
import { isAddress, type Address } from "viem";
import {
  CaretDown,
  Check,
  Copy,
  Plus,
  PlusCircle,
  SpinnerGap,
  X,
} from "@phosphor-icons/react";
import { useInstanceContext } from "@/components/instance-provider";
import { InstanceTokenBadge } from "@/components/dapp/instance-branding";
import {
  DEFAULT_INSTANCE,
  instanceShareUrl,
  resolveInstance,
} from "@/lib/instance";
import { DEFAULT_CHAIN_ID, isSupportedChain } from "@/lib/chains";
import { shortenAddress } from "@/lib/format";
import { cn, copyToClipboard } from "@/lib/utils";

/** A small colored disc showing an instance label's initial (list rows). */
function InitialDisc({ label }: { label: string }) {
  return (
    <div className="bg-core-orange/15 text-core-orange flex h-7 w-7 shrink-0 items-center justify-center rounded-full text-xs font-bold">
      {label.slice(0, 1).toUpperCase()}
    </div>
  );
}

/**
 * The active-instance selector — the app's "which community am I in" control.
 * Switch between known instances, add one by address, copy a shareable link for
 * any instance, or deploy a new one.
 */
export function InstanceSwitcher() {
  const {
    label,
    known,
    addresses,
    setActive,
    addInstance,
    removeInstance,
    resolving,
  } = useInstanceContext();
  const defaultDm =
    DEFAULT_INSTANCE.addresses.distributionManager.toLowerCase();
  // Add "by address" resolves on the wallet's connected chain (else home chain).
  const walletChainId = useChainId();
  const addChainId = isSupportedChain(walletChainId)
    ? walletChainId
    : DEFAULT_CHAIN_ID;
  const [open, setOpen] = useState(false);
  const [addr, setAddr] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [copied, setCopied] = useState<string | null>(null);

  const onAdd = async () => {
    if (!isAddress(addr)) {
      setErr("Not a valid address");
      return;
    }
    setBusy(true);
    setErr(null);
    try {
      const resolved = await resolveInstance(addr as Address, addChainId);
      addInstance({
        label: shortenAddress(addr, 4),
        chainId: addChainId,
        addresses: resolved,
      });
      setAddr("");
      setOpen(false);
    } catch {
      setErr("Could not resolve — is this a distribution manager?");
    } finally {
      setBusy(false);
    }
  };

  const onCopy = async (dm: Address, chainId: number) => {
    if (await copyToClipboard(instanceShareUrl(dm, chainId))) {
      setCopied(dm.toLowerCase());
      setTimeout(() => setCopied(null), 1600);
    }
  };

  return (
    <div className="relative">
      <button
        onClick={() => setOpen((o) => !o)}
        className="border-paper-2 text-text-standard hover:border-core-orange flex max-w-[13rem] items-center gap-2 rounded-lg border py-1 pr-2 pl-1 text-sm font-medium"
      >
        {resolving ? (
          <SpinnerGap size={22} className="text-core-orange animate-spin" />
        ) : (
          <InstanceTokenBadge className="h-7 w-7" />
        )}
        <span className="min-w-0 truncate">
          {resolving ? "Loading…" : label}
        </span>
        <CaretDown size={14} className="text-surface-grey flex-none" />
      </button>

      {open && (
        <>
          <div className="fixed inset-0 z-40" onClick={() => setOpen(false)} />
          <div className="border-paper-2 bg-paper-0 absolute left-0 z-50 mt-2 w-80 max-w-[calc(100vw-2rem)] rounded-xl border p-2 shadow-xl">
            <p className="text-surface-grey px-2 py-1 text-xs font-semibold">
              Your instances
            </p>
            {known.map((inst) => {
              const dm = inst.addresses.distributionManager;
              const isActive =
                dm.toLowerCase() ===
                addresses.distributionManager.toLowerCase();
              const isDefault = dm.toLowerCase() === defaultDm;
              const isCopied = copied === dm.toLowerCase();
              return (
                <div
                  key={dm}
                  className={cn(
                    "group hover:bg-paper-1 flex items-center gap-1 rounded-lg px-1.5 py-1.5",
                    isActive && "bg-paper-1",
                  )}
                >
                  <button
                    onClick={() => {
                      setActive(dm);
                      setOpen(false);
                    }}
                    className="flex min-w-0 flex-1 items-center gap-2 text-left"
                  >
                    <InitialDisc label={inst.label} />
                    <span className="min-w-0">
                      <span
                        className={cn(
                          "block truncate text-sm",
                          isActive
                            ? "text-core-orange font-semibold"
                            : "text-text-standard",
                        )}
                      >
                        {inst.label}
                      </span>
                      <span className="text-surface-grey block truncate font-mono text-[11px]">
                        {shortenAddress(dm, 4)}
                      </span>
                    </span>
                    {isActive && (
                      <Check
                        size={16}
                        weight="bold"
                        className="text-core-orange flex-none"
                      />
                    )}
                  </button>
                  <button
                    onClick={() => onCopy(dm, inst.chainId)}
                    aria-label="Copy shareable link"
                    title="Copy shareable link"
                    className={cn(
                      "flex-none rounded p-1.5",
                      isCopied
                        ? "text-system-green"
                        : "text-surface-grey hover:text-text-standard",
                    )}
                  >
                    {isCopied ? (
                      <Check size={14} weight="bold" />
                    ) : (
                      <Copy size={14} />
                    )}
                  </button>
                  {!isDefault && (
                    <button
                      onClick={() => removeInstance(dm)}
                      aria-label="Remove instance"
                      className="text-surface-grey hover:text-system-red flex-none rounded p-1.5"
                    >
                      <X size={14} weight="bold" />
                    </button>
                  )}
                </div>
              );
            })}

            <Link
              href="/app/deploy"
              onClick={() => setOpen(false)}
              className="text-core-orange hover:bg-paper-1 mt-1 flex items-center gap-2 rounded-lg px-2 py-2 text-sm font-semibold"
            >
              <PlusCircle size={18} weight="bold" />
              Deploy a new instance
            </Link>

            <div className="border-paper-2 mt-2 border-t pt-2">
              <p className="text-surface-grey px-2 pb-1 text-xs font-semibold">
                Add by distribution manager
              </p>
              <div className="flex gap-1.5 px-1">
                <input
                  value={addr}
                  onChange={(e) => setAddr(e.target.value)}
                  placeholder="0x…"
                  className="border-paper-2 bg-paper-main text-text-standard focus:border-core-orange w-full rounded-lg border px-2 py-1.5 font-mono text-xs outline-none"
                />
                <button
                  onClick={onAdd}
                  disabled={busy}
                  className="bg-core-orange flex flex-none items-center rounded-lg px-2 text-white disabled:opacity-50"
                >
                  {busy ? (
                    <SpinnerGap size={16} className="animate-spin" />
                  ) : (
                    <Plus size={16} weight="bold" />
                  )}
                </button>
              </div>
              {err && (
                <p className="text-system-red px-2 pt-1 text-xs">{err}</p>
              )}
            </div>
          </div>
        </>
      )}
    </div>
  );
}
