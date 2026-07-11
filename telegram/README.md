# Crowdstake as a Telegram Mini App

The dapp runs unchanged inside Telegram — same static export, same contracts.
This folder holds the launcher config: a one-time setup script and an optional
reply bot. Nothing here is part of the web build.

## How it works

- **Detection.** Telegram opens the app with launch params in the URL fragment
  (`#tgWebAppData=…`). A boot script in `src/app/layout.tsx` runs before
  hydration: it persists the detection in `sessionStorage` (in-app navigation
  drops the hash), tags `<html class="tg-app">` for Telegram-scoped CSS, and
  injects the official `telegram-web-app.js`.
- **Shell.** `src/components/telegram-provider.tsx` signals `ready()`, expands
  the webview, disables swipe-to-collapse, matches Telegram's chrome to the
  paper background, and drives Telegram's native back button on dapp subpages.
  Outside Telegram it is inert.
- **Login & wallet.** Telegram's webview injects no wallet. With Telegram login
  enabled in the Privy dashboard (below), Privy's **seamless auth** signs users
  into an embedded wallet with zero clicks on launch, and the app's existing
  "App pays" sponsorship makes every governance action gasless. Without the
  dashboard config the normal Privy modal (email) still works.
- **Instance deep links.** A `startapp` payload of `<distributionManager>` or
  `<distributionManager>_<chainId>` is promoted to the `?i=`/`&c=` params the
  app already understands:
  `https://t.me/<bot>/<shortname>?startapp=0xB38B15ad418202D3FdC1A139cEc51A8c13f59CB6`

## Setup

### 1. Create the bot (@BotFather)

1. `/newbot` → pick a name and username; save the token.
2. `/setdomain` → the dapp's domain (`crowdstake.fun`).
   **Required for Privy's Telegram login.**
3. `/newapp` → attach a Direct-Link Mini App to the bot: set the **Web App
   URL** to the dapp's `/app/` page (e.g.
   `https://crowdstake.fun/app/`) and pick a short
   name → the app opens at `t.me/<bot>/<shortname>`.
4. Optional: **Bot Settings → Configure Mini App → Enable Mini App** to make it
   the bot's _main_ app (`t.me/<bot>?startapp`, plus an "Open App" button on
   the bot's profile).

### 2. Menu button + commands (Bot API)

```bash
TELEGRAM_BOT_TOKEN=123456:ABC-... \
WEBAPP_URL=https://crowdstake.fun/app/ \
node telegram/setup.mjs
```

Idempotent; re-run whenever the URL changes.

### 3. Privy dashboard (seamless login)

In the [Privy dashboard](https://dashboard.privy.io) for the app id baked into
the deployment (`NEXT_PUBLIC_PRIVY_APP_ID`):

1. **Login methods → Socials → Telegram**: enable, and provide the **bot
   token** and **bot handle** from step 1.
2. Toggle **Enable seamless auth** — this is what logs Mini App users in with
   zero clicks (the frontend already offers `telegram` as a login method when
   it detects a Telegram launch).
3. Add `https://web.telegram.org` to the app's allowed domains so the Mini App
   also works in Telegram's web clients.

### 4. Optional reply bot

The menu button and t.me links need no server. If the bot should also _answer_
`/start` and `/app` messages with an open-app button:

```bash
TELEGRAM_BOT_TOKEN=... WEBAPP_URL=... \
DIRECT_LINK=https://t.me/<bot>/<shortname> \
node telegram/bot.mjs
```

`/start 0x<manager>[_<chainId>]` deep-links that instance, mirroring the
`startapp` format.

## Local development

Telegram requires HTTPS, so point a tunnel (e.g. `cloudflared tunnel --url
http://localhost:3001`) at `pnpm dev` and use the tunnel URL as the Mini App /
`/setdomain` URL. To iterate on the Telegram-only UI in a normal browser, open
the app with a fake launch hash: `http://localhost:3001/app/#tgWebAppPlatform=web`
(detection keys off `tgWebApp` in the fragment; Privy seamless login still
needs real launch data, so test login inside Telegram itself).
