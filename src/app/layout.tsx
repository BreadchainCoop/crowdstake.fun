import type { Metadata } from "next";
import "./globals.css";
import { Providers } from "@/components/providers";

// Icons + preview images ride Next's file conventions (src/app/icon.png,
// apple-icon.png, opengraph-image.png, twitter-image.png — plus a classic
// public/favicon.ico for tools that hardcode the path); metadataBase makes
// the generated URLs absolute, which scrapers require.
export const metadata: Metadata = {
  metadataBase: new URL("https://crowdstake.fun"),
  title: "Crowdstaking — Community-Powered Funding Protocol",
  description:
    "Transform any pool of money into a democratic, interest-generating engine for your group's shared goals. Open source, free, and customizable.",
  openGraph: {
    type: "website",
    url: "https://crowdstake.fun",
    siteName: "Crowdstaking",
    title: "Crowdstaking — Community-Powered Funding Protocol",
    description:
      "Stake together — only the interest funds your community's goals. Open source, multichain, gasless.",
  },
  twitter: {
    card: "summary_large_image",
    title: "Crowdstaking — Community-Powered Funding Protocol",
    description:
      "Stake together — only the interest funds your community's goals.",
  },
};

/**
 * Telegram Mini App boot — must run before hydration so every consumer sees a
 * settled URL/DOM (see src/lib/telegram.ts and telegram/README.md). Telegram
 * launches the app with #tgWebAppData=…&tgWebAppStartParam=… in the fragment;
 * in-app navigation drops the hash, so detection persists in sessionStorage.
 * When inside Telegram: tag <html> (scopes the .tg-app CSS), inject the
 * official SDK (viewport/back-button/theme bridge — the app degrades
 * gracefully without it), and promote a `startapp` deep-link payload
 * (<distributionManager> or <distributionManager>_<chainId>) to the ?i=/&c=
 * params InstanceProvider already reads. The hash itself is left untouched —
 * Privy's seamless Telegram auth reads #tgWebAppData directly.
 */
const TELEGRAM_BOOT_SCRIPT = `(function () {
  try {
    var KEY = "crowdstake.telegram.v1";
    var hash = window.location.hash;
    var flagged = null;
    try { flagged = sessionStorage.getItem(KEY); } catch (e) {}
    if (hash.indexOf("tgWebApp") === -1 && flagged !== "1") return;
    try { sessionStorage.setItem(KEY, "1"); } catch (e) {}
    document.documentElement.classList.add("tg-app");
    var s = document.createElement("script");
    s.src = "https://telegram.org/js/telegram-web-app.js";
    s.async = false;
    document.head.appendChild(s);
    var m = /(?:^#|&)tgWebAppStartParam=([^&]*)/.exec(hash);
    var start = m && decodeURIComponent(m[1]);
    var p = start && /^(0x[0-9a-fA-F]{40})(?:_([0-9]+))?$/.exec(start);
    if (p) {
      var url = new URL(window.location.href);
      if (!url.searchParams.get("i")) {
        url.searchParams.set("i", p[1]);
        if (p[2]) url.searchParams.set("c", p[2]);
        window.history.replaceState(null, "", url);
      }
    }
  } catch (e) {}
})();`;

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    // The boot script adds .tg-app to <html> before hydration inside Telegram;
    // suppress React's dev-only attribute diff for it (next-themes pattern).
    <html lang="en" suppressHydrationWarning>
      <body>
        <script dangerouslySetInnerHTML={{ __html: TELEGRAM_BOOT_SCRIPT }} />
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
