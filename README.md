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

## Releases

Contracts are released independently — see [GitHub Releases](https://github.com/BreadchainCoop/crowdstake.fun/releases) (latest: `v0.0.2`).
