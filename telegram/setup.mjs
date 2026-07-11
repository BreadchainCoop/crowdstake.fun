#!/usr/bin/env node
/**
 * One-time Bot API config for the Crowdstake Telegram Mini App: points the
 * bot's menu button at the dapp and registers its commands. Zero dependencies
 * (Node 18+, global fetch). BotFather steps that have no API — creating the
 * bot, /newapp, /setdomain — are in ./README.md.
 *
 * Usage:
 *   TELEGRAM_BOT_TOKEN=123456:ABC-... \
 *   WEBAPP_URL=https://crowdstake.fun/app/ \
 *   node telegram/setup.mjs
 */

const TOKEN = process.env.TELEGRAM_BOT_TOKEN;
const WEBAPP_URL = process.env.WEBAPP_URL;

if (!TOKEN || !WEBAPP_URL) {
  console.error(
    "Set TELEGRAM_BOT_TOKEN (from @BotFather) and WEBAPP_URL (HTTPS URL of the dapp's /app/ page).",
  );
  process.exit(1);
}

async function api(method, params) {
  const res = await fetch(`https://api.telegram.org/bot${TOKEN}/${method}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(params ?? {}),
  });
  const body = await res.json();
  if (!body.ok) throw new Error(`${method}: ${body.description}`);
  return body.result;
}

const me = await api("getMe");
console.log(`Configuring @${me.username}…`);

// Menu button: the paperclip-area button in every private chat with the bot.
await api("setChatMenuButton", {
  menu_button: {
    type: "web_app",
    text: "Open App",
    web_app: { url: WEBAPP_URL },
  },
});
console.log(`✓ menu button → ${WEBAPP_URL}`);

await api("setMyCommands", {
  commands: [
    { command: "start", description: "Open the crowdstaking app" },
    { command: "app", description: "Open the crowdstaking app" },
  ],
});
console.log("✓ commands (/start, /app)");

await api("setMyShortDescription", {
  short_description:
    "Community-powered funding — stake together, fund what matters.",
});
console.log("✓ short description");

console.log(`
Done. Next (manual, in @BotFather — see telegram/README.md):
  1. /setdomain → ${new URL(WEBAPP_URL).hostname} (required for Privy Telegram login)
  2. /newapp → Direct-Link Mini App (t.me/${me.username}/<shortname>)
  3. Bot Settings > Configure Mini App > Enable Mini App (t.me/${me.username}?startapp)
`);
