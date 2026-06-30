"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import type { Address } from "viem";
import {
  DEFAULT_INSTANCE,
  loadActiveManager,
  loadKnownInstances,
  saveActiveManager,
  saveKnownInstances,
  type InstanceAddresses,
  type KnownInstance,
} from "@/lib/instance";

interface InstanceContextValue {
  /** Active instance's contract addresses (what every hook reads from). */
  addresses: InstanceAddresses;
  /** Human label for the active instance. */
  label: string;
  /** All known instances (default + saved). */
  known: KnownInstance[];
  /** Activate a known instance by its distribution-manager address. */
  setActive: (distributionManager: Address) => void;
  /** Add (and activate) a newly discovered/deployed instance. */
  addInstance: (instance: KnownInstance) => void;
}

const InstanceContext = createContext<InstanceContextValue | null>(null);

export function InstanceProvider({ children }: { children: ReactNode }) {
  const [known, setKnown] = useState<KnownInstance[]>([DEFAULT_INSTANCE]);
  const [activeManager, setActiveManager] = useState<Address>(
    DEFAULT_INSTANCE.addresses.distributionManager,
  );

  // Hydrate from localStorage (client only — static export safe).
  useEffect(() => {
    const loaded = loadKnownInstances();
    setKnown(loaded);
    const saved = loadActiveManager();
    if (
      saved &&
      loaded.some((i) => i.addresses.distributionManager === saved)
    ) {
      setActiveManager(saved);
    }
  }, []);

  const active = useMemo(
    () =>
      known.find((i) => i.addresses.distributionManager === activeManager) ??
      DEFAULT_INSTANCE,
    [known, activeManager],
  );

  const setActive = useCallback((distributionManager: Address) => {
    setActiveManager(distributionManager);
    saveActiveManager(distributionManager);
  }, []);

  const addInstance = useCallback((instance: KnownInstance) => {
    setKnown((prev) => {
      const exists = prev.some(
        (i) =>
          i.addresses.distributionManager.toLowerCase() ===
          instance.addresses.distributionManager.toLowerCase(),
      );
      const next = exists ? prev : [...prev, instance];
      saveKnownInstances(next);
      return next;
    });
    setActiveManager(instance.addresses.distributionManager);
    saveActiveManager(instance.addresses.distributionManager);
  }, []);

  const value = useMemo(
    () => ({
      addresses: active.addresses,
      label: active.label,
      known,
      setActive,
      addInstance,
    }),
    [active, known, setActive, addInstance],
  );

  return (
    <InstanceContext.Provider value={value}>
      {children}
    </InstanceContext.Provider>
  );
}

/** Full instance context (addresses + switching). */
export function useInstanceContext(): InstanceContextValue {
  const ctx = useContext(InstanceContext);
  if (!ctx)
    throw new Error("useInstanceContext must be used within InstanceProvider");
  return ctx;
}

/** Active instance addresses — the common case used by data hooks. */
export function useInstance(): InstanceAddresses {
  return useInstanceContext().addresses;
}
