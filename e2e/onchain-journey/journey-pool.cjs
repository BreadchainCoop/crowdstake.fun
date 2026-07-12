/* POOL-MODE journey: drives the REAL UI through the wizard's DEFAULT deploy
 * (no token issued — a StakePool at the instance's token slot) and every user
 * flow against it, asserting each step's on-chain effect via independent reads.
 *
 * Coverage:
 *   P1. Connect (env-key shim).
 *   P2. Deploy with the DEFAULT staking mode: the wizard preselects
 *       "No token (pool)", labels the name field "Community name", and hides
 *       the token-symbol field entirely. Assert isPool() on-chain, and that
 *       the DM pays out the UNDERLYING (baseToken == WXDAI).
 *   P3. ?i= share-link regression: resolving the instance from its DM must
 *       yield the POOL at the token slot (via DM.yieldModule), not WXDAI —
 *       the page header shows the community name, not "Wrapped XDAI".
 *   P4. Recipient admin works identically on a pool instance.
 *   P5. Deposit (native) via the same UI: pool balance == deposit, votes
 *       auto-delegated; the pool-specific "Your deposit:" copy shows.
 *   P6. Vote.
 *   P7. Distribute: cycle advances and the recipient is paid in WXDAI
 *       (the underlying), not in instance units.
 *   P8. Yield split round-trips through the pool (25% preset -> 7500 keepBps
 *       ... give 25 => keep 75).
 *   P9. Withdraw: pool balance drops exactly; over-balance shows the pool
 *       copy ("exceeds your deposit").
 */
const { erc20Abi, parseAbi } = require("viem");
const { chromium } = require("playwright");
const { installShim } = require("./inject.cjs");
const L = require("./lib.cjs");
const { reads, resolveInstance, latestDeployedInstance, fork, account, pub } =
  L;

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
const ONE = 10n ** 18n;
const WXDAI = L.A.WXDAI;
// Distinct from the other journeys' recipients so WXDAI-delta assertions
// can't be polluted by their distributions on the shared fork.
const RP = "0x000000000000000000000000000000000000dd04";

