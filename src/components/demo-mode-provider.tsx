"use client";

import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import { formatAmount } from "@/lib/format";
import { useInstanceToken } from "@/hooks/use-token";

/**
 * Demo mode: a DISPLAY-ONLY ×1000 multiplier on shown token amounts, so a tiny
 * real mint reads as big balances and the (real, tiny) yield is visible. It
 * NEVER scales inputs or transaction amounts — you still mint/withdraw the exact
 * value you type; only the rendered numbers are multiplied.
 */
const KEY = "crowdstake.demoMode.v1";
export const DEMO_MULTIPLIER = 1000n;

const DemoModeContext = createContext<{
  demo: boolean;
  setDemo: (v: boolean) => void;
}>({ demo: false, setDemo: () => {} });

export function DemoModeProvider({ children }: { children: ReactNode }) {
  const [demo, setDemoState] = useState(false);

  useEffect(() => {
    try {
      setDemoState(window.localStorage.getItem(KEY) === "1");
    } catch {
      /* ignore */
    }
  }, []);

  const value = useMemo(
    () => ({
      demo,
      setDemo: (v: boolean) => {
        setDemoState(v);
        try {
          window.localStorage.setItem(KEY, v ? "1" : "0");
        } catch {
          /* ignore */
        }
      },
    }),
    [demo],
  );

  return (
    <DemoModeContext.Provider value={value}>
      {children}
    </DemoModeContext.Provider>
  );
}

export function useDemoMode() {
  return useContext(DemoModeContext);
}

/**
 * Returns a token-amount formatter that applies the demo multiplier when demo
 * mode is on. Use everywhere a project-token amount is *displayed* (not typed).
 */
export function useAmountFormatter(): (value?: bigint) => string {
  const { demo } = useDemoMode();
  // Format in the active instance token's decimals (18 native, 6 for USDC).
  const { decimals } = useInstanceToken();
  return (value?: bigint) =>
    value === undefined || value === null
      ? formatAmount(value, 4, decimals)
      : formatAmount(demo ? value * DEMO_MULTIPLIER : value, 4, decimals);
}
