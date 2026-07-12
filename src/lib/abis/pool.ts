import { parseAbi } from "viem";

/**
 * StakePool — the no-token instance kind. The pool is deliberately
 * ABI-compatible with every read the app already does on `instance.token`
 * (balanceOf/totalSupply/decimals/name/symbol, yieldAccrued/totalYieldAccrued,
 * yieldSplitOf/keptYieldOf/claimKeptYield/setYieldSplit, and the same
 * mint/burn deposit-withdraw signatures), so those calls keep using tokenAbi.
 * This ABI carries only the pool's EXTRA surface: the `isPool()` probe the UI
 * feature-detects the kind with (token instances revert on it — the same
 * pattern as useYieldSplit's `supported`), and the Deposited/Withdrawn events
 * a pool emits instead of ERC-20 Transfer events (a pool has no
 * transfer/approve/allowance at all).
 */
export const poolAbi = parseAbi([
  "function isPool() view returns (bool)",
  "event Deposited(address indexed receiver, uint256 amount)",
  "event Withdrawn(address indexed receiver, uint256 amount)",
]);
