#!/usr/bin/env node
/**
 * Optional long-polling bot: replies to /start and /app with a button that
 * opens the mini app. The menu button and t.me direct links work without any
 * running bot (they're BotFather/API config — see ./setup.mjs and ./README.md);
 * run this only if the bot should also answer messages. Zero dependencies
 * (Node 18+, global fetch).
 *
 * Usage:
 *   TELEGRAM_BOT_TOKEN=123456:ABC-... \
 *   WEBAPP_URL=https://crowdstake.fun/app/ \
 *   [DIRECT_LINK=https://t.me/<bot>/<shortname>] \
 *   node telegram/bot.mjs
 *
 * DIRECT_LINK is the /newapp Direct-Link Mini App; when set, group chats get
 * a t.me link button (web_app buttons only work in private chats).
 */

const TOKEN = process.env.TELEGRAM_BOT_TOKEN;
const WEBAPP_URL = process.env.WEBAPP_URL;
const DIRECT_LINK = process.env.DIRECT_LINK;

if (!TOKEN || !WEBAPP_URL) {
  console.error("Set TELEGRAM_BOT_TOKEN and WEBAPP_URL.");
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

/** /start payloads deep-link an instance: <manager> or <manager>_<chainId> —
 * the same format the frontend accepts as a `startapp` param. */
const parseInstance = (payload) =>
  /^(0x[0-9a-fA-F]{40})(?:_(\d+))?$/.exec(payload ?? "");

const webAppUrl = (payload) => {
  const m = parseInstance(payload);
  if (!m) return WEBAPP_URL;
  const sep = WEBAPP_URL.includes("?") ? "&" : "?";
  return `${WEBAPP_URL}${sep}i=${m[1]}${m[2] ? `&c=${m[2]}` : ""}`;
};

const directUrl = (payload) =>
  parseInstance(payload)
    ? `${DIRECT_LINK}?startapp=${payload}`
    : `${DIRECT_LINK}`;

async function onMessage(msg) {
  const m = /^\/(?:start|app)(?:@(\w+))?(?:\s+(\S+))?\s*$/.exec(msg.text ?? "");
  if (!m) return;
  // Ignore commands addressed to a different bot (/start@someotherbot).
  if (m[1] && m[1].toLowerCase() !== me.username.toLowerCase()) return;
  const payload = m[2];
  // web_app buttons are private-chat only; groups get the t.me direct link.
  const button =
    msg.chat.type === "private"
      ? { text: "Open Crowdstake", web_app: { url: webAppUrl(payload) } }
      : DIRECT_LINK
        ? { text: "Open Crowdstake", url: directUrl(payload) }
        : { text: "Open Crowdstake", url: webAppUrl(payload) };
  await api("sendMessage", {
    chat_id: msg.chat.id,
    text: "Crowdstake — stake together, fund what matters.",
    reply_markup: { inline_keyboard: [[button]] },
  });
}

const me = await api("getMe");
console.log(`@${me.username} polling for updates… (ctrl-c to stop)`);

let offset = 0;
for (;;) {
  try {
    const updates = await api("getUpdates", {
      offset,
      timeout: 50,
      allowed_updates: ["message"],
    });
    for (const u of updates) {
      offset = u.update_id + 1;
      if (u.message)
        await onMessage(u.message).catch((e) => console.error(e.message));
    }
  } catch (e) {
    console.error(e.message);
    await new Promise((r) => setTimeout(r, 3000));
  }
}
