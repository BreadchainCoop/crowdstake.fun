/* Drives the REAL Crowdstake UI (the unmodified static export) with a key-backed
 * injected wallet, signing every step instead of showing a wallet prompt, and
 * asserts each UI action's on-chain effect via independent viem reads. Proves
 * the app's wiring — not a script — produced the transactions.
 *
 * Steps: connect -> deposit -> vote -> distribute -> withdraw -> deploy instance.
 * Default target is a local anvil Gnosis fork (see run.sh). */
const { chromium } = require("playwright");
const { installShim } = require("./inject.cjs");
const { R, account } = require("./lib.cjs");

// Resolve a usable Chromium. Prefer an explicit override, then any full
// Chromium build Playwright has cached (works headless), else fall back to
// Playwright's managed browser (run `npx playwright install chromium` first).
function resolveChromium() {
  if (process.env.PW_EXECUTABLE_PATH) return process.env.PW_EXECUTABLE_PATH;
  const fs = require("fs");
  const os = require("os");
  const path = require("path");
  const roots = [
    path.join(os.homedir(), "Library/Caches/ms-playwright"), // macOS
    path.join(os.homedir(), ".cache/ms-playwright"), // linux
  ];
  for (const root of roots) {
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
    for (const d of dirs) {
      for (const rel of [
        "chrome-mac/Chromium.app/Contents/MacOS/Chromium",
        "chrome-linux/chrome",
      ]) {
        const p = path.join(root, d, rel);
        if (fs.existsSync(p)) return p;
      }
    }
  }
  return undefined; // let Playwright resolve its managed browser
}

const BASE = process.env.TEST_BASE_URL || "http://localhost:4173";
const ADDR = account.address;
const ZERO = "0x0000000000000000000000000000000000000000";
const ONE = 10n ** 18n;

let pass = 0,
  fail = 0;
const ok = (c, m) => {
  if (c) {
    pass++;
    console.log("  \x1b[32m✓\x1b[0m " + m);
  } else {
    fail++;
    console.log("  \x1b[31m✗ FAIL\x1b[0m " + m);
  }
};
// Poll an on-chain read until it satisfies pred (proves the UI tx landed).
async function waitFor(fn, pred, ms = 45000, every = 1000) {
  const t = Date.now();
  let v;
  while (Date.now() - t < ms) {
    v = await fn().catch(() => undefined);
    if (v !== undefined && pred(v)) return v;
    await new Promise((r) => setTimeout(r, every));
  }
  return v;
}
const click = (page, name) =>
  page.getByRole("button", { name, exact: true }).click();

