/* Focused e2e for instance metadata (token + header image). Deploys an instance
 * with artwork through the REAL deploy form, asserts the URIs were seeded on the
 * distribution manager in the same tx (ERC-7572 contractURI assembled), then
 * switches to it and checks the app renders both images. Uses tiny data: image
 * URIs so they load in headless chromium (no network). */
const { chromium } = require("playwright");
const { installShim } = require("./inject.cjs");
const L = require("./lib.cjs");
const { meta, resolveInstance, latestDeployedInstance, account } = L;

function resolveChromium() {
  if (process.env.PW_EXECUTABLE_PATH) return process.env.PW_EXECUTABLE_PATH;
  const fs = require("fs"),
    os = require("os"),
    path = require("path");
  for (const root of [
    path.join(os.homedir(), "Library/Caches/ms-playwright"),
    path.join(os.homedir(), ".cache/ms-playwright"),
  ]) {
    let dirs = [];
    try {
      dirs = fs
        .readdirSync(root)
        .filter((d) => /^chromium-\d+$/.test(d))
        .sort()
        .reverse();
    } catch {
      continue;
    }
    for (const d of dirs)
      for (const rel of [
        "chrome-mac/Chromium.app/Contents/MacOS/Chromium",
        "chrome-linux/chrome",
      ]) {
        const p = path.join(root, d, rel);
        if (fs.existsSync(p)) return p;
      }
  }
  return undefined;
}

const BASE = process.env.TEST_BASE_URL || "http://localhost:4173";
const ADDR = account.address;
// 1x1 PNGs — valid data:image URIs that load with no network.
const TOKEN_IMG =
  "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==";
const BANNER_IMG =
  "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==";

let pass = 0,
  fail = 0;
const ok = (c, m) => {
  if (c) {
    pass++;
    console.log("    \x1b[32m✓\x1b[0m " + m);
  } else {
    fail++;
    console.log("    \x1b[31m✗ FAIL\x1b[0m " + m);
  }
};
const head = (n) => console.log("\n" + n);
async function waitFor(fn, pred, ms = 90000, every = 1000) {
  const t = Date.now();
  let v;
  while (Date.now() - t < ms) {
    v = await fn().catch(() => undefined);
    if (v !== undefined && pred(v)) return v;
    await new Promise((r) => setTimeout(r, every));
  }
  return v;
}
let page;
const click = (name) => page.getByRole("button", { name, exact: true }).click();

(async () => {
  const browser = await chromium.launch({
    headless: true,
    ...(resolveChromium() ? { executablePath: resolveChromium() } : {}),
  });
  const ctx = await browser.newContext({
    viewport: { width: 1280, height: 900 },
  });
  await installShim(ctx);
  page = await ctx.newPage();
  page.on("pageerror", (e) => console.log("    [pageerror]", e.message));

  head("1) CONNECT");
  await page.goto(BASE + "/app", { waitUntil: "networkidle" });
  await page.waitForTimeout(2500);
  ok(
    (await page
      .getByRole("button", { name: "Connect Wallet", exact: true })
      .count()) === 0,
    "connected via env-key shim",
  );

  head("2) DEPLOY an instance with artwork");
  await page.goto(BASE + "/app/deploy", { waitUntil: "networkidle" });
  await page.waitForTimeout(1500);
  await page.getByPlaceholder("Acme Community Stake").fill("Art Co");
  await page.getByPlaceholder("ACME", { exact: true }).fill("ART");
  await page.getByPlaceholder("e.g. 24").fill("5");
  await page.getByRole("combobox").selectOption("minutes");
  await page
    .getByPlaceholder("Token image — https:// or ipfs://")
    .fill(TOKEN_IMG);
  await page
    .getByPlaceholder("Header/banner image — https:// or ipfs://")
    .fill(BANNER_IMG);
  await page.waitForTimeout(400);
  await click("Deploy instance");

  // Wait for the latest deployed instance whose metadata matches what we sent.
  const inst = await waitFor(
    async () => {
      const d = await latestDeployedInstance(ADDR);
      if (!d) return undefined;
      const i = await resolveInstance(d.distributionManager);
      try {
        if ((await meta.tokenImageURI(i.distributionManager)) === TOKEN_IMG)
          return i;
      } catch {
        /* older impl reverts */
      }
      return undefined;
    },
    (v) => v !== undefined,
  );
  ok(inst !== undefined, "instance deployed");
  const dm = inst.distributionManager;
  ok(
    (await meta.tokenImageURI(dm)) === TOKEN_IMG,
    "tokenImageURI seeded at deploy",
  );
  ok(
    (await meta.bannerImageURI(dm)) === BANNER_IMG,
    "bannerImageURI seeded at deploy",
  );
  ok(
    ((await meta.contractURI(dm)) || "").startsWith("data:application/json"),
    "ERC-7572 contractURI() assembled",
  );

  head("3) SWITCH to it — app renders the artwork");
  await click("Use this instance");
  await page.waitForTimeout(2500);
  await page.goto(BASE + "/app", { waitUntil: "networkidle" });
  await page.waitForTimeout(2500);
  const bannerSrc = await page
    .locator('img[alt="Instance banner"]')
    .first()
    .getAttribute("src")
    .catch(() => null);
  ok(bannerSrc === BANNER_IMG, "header banner renders the banner image");
  const tokenSrc = await page
    .locator('img[alt$="token"]')
    .first()
    .getAttribute("src")
    .catch(() => null);
  ok(tokenSrc === TOKEN_IMG, "portfolio token badge renders the token image");

  console.log(
    `\n=== ${fail === 0 ? "\x1b[32mMETADATA FLOW PASS\x1b[0m" : "\x1b[31mFAIL\x1b[0m"} (${pass} ok, ${fail} fail) ===`,
  );
  await browser.close();
  process.exit(fail === 0 ? 0 : 1);
})().catch((e) => {
  console.error("FATAL", e);
  process.exit(1);
});
