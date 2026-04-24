# Fuzz tests (Phase 1)

These tests use Foundry `testFuzz_*` against real protocol contracts with **local mocks only** (no `vm.createSelectFork` here).

## Run

```bash
# Fuzz tests only — uses root `foundry.toml` `[profile.default]` fuzz settings (same locally and in CI)
forge test --match-path 'test/fuzz/**' -vv
```

## CI

Workflow **`env: FOUNDRY_PROFILE: ci`** is kept for the repo’s convention. Root **`foundry.toml` has no `[profile.ci]`**, so jobs use the same **`[profile.default]`** fuzz run count as local.

The parallel **`fuzz`** job runs only `forge test --match-path 'test/fuzz/**'` (same profile as `check`).

Vendored `lib/**/foundry.toml` files are not modified.

## Fork tests

Fork-based suites live in `test/TestWrapper.sol` and friends, not under `test/fuzz/`.