const poolAbi = parseAbi([
  "function isPool() view returns (bool)",
  "function underlyingAsset() view returns (address)",
  "function yieldSplitOf(address) view returns (uint256)",
]);

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

  head("P1) CONNECT");
  await goto("/app", 2500);
  if (await btn("Connect wallet").count()) {
    await btn("Connect wallet").first().click();
    await page.waitForTimeout(1500);
    await page
      .getByRole("button", { name: "Crowdstake Test" })
      .first()
      .click()
      .catch(() => {});
    await page.waitForTimeout(3000);
  }
  ok((await btn("Connect wallet").count()) === 0, "connected (no prompt)");

  head("P2) DEPLOY with the DEFAULT staking mode (pool)");
  await goto("/app/deploy");
  ok(
    (await page.getByText("No token is issued", { exact: false }).count()) > 0,
    "wizard preselects pool mode (default)",
  );
  ok(
    (await page.getByText("Community name", { exact: true }).count()) > 0,
    'name field is labeled "Community name" in pool mode',
  );
  ok(
    (await page.getByPlaceholder("ACME", { exact: true }).count()) === 0,
    "token-symbol field hidden in pool mode",
  );
  await page
    .getByPlaceholder("Acme Community Stake")
    .fill("Harbor Pool Collective");
  await page.getByPlaceholder("e.g. 24").fill("5");
  await page.getByRole("combobox").selectOption("minutes");
  await page.waitForTimeout(400);
  // Snapshot BEFORE submitting: earlier journeys deployed on this same fork,
  // and an unbounded scan would match their (token) instance instantly.
  const b0 = await pub.getBlockNumber();
  await click("Deploy instance");
  const deployed = await waitFor(
    () => latestDeployedInstance(ADDR, b0),
    (v) => v !== null,
    90000,
  );
  ok(deployed !== null, "SystemDeployed emitted");
  const isPool = await pub
    .readContract({
      address: deployed.token,
      abi: poolAbi,
      functionName: "isPool",
    })
    .catch(() => false);
  ok(isPool === true, "token slot is a StakePool (isPool() == true)");
  const P = reads(await resolveInstance(deployed.distributionManager));
  const baseToken = await pub.readContract({
    address: deployed.distributionManager,
    abi: parseAbi(["function baseToken() view returns (address)"]),
    functionName: "baseToken",
  });
  ok(
    baseToken.toLowerCase() === WXDAI.toLowerCase(),
    "DM pays out the UNDERLYING (baseToken == WXDAI)",
  );

  head("P3) ?i= share-link resolves the POOL, not WXDAI");
  ok(
    P.inst.token.toLowerCase() === deployed.token.toLowerCase(),
    "resolveInstance(dm) token slot == the pool (via DM.yieldModule)",
  );
  await goto(`/app/?i=${deployed.distributionManager}`, 3500);
  ok(
    (await page.getByText("Harbor Pool Collective").count()) > 0,
    "share link renders the community name",
  );
  ok(
    (await page.getByText(/Wrapped XDAI/i).count()) === 0,
    "share link does NOT mislabel the instance as Wrapped XDAI",
  );

  head("P4) recipient admin on the pool instance");
  const recs0 = (await P.recipients()).length;
  ok(recs0 === 0, "fresh pool instance starts with zero recipients");
  await goto("/app/recipients", 2000);
  await page.getByPlaceholder("0x… recipient address").fill(RP);
  await click("Add");
  await page.waitForTimeout(300);
  await click("Queue additions");
  await waitFor(
    () => P.queuedAdditions(),
    (q) => q.length === 1,
    60000,
  );
  await click("Process queue");
  const recs = await waitFor(
    () => P.recipients(),
    (v) => v.length === recs0 + 1,
    60000,
  );
  ok(
    recs.length === recs0 + 1 &&
      recs.map((x) => x.toLowerCase()).includes(RP.toLowerCase()),
    "recipient queued + processed on pool instance",
  );

  head("P5) deposit 500 xDAI (native) into the pool");
  const pb0 = await P.balanceOf(ADDR);
  await goto("/app/deposit");
  ok(
    (await page.getByText("Your deposit:", { exact: false }).count()) > 0,
    'pool copy shows ("Your deposit:", no token framing)',
  );
  await click("xDAI (native)");
  await page.locator('input[inputmode="decimal"]').fill("500");
  await page.waitForTimeout(400);
  await click("Deposit");
  const pbD = await waitFor(
    () => P.balanceOf(ADDR),
    (v) => v > pb0,
  );
  ok(pbD - pb0 === 500n * ONE, "pool tracks exactly the 500 deposited");
  ok((await P.getVotes(ADDR)) >= 500n * ONE, "votes auto-delegated (>=500)");
  ok(
    (await P.delegates(ADDR)).toLowerCase() === ADDR.toLowerCase(),
    "self-delegated on deposit",
  );
  // Let time-weighted voting power accrue before voting.
  await fork.mine(20);

  head("P6) vote (single recipient)");
  await goto("/app/vote", 2000);
  await page.locator('input[inputmode="numeric"]').first().fill("50");
  await page.waitForTimeout(400);
  await click("Cast vote");
  ok(
    (await waitFor(
      () => P.hasVoted(ADDR),
      (v) => v === true,
    )) === true,
    "hasVoted on pool instance",
  );

  head("P7) distribute -> recipient paid in WXDAI (the underlying)");
  await fork.forceYield(2000n * ONE);
  await fork.mine(60);
  ok(
    (await waitFor(
      () => P.isDistributionReady(),
      (v) => v === true,
      20000,
    )) === true,
    "isDistributionReady",
  );
  const wx0 = await wxBalance(RP);
  const cyc0 = await P.currentCycle();
  await goto("/app/distribute", 2000);
  await click("Claim & distribute");
  const cyc1 = await waitFor(
    () => P.currentCycle(),
    (v) => v > cyc0,
    60000,
  );
  ok(cyc1 === cyc0 + 1n, `cycle advanced ${cyc0} -> ${cyc1}`);
  ok(
    (await wxBalance(RP)) > wx0,
    "recipient received WXDAI (underlying), not instance units",
  );

  head("P8) yield split round-trips on the pool");
  await goto("/app/yield", 2000);
  await click("25%"); // give 25 => keep 75 => 7500 keepBps
  await page.waitForTimeout(300);
  await click("Update split");
  const split = await waitFor(
    () =>
      pub.readContract({
        address: P.inst.token,
        abi: poolAbi,
        functionName: "yieldSplitOf",
        args: [ADDR],
      }),
    (v) => v === 7500n,
    45000,
  );
  ok(split === 7500n, "yieldSplitOf == 7500 keepBps after Update split");

  head("P9) withdraw 200 from the pool");
  await goto("/app/withdraw");
  await page.locator('input[inputmode="decimal"]').fill("99999999");
  await page.waitForTimeout(500);
  ok(
    (await page.getByText(/exceeds your deposit/i).count()) > 0,
    'over-balance shows the pool copy ("exceeds your deposit")',
  );
  const wb0 = await P.balanceOf(ADDR);
  await page.locator('input[inputmode="decimal"]').fill("200");
  await page.waitForTimeout(400);
  await click("Withdraw to xDAI");
  const wb1 = await waitFor(
    () => P.balanceOf(ADDR),
    (v) => v < wb0,
  );
  ok(wb0 - wb1 === 200n * ONE, "pool balance dropped by exactly 200");

  console.log(
    `\n=== ${fail === 0 ? "\x1b[32mPOOL JOURNEY PASS\x1b[0m" : "\x1b[31mFAIL\x1b[0m"} (${pass} ok, ${fail} fail) ===`,
  );
  await browser.close();
  process.exit(fail === 0 ? 0 : 1);
})().catch((e) => {
  console.error("FATAL", e);
  process.exit(1);
});
