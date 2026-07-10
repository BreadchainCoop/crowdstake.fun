/**
 * Telegram Mini App detection + SDK bridge.
 *
 * The dapp runs unchanged inside Telegram's webview (launched from a bot's
 * menu button or a t.me/<bot>/<app> direct link — see telegram/README.md).
 * Telegram identifies itself by putting launch params in the URL fragment
 * (#tgWebAppData=…&tgWebAppPlatform=…). The boot script in src/app/layout.tsx
 * runs before hydration: it persists a sessionStorage flag (in-app navigation
 * drops the hash), tags <html> with `tg-app` for CSS, and injects the official
 * telegram-web-app.js. Everything here just reads that state.
 */

/** sessionStorage flag set by the boot script on first load inside Telegram. */
export const TELEGRAM_FLAG_KEY = "crowdstake.telegram.v1";

/** The slice of the telegram-web-app.js SDK this app calls. Every member is
 * optional: clients predating an API simply skip the nicety. */
export interface TelegramWebApp {
  initData?: string;
  platform?: string;
  ready?: () => void;
  expand?: () => void;
  disableVerticalSwipes?: () => void;
  setHeaderColor?: (color: string) => void;
  setBackgroundColor?: (color: string) => void;
  BackButton?: {
    show: () => void;
    hide: () => void;
    onClick: (cb: () => void) => void;
    offClick: (cb: () => void) => void;
  };
}

declare global {
  interface Window {
    Telegram?: { WebApp?: TelegramWebApp };
  }
}

/** True when this session was launched from inside Telegram. */
export function isTelegramMiniApp(): boolean {
  if (typeof window === "undefined") return false;
  try {
    if (sessionStorage.getItem(TELEGRAM_FLAG_KEY) === "1") return true;
  } catch {
    /* sessionStorage blocked — fall through to the launch hash */
  }
  return window.location.hash.includes("tgWebApp");
}

/** The Telegram SDK object, once the boot-injected script has loaded. */
export function telegramWebApp(): TelegramWebApp | null {
  if (typeof window === "undefined") return null;
  return window.Telegram?.WebApp ?? null;
}
