# On-chain journey test

A **test-only** harness that drives the **real** Crowdstake UI end to end and
signs every transaction with a key from the environment **instead of a wallet
prompt** — so you can verify the whole on-chain journey doesn't break without
clicking through MetaMask by hand.

It runs against a **local anvil fork of Gnosis** by default: free, repeatable,
and it can force the yield/cycle state needed to exercise distribution.

## What it proves

Each step is performed through the actual app UI (the unmodified static export),
and each is asserted by an **independent** on-chain read — so a green run means
the app's wiring produced the transaction, not the test script:

1. **Connect** — auto-connects via an injected wallet, no prompt, on chain 100.
2. **Deposit** 250 xDAI (native) → mints exactly 250 CSTAKE, auto-delegates votes.
3. **Vote** 70 / 30 → `hasVotedInCurrentCycle` flips true.
4. **Distribute** → `isDistributionReady`, then the cycle advances by one.
5. **Withdraw** 100 → burns exactly 100 CSTAKE.
6. **Deploy** a fresh instance in one tx → `SystemDeployed` resolves to 7
   non-zero contracts owned by the signer.

`run.sh` also uses the canonical **CrowdStakeDeployer** to run
`journey-democratic.cjs`, which drives the democratic (recipient-voted) path:
deploy a `VotingRecipientRegistry`-backed instance, then propose → execute →
process a new recipient through the voting UI, asserting each step on-chain.

## How it works (and why no key reaches the app)

The app ships **zero** test affordances. The harness injects an
[EIP-1193](https://eips.ethereum.org/EIPS/eip-1193) `window.ethereum` shim into
the browser via Playwright `addInitScript`, announced over
[EIP-6963](https://eips.ethereum.org/EIPS/eip-6963) so wagmi/RainbowKit
auto-reconnect it with no modal. The shim is a thin **proxy**: reads are
forwarded to the fork RPC, and signing is delegated to Node
(`window.__csWallet` → `viem` `privateKeyToAccount`). **The private key lives
only in the Node test process — it never enters the page, the Next build graph,
any `NEXT_PUBLIC_*` var, or `out/`.** `run.sh` ends with a grep gate that fails
if the key ever appears in the built bundle.

## Run it

```bash
cd e2e/onchain-journey
npm install          # playwright (+ chromium) and viem, isolated from the app
npx playwright install chromium   # once, if Playwright has no browser cached
npm test             # = bash run.sh
```

`npm test` brings up the fork, builds the static export pointed at it, serves
`out/`, runs the journey, tears everything down, and checks the bundle.

Requirements: `anvil`/`foundry`, `node` 18+, `python3`, and the repo's
`corepack pnpm@9.15.4` build. Override anything via `.env` (see `.env.example`).

## CI

Add a job that runs `e2e/onchain-journey` on PRs. Use a **throwaway** key for
the fork signer (or the default anvil dev key) — **never** a funded/live key,
and never in the Pages build. Keep the `check-bundle.sh` step as a hard gate.

## Extending

Add a step to `journey.cjs`: drive the page, then assert the effect with a read
in `lib.cjs` (`R.*`). Admin flows (recipient queue/process, cycle length, yield
claimer) follow the same pattern against a fresh deployed instance where the
signer is owner.

> The default signer is anvil dev account #0 — a publicly known key, funded only
> on the local fork. It is intentionally not a secret.
