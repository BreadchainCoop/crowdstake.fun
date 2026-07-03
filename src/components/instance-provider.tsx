"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react";
import { usePathname } from "next/navigation";
import type { Address } from "viem";
import {
  CHAIN_PARAM,
  DEFAULT_INSTANCE,
  INSTANCE_PARAM,
  chainParam,
  instanceParam,
  loadActiveManager,
  loadKnownInstances,
  resolveInstance,
  saveActiveManager,
  saveKnownInstances,
  type InstanceAddresses,
  type KnownInstance,
} from "@/lib/instance";
import { DEFAULT_CHAIN_ID } from "@/lib/chains";
import { shortenAddress } from "@/lib/format";

interface InstanceContextValue {
  /** Active instance's contract addresses (what every hook reads from). */
  addresses: InstanceAddresses;
  /** The chain the active instance lives on (what every read hook targets). */
  chainId: number;
  /** Human label for the active instance. */
  label: string;
  /** All known instances (default + saved). */
  known: KnownInstance[];
  /** Activate a known instance by its distribution-manager address. */
  setActive: (distributionManager: Address) => void;
  /** Add (and activate) a newly discovered/deployed instance. */
  addInstance: (instance: KnownInstance) => void;
  /** Remove a custom instance (the built-in default can't be removed). */
  removeInstance: (distributionManager: Address) => void;
  /** True while a shared `?i=` link is being resolved on-chain. */
  resolving: boolean;
}

const InstanceContext = createContext<InstanceContextValue | null>(null);

const isDefaultManager = (dm: Address) =>
  dm.toLowerCase() ===
  DEFAULT_INSTANCE.addresses.distributionManager.toLowerCase();

export function InstanceProvider({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  const [known, setKnown] = useState<KnownInstance[]>([DEFAULT_INSTANCE]);
  const [activeManager, setActiveManager] = useState<Address>(
    DEFAULT_INSTANCE.addresses.distributionManager,
  );
  const [resolving, setResolving] = useState(false);
  // Only start syncing the URL after the initial param/localStorage hydration,
  // so the mount pass doesn't strip a shared `?i=` before we've honored it.
  const hydrated = useRef(false);

  // Hydrate on mount. Precedence: ?i= link > localStorage > default. An unknown
  // shared instance is resolved on-chain and added transparently. All window
  // access lives in this effect (static export prerenders this component).
  useEffect(() => {
    let cancelled = false;
    const loaded = loadKnownInstances();
    setKnown(loaded);

    const inList = (dm: Address) =>
      loaded.some(
        (i) =>
          i.addresses.distributionManager.toLowerCase() === dm.toLowerCase(),
      );

    // Switch to a distribution manager: activate if known, else resolve its
    // full instance on-chain (on `chainId`), remember it, then activate.
    const activate = async (dm: Address, chainId: number) => {
      if (inList(dm)) {
        if (cancelled) return;
        setActiveManager(dm);
        saveActiveManager(dm);
        return;
      }
      const addresses = await resolveInstance(dm, chainId); // may throw
      if (cancelled) return;
      const inst = { label: shortenAddress(dm, 4), chainId, addresses };
      setKnown((prev) => {
        const next = [...prev, inst];
        saveKnownInstances(next);
        return next;
      });
      setActiveManager(dm);
      saveActiveManager(dm);
    };

    const onApp =
      typeof window !== "undefined" && (pathname?.startsWith("/app") ?? false);

    void (async () => {
      // 1. Shared ?i= (&c=<chainId>) deep link.
      const shared = onApp ? instanceParam(window.location.search) : null;
      if (shared) {
        if (inList(shared)) {
          if (!cancelled) {
            setActiveManager(shared);
            saveActiveManager(shared);
          }
          return;
        }
        const cid = chainParam(window.location.search) ?? DEFAULT_CHAIN_ID;
        setResolving(true);
        try {
          await activate(shared, cid);
        } catch {
          /* unresolvable link — keep whatever's active */
        } finally {
          if (!cancelled) setResolving(false);
        }
        return;
      }

      // 2. localStorage, else the built-in default.
      const saved = loadActiveManager();
      if (saved && inList(saved) && !cancelled) setActiveManager(saved);
    })().finally(() => {
      hydrated.current = true;
    });

    return () => {
      cancelled = true;
    };
    // Runs once on mount; pathname is read only to gate the initial ?i= read.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const active = useMemo(
    () =>
      known.find(
        (i) =>
          i.addresses.distributionManager.toLowerCase() ===
          activeManager.toLowerCase(),
      ) ?? DEFAULT_INSTANCE,
    [known, activeManager],
  );

  // Keep the address bar in sync with the active instance so the current URL is
  // always a shareable deep link. The default instance uses the clean URL.
  useEffect(() => {
    if (typeof window === "undefined") return;
    if (!hydrated.current || resolving) return;
    if (!pathname?.startsWith("/app")) return;
    const url = new URL(window.location.href);
    const current = url.searchParams.get(INSTANCE_PARAM);
    const dm = active.addresses.distributionManager;
    if (isDefaultManager(dm)) {
      if (current === null && !url.searchParams.has(CHAIN_PARAM)) return;
      url.searchParams.delete(INSTANCE_PARAM);
      url.searchParams.delete(CHAIN_PARAM);
    } else {
      if (current && current.toLowerCase() === dm.toLowerCase()) return;
      url.searchParams.set(INSTANCE_PARAM, dm);
      // Non-default chains carry &c=; the home chain stays clean.
      if (active.chainId !== DEFAULT_CHAIN_ID) {
        url.searchParams.set(CHAIN_PARAM, String(active.chainId));
      } else {
        url.searchParams.delete(CHAIN_PARAM);
      }
    }
    window.history.replaceState(null, "", url);
  }, [active, pathname, resolving]);

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

  const removeInstance = useCallback((distributionManager: Address) => {
    const dm = distributionManager.toLowerCase();
    // Never remove the built-in default.
    if (dm === DEFAULT_INSTANCE.addresses.distributionManager.toLowerCase())
      return;
    setKnown((prev) => {
      const next = prev.filter(
        (i) => i.addresses.distributionManager.toLowerCase() !== dm,
      );
      saveKnownInstances(next);
      return next;
    });
    setActiveManager((cur) => {
      if (cur.toLowerCase() === dm) {
        const fallback = DEFAULT_INSTANCE.addresses.distributionManager;
        saveActiveManager(fallback);
        return fallback;
      }
      return cur;
    });
  }, []);

  const value = useMemo(
    () => ({
      addresses: active.addresses,
      chainId: active.chainId,
      label: active.label,
      known,
      setActive,
      addInstance,
      removeInstance,
      resolving,
    }),
    [active, known, setActive, addInstance, removeInstance, resolving],
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

/** The chain id every read hook should target (the active instance's chain). */
export function useActiveChainId(): number {
  return useInstanceContext().chainId;
}
