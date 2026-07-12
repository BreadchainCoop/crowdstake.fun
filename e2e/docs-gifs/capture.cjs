/* Captures the /docs walkthrough GIF frames by driving the REAL static export
 * on a local anvil Gnosis fork with the onchain-journey wallet shim — every
 * transaction shown in a clip is a real, confirmed transaction (on the fork).
 *
 * Run via run.sh (which brings up the fork + build + server), or standalone
 * against an already-running stack:
 *   TEST_RPC_URL=http://localhost:8546 TEST_BASE_URL=http://localhost:4173 \
 *   node capture.cjs [flow]
 *
 * Flows: landing-tour connect-wallet deposit vote distribute withdraw
 *        deploy recipients instance-switcher      (deploy → recipients →
 *        instance-switcher share one browser context: the last two need the
 *        self-owned instance the deploy flow creates and activates.)
 */
const path = require("path");
const fs = require("fs");

// Reuse the journey harness's deps + shim so the two can't drift apart.
const OJ = path.resolve(__dirname, "../onchain-journey");
const { chromium } = require(path.join(OJ, "node_modules/playwright"));
const { installShim } = require(path.join(OJ, "inject.cjs"));
const L = require(path.join(OJ, "lib.cjs"));
const { fork } = L;

const BASE = process.env.TEST_BASE_URL || "http://localhost:4173";
const ONE = 10n ** 18n;
const NEW_RECIPIENT = "0x000000000000000000000000000000000000dd05";

