"use client";

import {
  createContext,
  useContext,
  useEffect,
  useState,
  type ReactNode,
} from "react";
import { usePathname, useRouter } from "next/navigation";
import {
  isTelegramMiniApp,
  telegramWebApp,
  type TelegramWebApp,
} from "@/lib/telegram";

/** paper-main — keep Telegram's own chrome the same color as the app. */
const TELEGRAM_CHROME_COLOR = "#f6f3eb";

interface TelegramContextValue {
  /** True when running inside Telegram's webview (Mini App launch). */
  isTelegram: boolean;
}

const TelegramContext = createContext<TelegramContextValue>({
  isTelegram: false,
});

/** With `trailingSlash: true` a hard load reports "/app/" while client nav
 * reports "/app" — normalize before comparing. */
const normalizePath = (pathname: string | null) =>
  pathname ? pathname.replace(/\/+$/, "") || "/" : "";

/**
 * Telegram Mini App shell: inert everywhere except inside Telegram, where it
 * hands the webview over (ready/expand), keeps scroll gestures from collapsing
 * the app, matches Telegram's chrome to the paper background, and mirrors
 * in-app depth on Telegram's native back button. Login is not handled here:
 * Privy's seamless Telegram auth reads the launch hash on its own (see
 * providers.tsx).
 */
export function TelegramProvider({ children }: { children: ReactNode }) {
  const [isTelegram, setIsTelegram] = useState(false);
  const [webApp, setWebApp] = useState<TelegramWebApp | null>(null);
  const pathname = usePathname();
  const router = useRouter();

  // Detect the Telegram launch (flag set by the boot script in layout.tsx),
  // then wait for telegram-web-app.js — injected by the same script — to land.
  // Everything is optional-chained and try-wrapped: the app must keep working
  // if telegram.org is unreachable or the client predates an API.
  useEffect(() => {
    if (!isTelegramMiniApp()) return;
    setIsTelegram(true);
    let cancelled = false;
    let tries = 0;
    const init = () => {
      if (cancelled) return;
      const wa = telegramWebApp();
      if (!wa) {
        // The SDK script loads async from telegram.org; poll ~5s then give up.
        if (++tries < 50) setTimeout(init, 100);
        return;
      }
      // Each call gets its own try: e.g. clients on Bot API 6.1–6.8 throw on
      // hex header colors but do accept the background call that follows.
      const attempt = (fn: (() => void) | undefined) => {
        try {
          fn?.();
        } catch {
          /* cosmetic call on a stale client */
        }
      };
      attempt(wa.ready?.bind(wa));
      attempt(wa.expand?.bind(wa));
      attempt(wa.disableVerticalSwipes?.bind(wa));
      attempt(() => wa.setHeaderColor?.(TELEGRAM_CHROME_COLOR));
      attempt(() => wa.setBackgroundColor?.(TELEGRAM_CHROME_COLOR));
      setWebApp(wa);
    };
    init();
    return () => {
      cancelled = true;
    };
  }, []);

  // Telegram's native back button mirrors dapp depth: visible on subpages,
  // returns to the portfolio. (InstanceProvider's URL sync restores the ?i=
  // param after navigation, same as the regular nav links.)
  useEffect(() => {
    const back = webApp?.BackButton;
    if (!back) return;
    const path = normalizePath(pathname);
    const onSubpage = path.startsWith("/app") && path !== "/app";
    try {
      if (!onSubpage) {
        back.hide();
        return;
      }
      const goHome = () => router.push("/app");
      back.onClick(goHome);
      back.show();
      return () => {
        back.offClick(goHome);
        back.hide();
      };
    } catch {
      /* stale client without BackButton support */
    }
  }, [webApp, pathname, router]);

  return (
    <TelegramContext.Provider value={{ isTelegram }}>
      {children}
    </TelegramContext.Provider>
  );
}

/** Telegram context — `isTelegram` is false everywhere outside Telegram. */
export function useTelegram(): TelegramContextValue {
  return useContext(TelegramContext);
}