(async () => {
  const execPath = resolveChromium();
  const browser = await chromium.launch({
    headless: true,
    ...(execPath ? { executablePath: execPath } : {}),
  });
  const ctx = await browser.newContext({
    viewport: { width: 1280, height: 800 },
  });
  await installShim(ctx);
  const page = await ctx.newPage();
  page.on("pageerror", (e) => console.log("  [pageerror]", e.message));

  // 1) CONNECT — auto-reconnect via the injected provider; no wallet prompt.
  console.log("\n1) CONNECT (env key, no wallet prompt)");
  await page.goto(BASE + "/app", { waitUntil: "networkidle" });
  await page.waitForTimeout(2500);
  const connectBtn = () =>
    page.getByRole("button", { name: "Connect Wallet", exact: true });
  if (await connectBtn().count()) {
    // Fallback if reconnect didn't fire: open the modal and pick our wallet.
    await connectBtn().first().click();
    await page.waitForTimeout(1500);
    await page
      .getByRole("button", { name: "Crowdstake Test" })
      .first()
      .click()
      .catch(() => {});
    await page.waitForTimeout(3000);
  }
  await page.waitForTimeout(1000);
  ok(
    (await connectBtn().count()) === 0,
    "connected via env-key shim (no prompt)",
  );
  ok(
    (await page.getByRole("button", { name: /Switch to/i }).count()) === 0,
    "on Gnosis (chain 100)",
  );

  // 2) DEPOSIT 250 xDAI (native) -> mint 1:1 + auto-delegate
  console.log("\n2) DEPOSIT 250 xDAI (native)");
  const bal0 = await R.balanceOf(ADDR);
  await page.goto(BASE + "/app/deposit", { waitUntil: "networkidle" });
  await page.waitForTimeout(1500);
  await click(page, "xDAI (native)");
  await page.locator('input[inputmode="decimal"]').fill("250");
  await page.waitForTimeout(500);
  await click(page, "Deposit");
  const balD = await waitFor(
    () => R.balanceOf(ADDR),
    (v) => v > bal0,
  );
  ok(balD - bal0 === 250n * ONE, "minted exactly 250 CSTAKE via UI");
  ok((await R.getVotes(ADDR)) >= 250n * ONE, "votes auto-delegated (>=250)");

  // 3) VOTE 70 / 30
  console.log("\n3) VOTE 70 / 30");
  await page.goto(BASE + "/app/vote", { waitUntil: "networkidle" });
  await page.waitForTimeout(2000);
  const sliders = page.locator('input[type="range"]');
  await sliders.nth(0).fill("70");
  await sliders.nth(1).fill("30");
  await page.waitForTimeout(500);
  await click(page, "Cast vote");
  ok(
    (await waitFor(
      () => R.hasVoted(ADDR),
      (v) => v === true,
    )) === true,
    "hasVotedInCurrentCycle via UI",
  );

  // 4) DISTRIBUTE (permissionless) -> cycle advances
  console.log("\n4) DISTRIBUTE");
  ok(
    (await waitFor(
      () => R.isDistributionReady(),
      (v) => v === true,
      20000,
    )) === true,
    "isDistributionReady after vote",
  );
  const cyc0 = await R.currentCycle();
  await page.goto(BASE + "/app/distribute", { waitUntil: "networkidle" });
  await page.waitForTimeout(2000);
  await click(page, "Claim & distribute");
  const cyc1 = await waitFor(
    () => R.currentCycle(),
    (v) => v > cyc0,
    60000,
  );
  ok(cyc1 === cyc0 + 1n, `cycle advanced ${cyc0} -> ${cyc1} via UI`);

  // 5) WITHDRAW 100 CSTAKE -> burn 1:1
  console.log("\n5) WITHDRAW 100 CSTAKE");
  const bw0 = await R.balanceOf(ADDR);
  await page.goto(BASE + "/app/withdraw", { waitUntil: "networkidle" });
  await page.waitForTimeout(1500);
  await page.locator('input[inputmode="decimal"]').fill("100");
  await page.waitForTimeout(500);
  await click(page, "Withdraw to xDAI");
  const bw1 = await waitFor(
    () => R.balanceOf(ADDR),
    (v) => v < bw0,
  );
  ok(bw0 - bw1 === 100n * ONE, "burned exactly 100 CSTAKE via UI");

  // 6) DEPLOY a fresh instance in one transaction
  console.log("\n6) DEPLOY instance");
  await page.goto(BASE + "/app/deploy", { waitUntil: "networkidle" });
  await page.waitForTimeout(1500);
  await page.getByPlaceholder("Acme Community Stake").fill("Riverside Mutual");
  await page.getByPlaceholder("ACME", { exact: true }).fill("RVR");
  await page.waitForTimeout(400);
  await click(page, "Deploy instance");
  const deployed = await waitFor(
    () => R.latestDeployedInstance(ADDR),
    (v) => v !== null,
    90000,
  );
  ok(deployed !== null, "SystemDeployed emitted for our owner via UI");
  if (deployed) {
    const inst = await R.resolveInstance(deployed.distributionManager);
    const all = Object.values(inst);
    ok(
      all.every((x) => x && x !== ZERO),
      "deployed instance resolves to 7 non-zero contracts",
    );
    ok(
      (await R.registryOwner(inst.recipientRegistry)).toLowerCase() ===
        ADDR.toLowerCase(),
      "deployer owns the new instance's registry",
    );
    // UI success card (only renders when the event decoded correctly).
    ok(
      (await page.getByRole("button", { name: "Use this instance" }).count()) >
        0,
      "UI shows 'Use this instance' (event decoded -> instance mapped)",
    );
  }

  console.log(
    `\n=== ${fail === 0 ? "\x1b[32mJOURNEY PASS\x1b[0m" : "\x1b[31mJOURNEY FAIL\x1b[0m"} (${pass} ok, ${fail} fail) ===`,
  );
  await browser.close();
  process.exit(fail === 0 ? 0 : 1);
})().catch((e) => {
  console.error("FATAL", e);
  process.exit(1);
});
