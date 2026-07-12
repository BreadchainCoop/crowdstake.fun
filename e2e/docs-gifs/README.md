# /docs walkthrough GIF pipeline

Re-records the nine animated walkthroughs embedded on the `/docs` page
(`public/docs/*.gif`) whenever the UI changes. The clips drive the **real
static export** on a **local anvil fork of Gnosis** with the same env-key
wallet shim as `../onchain-journey` — so every transaction in a clip is a real
transaction (on the fork), end to end, and no key ever enters the app build.

## Run it

```bash
cd e2e/onchain-journey && npm install   # playwright + viem (shared)
cd ../docs-gifs && npm install          # gifenc + pngjs (encoder)
npm run record                          # ≈10 min: fork + build + capture + encode
```

`run.sh` brings up the fork, deploys the canonical CrowdStakeDeployer to it,
builds the static export pointed at the fork, serves `out/`, captures each
flow's frames with Playwright (step badge + click-ring overlay), downscales
with `sips`, encodes with gifenc (global palette + inter-frame transparency
diff — ffmpeg-free), and copies the results into `public/docs/`.

Re-record a single flow:

```bash
FLOWS=deploy npm run record
```

## Why this shape

- **Playwright + gifenc, not the browser-extension recorder or ffmpeg**: the
  MCP recorder can't capture tabs it doesn't own, and ffmpeg's brew install
  breaks whenever its dylibs move. Pure-JS encoding always works.
- **Fork, not production**: clips can show the *complete* flow — deposit,
  vote, distribute, deploy — with confirmed transactions, using real forked
  Gnosis state for balances/yield, without touching real funds.
- Playwright + viem are **reused from `../onchain-journey/node_modules`** so
  the two harnesses can't drift apart; this package only adds the encoder.
