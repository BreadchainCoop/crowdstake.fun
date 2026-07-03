/* Focused e2e for the democratic (VotingRecipientRegistry) flow via CrowdStake
 * DeployerV2. Drives the REAL UI with the env-key wallet: deploy a democratic
 * instance, then propose -> execute -> process a new recipient through the
 * voting UI, asserting on-chain at each step. Requires TEST_DEPLOYER_ADDRESS =
 * a V2 deployer and the app built with NEXT_PUBLIC_DEPLOYER_V2=true. */
const { chromium } = require("playwright");
const { installShim } = require("./inject.cjs");
const L = require("./lib.cjs");
const { vreg, resolveInstance, latestDeployedInstance, account } = L;

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
const R1 = "0x000000000000000000000000000000000000dd01";

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
async function waitFor(fn, pred, ms = 60000, every = 1000) {
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

  head("2) DEPLOY a democratic instance (founder = signer)");
  await page.goto(BASE + "/app/deploy", { waitUntil: "networkidle" });
  await page.waitForTimeout(1500);
  await page.getByPlaceholder("Acme Community Stake").fill("Co-op Fund");
  await page.getByPlaceholder("ACME", { exact: true }).fill("COOP");
  await page.getByPlaceholder("e.g. 24").fill("5");
  await page.getByRole("combobox").selectOption("minutes");
  await click("Democratic"); // registry-kind toggle
  await page.waitForTimeout(500);
  await click("Deploy instance");
  // Wait for the LATEST deployed instance to be a DEMOCRATIC one — proposalExpiry
  // only succeeds on a voting registry (other runs may have deployed admin ones).
  const found = await waitFor(
    async () => {
      const d = await latestDeployedInstance(ADDR);
      if (!d) return undefined;
      const inst = await resolveInstance(d.distributionManager);
      try {
        const expiry = await vreg.proposalExpiry(inst.recipientRegistry);
        return { inst, expiry };
      } catch {
        return undefined;
      }
    },
    (v) => v !== undefined,
    90000,
  );
  ok(found !== undefined, "democratic SystemDeployed emitted");
  const inst = found.inst;
  const reg = inst.recipientRegistry;
  ok(found.expiry > 0n, "registry is democratic (proposalExpiry > 0)");
  const founders = await vreg.recipients(reg);
  ok(
    founders.map((x) => x.toLowerCase()).includes(ADDR.toLowerCase()),
    "signer is a founding recipient",
  );

  head("3) SWITCH to it + open the democratic recipients UI");
  await click("Use this instance");
  await page.waitForTimeout(2500);
  await page.goto(BASE + "/app/recipients", { waitUntil: "networkidle" });
  await page.waitForTimeout(2500);
  ok(
    (await page.getByText("Propose a new recipient").count()) > 0,
    "democratic UI renders (propose card shown)",
  );

  head("4) PROPOSE a recipient");
  await page.getByPlaceholder("0x… candidate address").fill(R1);
  await page.waitForTimeout(300);
  await click("Propose");
  await waitFor(
    () => vreg.proposalCount(reg),
    (v) => v >= 1n,
    60000,
  );
  ok((await vreg.proposalCount(reg)) === 1n, "proposal created");

  head("5) EXECUTE (sole founder => votes == required)");
  await click("Execute");
  await waitFor(
    () => vreg.getProposal(reg, 0),
    (p) => p && p[4] === true, // executed
    60000,
  );
  ok((await vreg.getProposal(reg, 0))[4] === true, "proposal executed");

  head("6) PROCESS queue -> recipient becomes active");
  await click("Process queue");
  const recs = await waitFor(
    () => vreg.recipients(reg),
    (v) => v.length >= 2,
    60000,
  );
  ok(
    recs.map((x) => x.toLowerCase()).includes(R1.toLowerCase()),
    "candidate added to the registry by vote",
  );

  console.log(
    `\n=== ${fail === 0 ? "\x1b[32mDEMOCRATIC FLOW PASS\x1b[0m" : "\x1b[31mFAIL\x1b[0m"} (${pass} ok, ${fail} fail) ===`,
  );
  await browser.close();
  process.exit(fail === 0 ? 0 : 1);
})().catch((e) => {
  console.error("FATAL", e);
  process.exit(1);
});