function resolveChromium() {
  if (process.env.PW_EXECUTABLE_PATH) return process.env.PW_EXECUTABLE_PATH;
  const os = require("os");
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

/* ---------------- overlay: step badge + orange click ring ---------------- */
async function installOverlay(page) {
  await page
    .addStyleTag({
      content: `
    #gif-badge{position:fixed;left:50%;bottom:26px;transform:translateX(-50%);z-index:99999;
      background:#1c1917;color:#fff;font:600 15px Archivo,system-ui,sans-serif;padding:9px 18px;
      border-radius:999px;box-shadow:0 6px 24px rgba(0,0,0,.28);max-width:82vw;white-space:nowrap;}
    #gif-ring{position:fixed;z-index:99998;width:44px;height:44px;border:3px solid #EA5817;border-radius:50%;
      pointer-events:none;box-shadow:0 0 0 5px rgba(234,88,23,.28);display:none;}`,
    })
    .catch(() => {});
  await page.evaluate(() => {
    if (!document.getElementById("gif-badge")) {
      const b = document.createElement("div");
      b.id = "gif-badge";
      b.style.display = "none";
      document.body.appendChild(b);
    }
    if (!document.getElementById("gif-ring")) {
      const r = document.createElement("div");
      r.id = "gif-ring";
      document.body.appendChild(r);
    }
  });
}
const badge = (page, text) =>
  page.evaluate((t) => {
    const b = document.getElementById("gif-badge");
    if (!b) return;
    b.textContent = t;
    b.style.display = t ? "block" : "none";
  }, text);
const ringAt = (page, x, y, show = true) =>
  page.evaluate(
    ({ x, y, show }) => {
      const r = document.getElementById("gif-ring");
      if (!r) return;
      r.style.left = x - 22 + "px";
      r.style.top = y - 22 + "px";
      r.style.display = show ? "block" : "none";
    },
    { x, y, show },
  );

/* ------------------------------- frame kit ------------------------------- */
function frameSink(flow) {
  const dir = path.join(__dirname, "frames", flow);
  fs.rmSync(dir, { recursive: true, force: true });
  fs.mkdirSync(dir, { recursive: true });
  let n = 0;
  return {
    dir,
    flow,
    async shot(page, copies = 1) {
      const f = path.join(dir, `${String(n).padStart(3, "0")}.png`);
      await page.screenshot({ path: f });
      for (let i = 1; i < copies; i++)
        fs.copyFileSync(f, path.join(dir, `${String(n + i).padStart(3, "0")}.png`));
      n += copies;
    },
  };
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function clickWithRing(page, sink, locator, holdBefore = 2) {
  const el = locator.first();
  await el.scrollIntoViewIfNeeded();
  const box = await el.boundingBox();
  if (box)
    await ringAt(page, box.x + box.width / 2, box.y + box.height / 2, true);
  await sink.shot(page, holdBefore);
  await el.click();
  await ringAt(page, 0, 0, false);
}
// Flows must not silently produce false recordings: a clip that captions an
// unconfirmed transaction as done is worse than no clip. Every missed success
// label is collected here and fails the run at the end.
const problems = [];

// Wait for a tx success label (string or RegExp — pass a label UNIQUE to the
// success toast, not a substring of static page text), screenshotting so the
// pending state shows. Records a problem on timeout.
async function waitSuccess(page, sink, text, ms = 90000) {
  const t = Date.now();
  while (Date.now() - t < ms) {
    if ((await page.getByText(text, { exact: false }).count()) > 0) return true;
    await sink.shot(page, 1);
    await sleep(700);
  }
  problems.push(`${sink.flow}: success label ${text} never appeared`);
  return false;
}

async function newContext(browser, { shim = true } = {}) {
  const context = await browser.newContext({
    viewport: { width: 1280, height: 800 },
  });
  // The shim preseeds wagmi, so pages open already connected. The connect
  // flow's "not yet connected" shots come from PRODUCTION instead (the Privy
  // modal only opens on allowlisted origins — never on localhost).
  if (shim) await installShim(context);
  return context;
}
async function openPage(context, urlPath, settle = 2500) {
  const page = await context.newPage();
  // "load", not "networkidle": the app polls its RPCs continuously (and a
  // rate-limited fork upstream answers slowly), so the network never idles.
  page.setDefaultNavigationTimeout(60000);
  await page.goto(BASE + urlPath, { waitUntil: "load" });
  await page.waitForTimeout(settle);
  await installOverlay(page);
  return page;
}
const gotoAndOverlay = async (page, urlPath, settle = 2200) => {
  await page.goto(BASE + urlPath, { waitUntil: "load" });
  await page.waitForTimeout(settle);
  await installOverlay(page);
};

(async () => {
  const only = process.env.FLOWS || process.argv[2];
  const want = (f) => !only || only.split(",").includes(f);
  const browser = await chromium.launch({
    headless: true,
    ...(resolveChromium() ? { executablePath: resolveChromium() } : {}),
  });

  /* landing-tour — no wallet, just the pitch. */
  if (want("landing-tour")) {
    const sink = frameSink("landing-tour");
    const context = await newContext(browser, { shim: false });
    const page = await openPage(context, "/", 3000);
    await badge(page, "Crowdstake — a community fund powered by staking yield");
    await sink.shot(page, 6);
    await page.mouse.wheel(0, 560);
    await sleep(400);
    await badge(page, "Size your fund: target a monthly amount, see the stake needed");
    await sink.shot(page, 6);
    await page.mouse.wheel(0, 640);
    await sleep(400);
    await badge(page, "Deposit → yield → vote → distribute, on a fixed cycle");
    await sink.shot(page, 6);
    await page.mouse.wheel(0, 700);
    await sleep(400);
    await sink.shot(page, 5);
    await context.close();
    console.log("captured landing-tour");
  }

  /* connect-wallet — hybrid: the Privy modal only opens on allowlisted
   * origins (crowdstake.fun, not localhost), so the modal shots come from
   * PRODUCTION (read-only: open the modal, hold, Escape — nothing entered,
   * nothing signed), and the connected end-state comes from the fork stack
   * with the preseeded shim. */
  if (want("connect-wallet")) {
    const sink = frameSink("connect-wallet");
    {
      const context = await browser.newContext({
        viewport: { width: 1280, height: 800 },
      });
      const page = await context.newPage();
      // NOT networkidle: the app polls its RPCs continuously, so production
      // never goes network-quiet — wait for the connect button instead.
      await page.goto("https://crowdstake.fun/app/", {
        waitUntil: "domcontentloaded",
      });
      await page
        .getByRole("button", { name: "Connect wallet" })
        .first()
        .waitFor({ timeout: 60000 });
      await page.waitForTimeout(1500);
      await installOverlay(page);
      await badge(page, "Every page is browsable read-only — connect only to act");
      await sink.shot(page, 5);
      const connectBtn = page.getByRole("button", { name: "Connect wallet" });
      await connectBtn.first().waitFor({ timeout: 45000 });
      await clickWithRing(page, sink, connectBtn, 3);
      await sleep(2500);
      await installOverlay(page);
      await badge(page, "Email, passkey, or any wallet — pick one to sign in");
      await sink.shot(page, 8);
      await page.keyboard.press("Escape");
      await context.close();
    }
    {
      const context = await newContext(browser); // preseeded = connected
      const page = await openPage(context, "/app/", 4000);
      await badge(page, "Connected on Gnosis — your portfolio loads");
      await sink.shot(page, 7);
      await context.close();
    }
    console.log("captured connect-wallet");
  }

  /* The action flows share one auto-connected context (state builds on the
   * fork: deposit → vote → distribute → withdraw). */
  if (["deposit", "vote", "distribute", "withdraw"].some(want)) {
    const context = await newContext(browser);
    const page = await openPage(context, "/app/");

    if (want("deposit")) {
      const sink = frameSink("deposit");
      await gotoAndOverlay(page, "/app/deposit/");
      await badge(page, "Deposit — stake xDAI; principal stays withdrawable");
      await sink.shot(page, 5);
      await clickWithRing(
        page,
        sink,
        page.getByRole("button", { name: "xDAI (native)", exact: true }),
        2,
      );
      await sleep(400);
      await page.locator('input[inputmode="decimal"]').fill("100");
      await sink.shot(page, 3);
      await clickWithRing(
        page,
        sink,
        page.getByRole("button", { name: "Deposit", exact: true }),
        3,
      );
      await waitSuccess(page, sink, "Deposit confirmed");
      await badge(page, "Deposited — 100 staked, votes self-delegated");
      await sink.shot(page, 6);
      console.log("captured deposit");
    }

    if (want("vote")) {
      const sink = frameSink("vote");
      // Voting power is time-weighted (~0 right after the deposit) and anvil
      // only mines per-tx — advance blocks so Cast vote enables.
      await fork.mine(30);
      await gotoAndOverlay(page, "/app/vote/");
      await badge(page, "Vote — weight the recipients of the next distribution");
      await sink.shot(page, 5);
      const steppers = page.locator('input[inputmode="numeric"]');
      await steppers.nth(0).fill("70");
      await sink.shot(page, 3);
      await steppers.nth(1).fill("30");
      await sink.shot(page, 3);
      await clickWithRing(
        page,
        sink,
        page.getByRole("button", { name: "Cast vote", exact: true }),
        3,
      );
      // NOT the bare string "Vote" — that matches the always-present page
      // title and would turn this wait into a no-op.
      await waitSuccess(page, sink, /Vote (cast|updated)/);
      await badge(page, "Vote cast — counted for the current cycle");
      await sink.shot(page, 6);
      console.log("captured vote");
    }

    if (want("distribute")) {
      const sink = frameSink("distribute");
      // Push some yield into the vault so the clip shows a real number.
      await fork.forceYield(500n * ONE);
      await fork.mine(30);
      await gotoAndOverlay(page, "/app/distribute/");
      await badge(page, "Distribute — anyone can trigger it once the cycle completes");
      await sink.shot(page, 6);
      await clickWithRing(
        page,
        sink,
        page.getByRole("button", { name: "Claim & distribute", exact: true }),
        3,
      );
      await waitSuccess(page, sink, "Distributed — cycle advanced");
      await badge(page, "Yield distributed by vote share — a fresh cycle begins");
      await sink.shot(page, 6);
      console.log("captured distribute");
    }

    if (want("withdraw")) {
      const sink = frameSink("withdraw");
      await gotoAndOverlay(page, "/app/withdraw/");
      await badge(page, "Withdraw — redeem your principal 1:1, any time");
      await sink.shot(page, 5);
      await page.locator('input[inputmode="decimal"]').fill("50");
      await sink.shot(page, 3);
      await clickWithRing(
        page,
        sink,
        page.getByRole("button", { name: "Withdraw to xDAI", exact: true }),
        3,
      );
      await waitSuccess(page, sink, "Withdrawal confirmed");
      await badge(page, "Withdrawn — 50 xDAI back in your wallet");
      await sink.shot(page, 6);
      console.log("captured withdraw");
    }
    await context.close();
  }

  /* deploy → recipients → instance-switcher: one context — the last two run
   * on the self-owned instance the deploy flow creates + activates. */
  if (["deploy", "recipients", "instance-switcher"].some(want)) {
    const context = await newContext(browser);
    const page = await openPage(context, "/app/deploy/");

    {
      const sink = frameSink("deploy");
      await badge(page, "Deploy your own community — one transaction");
      await sink.shot(page, 5);
      await badge(page, "Staking mode: no token by default — deposits are simply tracked");
      await sink.shot(page, 5);
      await clickWithRing(
        page,
        sink,
        page.getByRole("button", { name: "Issue a token", exact: true }),
        2,
      );
      await sleep(400);
      await badge(page, "…or issue a transferable ERC-20, redeemable 1:1");
      await sink.shot(page, 5);
      await clickWithRing(
        page,
        sink,
        page.getByRole("button", { name: "No token (pool)", exact: true }),
        2,
      );
      await sleep(400);
      await page
        .getByPlaceholder("Acme Community Stake")
        .fill("Harbor Community Pool");
      await sink.shot(page, 3);
      await page.getByPlaceholder("e.g. 24").fill("5");
      await page.getByRole("combobox").selectOption("minutes");
      await sink.shot(page, 3);
      await badge(page, "Deploy — every contract wired and handed to you");
      await clickWithRing(
        page,
        sink,
        page.getByRole("button", { name: "Deploy instance", exact: true }),
        3,
      );
      const okDeploy = await waitSuccess(page, sink, "Use this instance", 120000);
      await badge(page, "Deployed — registry, voting, cycles, distribution: yours");
      await sink.shot(page, 6);
      console.log("captured deploy", okDeploy ? "" : "(no success panel!)");
    }

    // Activate the fresh instance for the next two flows.
    await page
      .getByRole("button", { name: "Use this instance", exact: true })
      .click()
      .catch(() => {
        problems.push(
          "deploy: 'Use this instance' missing — recipients/switcher flows ran on the wrong instance",
        );
      });
    await sleep(2500);

    if (want("recipients")) {
      const sink = frameSink("recipients");
      await gotoAndOverlay(page, "/app/recipients/");
      await badge(page, "Recipients — the public registry your community funds");
      await sink.shot(page, 5);
      await page.getByPlaceholder("0x… recipient address").fill(NEW_RECIPIENT);
      await sink.shot(page, 3);
      await clickWithRing(
        page,
        sink,
        page.getByRole("button", { name: "Add", exact: true }),
        2,
      );
      await sleep(400);
      await sink.shot(page, 3);
      await clickWithRing(
        page,
        sink,
        page.getByRole("button", { name: "Queue additions", exact: true }),
        3,
      );
      // The success toasts here unmount when the on-chain state refetch
      // re-renders the panels — wait on the STATE transitions instead: the
      // pending-changes card appears once the queue tx confirms, and the
      // active-recipients count flips once processing confirms.
      await waitSuccess(page, sink, "Pending changes");
      await sink.shot(page, 3);
      await clickWithRing(
        page,
        sink,
        page.getByRole("button", { name: "Process queue", exact: true }),
        3,
      );
      await waitSuccess(page, sink, /Active recipients \(1\)/);
      await badge(page, "Processed — the recipient appears on the Vote page");
      await sink.shot(page, 6);
      console.log("captured recipients");
    }

    if (want("instance-switcher")) {
      const sink = frameSink("instance-switcher");
      await gotoAndOverlay(page, "/app/");
      await badge(page, "One dashboard, many communities — switch any time");
      await sink.shot(page, 5);
      // The switcher is the nav's left-most control (the instance badge+name).
      await clickWithRing(page, sink, page.locator("nav button").first(), 2);
      await sleep(600);
      await sink.shot(page, 5);
      await badge(page, "Add any instance by address — or jump between yours");
      await sink.shot(page, 4);
      const row = page.getByRole("button", { name: /CSTAKE/ }).first();
      if (await row.count()) {
        await clickWithRing(page, sink, row, 2);
        await sleep(2500);
        await installOverlay(page);
        await badge(page, "Switched — every page re-reads from the new instance");
        await sink.shot(page, 6);
      }
      console.log("captured instance-switcher");
    }
    await context.close();
  }

  await browser.close();
  for (const f of fs.readdirSync(path.join(__dirname, "frames"))) {
    const n = fs.readdirSync(path.join(__dirname, "frames", f)).length;
    console.log(`  ${f}: ${n} frames`);
  }
  if (problems.length) {
    console.error("\nCAPTURE PROBLEMS — these clips would lie, fix and re-record:");
    for (const p of problems) console.error("  ✗ " + p);
    process.exit(1);
  }
})().catch((e) => {
  console.error("CAPTURE FAIL", e);
  process.exit(1);
});
