"use client";

import { useState } from "react";
import { isAddress, type Address } from "viem";
import { CaretDown, Check, Plus, SpinnerGap, X } from "@phosphor-icons/react";
import { useInstanceContext } from "@/components/instance-provider";
import { DEFAULT_INSTANCE, resolveInstance } from "@/lib/instance";
import { shortenAddress } from "@/lib/format";
import { cn } from "@/lib/utils";

/** Pick the active CrowdStake instance, or add one by its distribution-manager address. */
export function InstanceSwitcher() {
  const { label, known, addresses, setActive, addInstance, removeInstance } =
    useInstanceContext();
  const defaultDm =
    DEFAULT_INSTANCE.addresses.distributionManager.toLowerCase();
  const [open, setOpen] = useState(false);
  const [addr, setAddr] = useState("");
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  const onAdd = async () => {
    if (!isAddress(addr)) {
      setErr("Not a valid address");
      return;
    }
    setBusy(true);
    setErr(null);
    try {
      const resolved = await resolveInstance(addr as Address);
      addInstance({ label: shortenAddress(addr, 4), addresses: resolved });
      setAddr("");
      setOpen(false);
    } catch {
      setErr("Could not resolve — is this a distribution manager?");
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="relative">
      <button
        onClick={() => setOpen((o) => !o)}
        className="border-paper-2 text-text-standard hover:border-core-orange flex max-w-[10rem] items-center gap-1 rounded-lg border px-2.5 py-1.5 text-sm font-medium"
      >
        <span className="truncate">{label}</span>
        <CaretDown size={14} className="text-surface-grey flex-none" />
      </button>

      {open && (
        <>
          <div className="fixed inset-0 z-40" onClick={() => setOpen(false)} />
          <div className="border-paper-2 bg-paper-0 absolute right-0 z-50 mt-2 w-72 rounded-xl border p-2 shadow-xl">
            <p className="text-surface-grey px-2 py-1 text-xs font-semibold">
              Instances
            </p>
            {known.map((inst) => {
              const dm = inst.addresses.distributionManager;
              const isActive =
                dm.toLowerCase() ===
                addresses.distributionManager.toLowerCase();
              const isDefault = dm.toLowerCase() === defaultDm;
              return (
                <div key={dm} className="flex items-center gap-1">
                  <button
                    onClick={() => {
                      setActive(dm);
                      setOpen(false);
                    }}
                    className={cn(
                      "hover:bg-paper-1 flex flex-1 items-center justify-between rounded-lg px-2 py-2 text-left text-sm",
                      isActive && "text-core-orange",
                    )}
                  >
                    <span className="truncate">{inst.label}</span>
                    {isActive && <Check size={16} weight="bold" />}
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
