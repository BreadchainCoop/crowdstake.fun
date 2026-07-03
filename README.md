# crowdstake.fun

Community-powered funding protocol — turn any pool of money into an
interest-generating engine for your group's shared goals.

This is a monorepo:

| Path         | What                                                                                                                                                             |
| ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `/` (root)   | **Next.js frontend** — landing page + dapp (App Router, React 19, Tailwind v4, [`@breadcoop/ui`](https://github.com/BreadchainCoop/bread-ui-kit) design system). |
| `contracts/` | **Foundry smart contracts** — the on-chain protocol (distribution, voting, automation, registries).                                                              |

## Quick start

**Frontend** (from repo root):

```bash
pnpm install
pnpm dev            # http://localhost:3001
```

**Contracts** (from `contracts/`):

```bash
forge build
forge test
```

See [AGENTS.md](./AGENTS.md) for architecture, conventions, and the full command list.

## Live deployment (Gnosis Chain)

A full working instance is deployed on Gnosis mainnet (chain 100). The dapp at
`/app` is wired to it out of the box. Addresses are in
[`contracts/deployments/gnosis.json`](./contracts/deployments/gnosis.json) and
default in `src/lib/constants.ts` (override with `NEXT_PUBLIC_*` env vars):

| Contract             | Address                                      |
| -------------------- | -------------------------------------------- |
| Token (`CSTAKE`)     | `0x7E94a840143E3D5C78f367bBe45e6fB6e55098ec` |
| Distribution Manager | `0xB38B15ad418202D3FdC1A139cEc51A8c13f59CB6` |
| Cycle Module         | `0xDfBDa0C7061276C3B8a08aC38fEdeE63c0B63827` |
| Voting Module        | `0xf921AF0C0fCd4A9dE0F6C58b34b05DBCCf0aAc42` |
| Recipient Registry   | `0x8e61175AbBC31A07237367e356833C83204945C2` |

Deploy your own instance with `contracts/script/DeployGnosis.s.sol` (see the env
vars documented at the top of that script).

## Every instance gets its own page

The dapp is one static bundle that resolves any instance client-side, so every
deployed instance has a standalone shareable link:

```
https://<host>/app/?i=<distributionManager>
```

Opening it resolves the instance on-chain (wiring + artwork + governance kind)
and boots straight into it — no registry, no backend. The deploy-success screen
shows the link plus a QR code.

### Decentralized hosting (IPFS + ENS / eth.limo)

Publish to IPFS **from the browser** — no CI, no repo secrets. Open
`/app/publish`, pick a provider, and the running app pins itself; you get a CID,
gateway URLs, and the `ipfs://` URI for an ENS contenthash.

- **Your IPFS node** — fully account-free: a local [Kubo/IPFS Desktop](https://docs.ipfs.tech/install/ipfs-desktop/)
  node pins and hosts the app itself (one-time CORS config, shown in the UI).
  Keep the node online for gateways to fetch it; fresh content can take a few
  minutes to become fetchable through public gateways.
- **Pinata** — paste a free API key scoped to `pinFileToIPFS` (stays in the tab);
  always-on pinning without running anything.
- **Storacha** — email magic-link sign-in (IPFS + Filecoin, nothing to paste).
  Note: its upload endpoint `up.storacha.network` can be down in DNS; use one of
  the others when it is.

Try it locally (serves the root build so self-pin works exactly as on IPFS):

```
pnpm preview:ipfs        # builds, serves, prints the steps → open /app/publish/
```

Prefer CI? The **Publish to IPFS** workflow (`deploy-ipfs.yml`, manual dispatch)
does the same pin non-interactively with repo secrets `STORACHA_PRINCIPAL` +
`STORACHA_PROOF`. Either way you get:

```
https://<CID>.ipfs.dweb.link/app/?i=<distributionManager>
```

Point an ENS name's contenthash at `ipfs://<CID>` (manual mainnet tx — no keys
in CI) and the app is live at `https://<name>.eth.limo/…`. From there, two ways
to a fully decentralized per-instance page:

1. **Query link** — `https://<name>.eth.limo/app/?i=<dm>`; works immediately.
2. **Branded ENS subdomain** — give an instance its own name (e.g.
   `acme.crowdstake.eth`): set its text record `crowdstake.instance` to the
   instance's distribution-manager address and its contenthash to the same CID.
   The app detects the ENS host at load (`src/lib/ens.ts`, resolved via an
   Ethereum-mainnet RPC, `NEXT_PUBLIC_ENS_RPC_URL`) and boots that instance at
   `https://acme.crowdstake.eth.limo` — a memorable, fully on-chain page.

Only origin-isolated hosts are supported (eth.limo, `<CID>.ipfs.dweb.link`);
path gateways (`/ipfs/<CID>/…`) break absolute asset paths and share origins.
Set the repo var `NEXT_PUBLIC_ENS_HOST` (e.g. `crowdstake.eth`) to surface the
eth.limo link in the share card.

## Releases

Contracts are released independently — see [GitHub Releases](https://github.com/BreadchainCoop/crowdstake.fun/releases) (latest: `v0.0.2`).
