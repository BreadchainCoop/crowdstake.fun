# crowdstake.fun — Agent & Contributor Guide

Monorepo: a **Next.js frontend at the repo root** and the **Foundry smart contracts under `contracts/`**.

## Layout

```
/                     Next.js app (App Router) — the frontend
  src/app/            routes (thin page.tsx + colocated _components/)
  src/components/     shared UI (_home/ = landing page)
  src/lib/            utils, env, web3 config (utils.ts = cn)
  package.json        the app (pnpm)
contracts/            Foundry project (the protocol)
  src/ test/ script/  Solidity + tests + deploy scripts
  foundry.toml        contracts build config (FOUNDRY_PROFILE=ci in CI)
.github/workflows/    CI (contracts build/test today; etherform + web deploy to follow)
```

## Stack

- **Next.js 15** (App Router, Turbopack dev), **React 19**, **TypeScript strict**.
- **pnpm 11** (`packageManager` pinned). Path alias `@/* → ./src/*`.
- **Tailwind CSS v4** (CSS-first, no JS config) via `@tailwindcss/postcss`.
- **Design system: `@breadcoop/ui`** (Breadchain bread-ui-kit). Tokens + Pogaca fonts + components come from `@import "@breadcoop/ui/theme"` in `src/app/globals.css`. Prefer its components (`Button`, `Heading1–5`, `Body`, `Logo`, `Chip`) and tokens (`bg-core-orange`, `text-text-standard`, `font-breadDisplay`, etc.). Icons: `@phosphor-icons/react`.
- **Web3**: wagmi v2 + viem + RainbowKit (Gnosis chain). Config in `src/lib/wagmi.ts`, providers in `src/components/providers.tsx`, contract ABIs in `src/lib/abis/`, deployed addresses in `src/lib/constants.ts`, read/write hooks in `src/hooks/`.

## Commands

App (run from repo root):

- `pnpm install`
- `pnpm dev` — dev server on **:3001** (Turbopack)
- `pnpm build` — production build (also the typecheck gate)
- `pnpm lint` / `pnpm lint:fix`
- `pnpm format` / `pnpm format:check`

Contracts (run from `contracts/`):

- `forge build` · `forge test` · `forge fmt --check`
- CI uses `FOUNDRY_PROFILE=ci` and pins Foundry to `1.4.4`.

## Conventions (frontend)

- **kebab-case** file names (`interest-calculator.tsx`); `@/` imports for anything in `src/`.
- **RSC by default**; add `"use client"` only at the leaves that need state/hooks/wallet.
- **Route colocation**: keep `page.tsx` thin; put logic in a colocated `_components/` folder (underscore = ignored by the router).
- **Styling**: Tailwind utilities + `@breadcoop/ui` first; use the `cn` helper (`@/lib/utils`) for conditional classes.
- **Design**: build on the `@breadcoop/ui` design system. Reuse copy/structure from the original Crowdstaking landing page, re-skinned to these tokens.
- **TS**: no `any`; unused vars prefixed `_` or removed.

## Conventions (contracts)

- `forge fmt` must be clean (enforced on PRs). Tests deploy upgradeable contracts **behind `ERC1967Proxy`** (constructors call `_disableInitializers()`).

## Verification gate

- Frontend: `pnpm lint` + `pnpm build` + `pnpm format:check` (no test suite yet) + manual browser check.
- Contracts: `forge fmt --check` + `forge build` + `forge test`.

## Git

- Branch from / target `main`. Conventional Commits without scope (`feat: add x`).
