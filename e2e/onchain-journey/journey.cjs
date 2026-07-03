/* Exhaustive on-chain journey: drives the REAL Crowdstake UI with a key-backed
 * injected wallet (no wallet prompt) and asserts every feature/user path's
 * on-chain effect via independent viem reads. Default target is a local anvil
 * Gnosis fork (see run.sh).
 *
 * Coverage:
 *   A. Default instance: connect, deposit (native + WXDAI approve/mint),
 *      withdraw, vote, distribute, delegate.
 *   B. Deploy a self-owned instance (short cycle) and switch to it.
 *   C. Recipient admin on it: queue add (x2), process, queue remove, process.
 *   D. Admin settings on it: update cycle length, prepare yield-claimer rotation.
 *   E. Full loop on it: deposit -> vote -> force yield + complete cycle ->
 *      distribute (recipients paid) -> withdraw.
 *   Plus a few UI edge cases (over-balance, no-allocation gating).
 */
const { erc20Abi, isAddress } = require("viem");
const { chromium } = require("playwright");
const { installShim } = require("./inject.cjs");
const L = require("./lib.cjs");
const {
  R,
  reads,
  resolveInstance,
  latestDeployedInstance,
  fork,
  account,
  pub,
} = L;

function resolveChromium() {
  if (process.env.PW_EXECUTABLE_PATH) return process.env.PW_EXECUTABLE_PATH;
  const fs = require("fs");
  const os = require("os");
  const path = require("path");
  const roots = [
    path.join(os.homedir(), "Library/Caches/ms-playwright"),
    path.join(os.homedir(), ".cache/ms-playwright"),
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
const ZERO = "0x0000000000000000000000000000000000000000";
const ONE = 10n ** 18n;
const WXDAI = L.A.WXDAI;
const R1 = "0x000000000000000000000000000000000000aa01";
const R2 = "0x000000000000000000000000000000000000bb02";
const NEW_CLAIMER = "0x000000000000000000000000000000000000cc03";

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
let page;
const btn = (name) => page.getByRole("button", { name, exact: true });
const click = (name) => btn(name).click();
const goto = async (path, settle = 1600) => {
  await page.goto(BASE + path, { waitUntil: "networkidle" });
  await page.waitForTimeout(settle);
};
const wxBalance = (a) =>
  pub.readContract({
    address: WXDAI,
    abi: erc20Abi,
    functionName: "balanceOf",
    args: [a],
  });

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

  /* ===================== A. DEFAULT INSTANCE ====================== */
  head("A. DEFAULT INSTANCE");

  head("A1) connect (env key, no wallet prompt)");
  await goto("/app", 2500);
  if (await btn("Connect Wallet").count()) {
    await btn("Connect Wallet").first().click();
    await page.waitForTimeout(1500);
    await page
      .getByRole("button", { name: "Crowdstake Test" })
      .first()
      .click()
      .catch(() => {});
    await page.waitForTimeout(3000);
  }
  await page.waitForTimeout(1000);
  ok((await btn("Connect Wallet").count()) === 0, "connected (no prompt)");
  ok(
    (await page.getByRole("button", { name: /Switch to/i }).count()) === 0,
    "on Gnosis (chain 100)",
  );

  head("A2) deposit 250 xDAI (native) -> mint + auto-delegate");
  let bal0 = await R.balanceOf(ADDR);
  await goto("/app/deposit");
  await click("xDAI (native)");
  await page.locator('input[inputmode="decimal"]').fill("250");
  await page.waitForTimeout(400);
  await click("Deposit");
  let balD = await waitFor(
    () => R.balanceOf(ADDR),
    (v) => v > bal0,
  );
  ok(balD - bal0 === 250n * ONE, "minted exactly 250 CSTAKE");
  ok((await R.getVotes(ADDR)) >= 250n * ONE, "votes auto-delegated (>=250)");

  head("A3) deposit 100 WXDAI (approve + mint)");
  await fork.wrapWxdai(150n * ONE); // give the signer WXDAI to stake
  const wx0 = await wxBalance(ADDR);
  bal0 = await R.balanceOf(ADDR);
  await goto("/app/deposit");
  await click("WXDAI");
  await page.locator('input[inputmode="decimal"]').fill("100");
  await page.waitForTimeout(400);
  ok((await btn("Approve WXDAI").count()) > 0, "shows Approve WXDAI first");
  await click("Approve WXDAI");
  await waitFor(
    () => btn("Deposit").count(),
    (v) => v > 0,
    45000,
    800,
  );
  await click("Deposit");
  balD = await waitFor(
    () => R.balanceOf(ADDR),
    (v) => v > bal0,
  );
  ok(balD - bal0 === 100n * ONE, "minted exactly 100 CSTAKE from WXDAI");
  ok(wx0 - (await wxBalance(ADDR)) === 100n * ONE, "spent exactly 100 WXDAI");

  head("A4) over-balance is blocked (UI edge)");
  await goto("/app/deposit");
  await click("xDAI (native)");
  await page.locator('input[inputmode="decimal"]').fill("99999999");
  await page.waitForTimeout(500);
  ok(
    (await page.getByText(/exceeds your balance/i).count()) > 0,
    "over-balance shows error",
  );
  ok(await btn("Deposit").isDisabled(), "Deposit disabled when over balance");

  head("A5) vote 70 / 30");
  await goto("/app/vote", 2000);
  ok(
    (await btn("Cast vote").isDisabled()) === true,
    "Cast vote disabled with no allocation",
  );
  const steppers = page.locator('input[inputmode="numeric"]');
  await steppers.nth(0).fill("70");
  await steppers.nth(1).fill("30");
  await page.waitForTimeout(500);
  await click("Cast vote");
  ok(
    (await waitFor(
      () => R.hasVoted(ADDR),
      (v) => v === true,
    )) === true,
    "hasVotedInCurrentCycle",
  );

  head("A6) distribute -> cycle advances");
  ok(
    (await waitFor(
      () => R.isDistributionReady(),
      (v) => v === true,
      20000,
    )) === true,
    "isDistributionReady",
  );
  let cyc0 = await R.currentCycle();
  await goto("/app/distribute", 2000);
  await click("Claim & distribute");
  let cyc1 = await waitFor(
    () => R.currentCycle(),
    (v) => v > cyc0,
    60000,
  );
  ok(cyc1 === cyc0 + 1n, `cycle advanced ${cyc0} -> ${cyc1}`);

  head("A7) withdraw 100 -> burn");
  let bw0 = await R.balanceOf(ADDR);
  await goto("/app/withdraw");
  await page.locator('input[inputmode="decimal"]').fill("100");
  await page.waitForTimeout(400);
  await click("Withdraw to xDAI");
  let bw1 = await waitFor(
    () => R.balanceOf(ADDR),
    (v) => v < bw0,
  );
  ok(bw0 - bw1 === 100n * ONE, "burned exactly 100 CSTAKE");

  head("A8) delegate to myself (admin page)");
  await goto("/app/admin", 2000);
  await click("Delegate to myself");
  ok(
    (await waitFor(
      () => R.delegates(ADDR),
      (v) => v.toLowerCase() === ADDR.toLowerCase(),
    )) !== undefined,
    "delegates(self) == self",
  );

  /* ===================== B. DEPLOY + SWITCH ====================== */
  head("B. DEPLOY A SELF-OWNED INSTANCE");
  await goto("/app/deploy");
  await page.getByPlaceholder("Acme Community Stake").fill("Riverside Mutual");
  await page.getByPlaceholder("ACME", { exact: true }).fill("RVR");
  // Cycle length is now a duration; 5 min ≈ 60 blocks @5s — short for the fork.
  await page.getByPlaceholder("e.g. 24").fill("5");
  await page.getByRole("combobox").selectOption("minutes");
  await page.waitForTimeout(400);
  await click("Deploy instance");
  const deployed = await waitFor(
    () => latestDeployedInstance(ADDR),
    (v) => v !== null,
    90000,
  );
  ok(deployed !== null, "SystemDeployed emitted");
  const N = reads(await resolveInstance(deployed.distributionManager));
  ok(
    Object.values(N.inst).every((x) => x && x !== ZERO),
    "instance resolves to 7 non-zero contracts",
  );
  ok(
    (await N.registryOwner()).toLowerCase() === ADDR.toLowerCase(),
    "signer owns the new registry",
  );
  await click("Use this instance"); // activate it
  await page.waitForTimeout(2500);
  ok(
    (await page.getByText("RVR", { exact: false }).count()) > 0,
    "switched to the new instance (label shows)",
  );

  /* ===================== C. RECIPIENT ADMIN ====================== */
  head("C. RECIPIENT ADMIN (self-owned instance)");
  const lc = (x) => x.toLowerCase();
  await goto("/app/recipients", 2000);
  // Stage two additions in DESCENDING address order (R2 then R1). Without the
  // client-side sort this would revert QueueNotSorted — a regression guard.
  const addInput = () => page.getByPlaceholder("0x… recipient address");
  await addInput().fill(R2);
  await click("Add");
  await addInput().fill(R1);
  await click("Add");
  await page.waitForTimeout(300);
  await click("Queue additions");
  await waitFor(
    () => N.queuedAdditions(),
    (q) => q.length === 2,
    60000,
  );
  ok(
    (await N.queuedAdditions()).length === 2,
    "out-of-order batch queued without QueueNotSorted (sorted client-side)",
  );
  await click("Process queue");
  const recs = await waitFor(
    () => N.recipients(),
    (v) => v.length >= 2,
    60000,
  );
  ok(recs.length === 2, "process -> 2 active recipients");
  ok(
    recs.map(lc).includes(R1.toLowerCase()) &&
      recs.map(lc).includes(R2.toLowerCase()),
    "both recipients active",
  );

  head("C2) stage + queue + process a removal");
  await page.waitForTimeout(800);
  await page
    .getByRole("button", { name: "Remove", exact: true })
    .last()
    .click();
  await page.waitForTimeout(300);
  await click("Queue 1 removal");
  await waitFor(
    () => N.queuedRemovals(),
    (v) => v.length >= 1,
    60000,
  );
  await click("Process queue");
  const recs2 = await waitFor(
    () => N.recipients(),
    (v) => v.length === 1,
    60000,
  );
  ok(recs2.length === 1, "process -> 1 active recipient after removal");

  /* ===================== D. ADMIN SETTINGS ====================== */
  head("D. ADMIN SETTINGS (self-owned instance)");
  await goto("/app/admin", 2000);
  // Duration input: 2 min = 24 blocks @5s.
  await page.getByPlaceholder("e.g. 24").fill("2");
  await page.getByRole("combobox").selectOption("minutes");
  await page.waitForTimeout(300);
  await click("Update");
  ok(
    (await waitFor(
      () => N.cycleLength(),
      (v) => v === 24n,
      45000,
    )) === 24n,
    "cycle length updated to 24 (2 min @5s)",
  );

  head("D2) prepare yield-claimer rotation (timelock; prepare only)");
  await goto("/app/admin", 2000);
  await page.getByPlaceholder("0x… new claimer").fill(NEW_CLAIMER);
  await page.waitForTimeout(300);
  await click("Prepare");
  const pend = await waitFor(
    () =>
      pub.readContract({
        address: N.inst.token,
        abi: require("viem").parseAbi([
          "function pendingYieldClaimer() view returns (address)",
        ]),
        functionName: "pendingYieldClaimer",
      }),
    (v) => v.toLowerCase() === NEW_CLAIMER.toLowerCase(),
    45000,
  );
  ok(
    pend && pend.toLowerCase() === NEW_CLAIMER.toLowerCase(),
    "pendingYieldClaimer set (finalize gated by 14-day timelock)",
  );

  /* ===================== E. FULL LOOP ON NEW INSTANCE ============ */
  head("E. FULL LOOP ON THE SELF-OWNED INSTANCE");
  head("E1) deposit 500 (native)");
  const nb0 = await N.balanceOf(ADDR);
  await goto("/app/deposit");
  await click("xDAI (native)");
  await page.locator('input[inputmode="decimal"]').fill("500");
  await page.waitForTimeout(400);
  await click("Deposit");
  const nbD = await waitFor(
    () => N.balanceOf(ADDR),
    (v) => v > nb0,
  );
  ok(nbD - nb0 === 500n * ONE, "minted 500 CSTAKE on new instance");
  // Let time-weighted voting power accrue (it's ~0 right at deposit — the UI
  // correctly blocks a zero-power vote until then).
  await fork.mine(20);

  head("E2) vote (single recipient R1)");
  await goto("/app/vote", 2000);
  await page.locator('input[inputmode="numeric"]').first().fill("50");
  await page.waitForTimeout(400);
  await click("Cast vote");
  ok(
    (await waitFor(
      () => N.hasVoted(ADDR),
      (v) => v === true,
    )) === true,
    "hasVoted on new instance",
  );

  head("E3) force yield + complete the 50-block cycle");
  await fork.forceYield(2000n * ONE);
  await fork.mine(60);
  ok(
    (await waitFor(
      () => N.isDistributionReady(),
      (v) => v === true,
      20000,
    )) === true,
    "isDistributionReady on new instance",
  );

  head("E4) distribute -> cycle advances, recipient paid");
  const rb0 = await N.balanceOf(R1);
  cyc0 = await N.currentCycle();
  await goto("/app/distribute", 2000);
  await click("Claim & distribute");
  cyc1 = await waitFor(
    () => N.currentCycle(),
    (v) => v > cyc0,
    60000,
  );
  ok(cyc1 === cyc0 + 1n, `new-instance cycle advanced ${cyc0} -> ${cyc1}`);
  ok((await N.balanceOf(R1)) > rb0, "recipient R1 received distribution");

  head("E5) withdraw 200 on new instance -> burn");
  const eb0 = await N.balanceOf(ADDR);
  await goto("/app/withdraw");
  await page.locator('input[inputmode="decimal"]').fill("200");
  await page.waitForTimeout(400);
  await click("Withdraw to xDAI");
  const eb1 = await waitFor(
    () => N.balanceOf(ADDR),
    (v) => v < eb0,
  );
  ok(eb0 - eb1 === 200n * ONE, "burned exactly 200 CSTAKE on new instance");

  console.log(
    `\n=== ${fail === 0 ? "\x1b[32mALL PATHS PASS\x1b[0m" : "\x1b[31mFAIL\x1b[0m"} (${pass} ok, ${fail} fail) ===`,
  );
  await browser.close();
  process.exit(fail === 0 ? 0 : 1);
})().catch((e) => {
  console.error("FATAL", e);
  process.exit(1);
});
