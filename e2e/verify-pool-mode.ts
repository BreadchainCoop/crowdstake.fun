/*
 * On-chain verification for POOL MODE (issueToken=false deploys) through the
 * frontend's OWN ABIs — any drift between the dapp and the contracts fails
 * here first. It proves the ABI-compatibility contract the UI leans on: every
 * read/write the app does on `instance.token` (balanceOf/totalSupply/decimals/
 * name/symbol, yieldAccrued/yieldSplitOf/keptYieldOf/setYieldSplit, and the
 * same mint/burn deposit-withdraw signatures) works against a StakePool, the
 * `isPool()` probe feature-detects the kind exactly like useInstanceKind, and
 * the pool exposes NO transfer/approve/allowance surface.
 *
 * Needs a deployer that supports the appended `issueToken` param (the sibling
 * pool-mode contracts branch) — pass its address via DEPLOYER. Run against an
 * anvil fork of Gnosis:
 *   anvil --fork-url https://gnosis-rpc.publicnode.com --chain-id 100 --port 8547
 *   DEPLOYER=0x… RPC_URL=http://localhost:8547 npx tsx e2e/verify-pool-mode.ts
 *
 * What it proves:
 *   1. deploy() with issueToken=false succeeds; SystemDeployed carries the
 *      pool address in the Instance tuple's `token` slot
 *   2. isPool() returns true on the pool — and REVERTS on a classic token
 *      instance (deployed with issueToken=true in the same run), so the UI's
 *      success+true → "pool" / revert → "token" probe is sound both ways
 *   3. name() is the instance name; symbol() is the UNDERLYING asset's (the
 *      deploy passed "", as the wizard does in pool mode); decimals() readable
 *   4. mint(receiver){value} deposits: balanceOf/totalSupply == the deposit
 *   5. yieldAccrued/totalYieldAccrued/yieldSplitOf/keptYieldOf all read;
 *      setYieldSplit(2500) round-trips through yieldSplitOf
 *   6. burn(amount, receiver) withdraws: balance drops, native comes back
 *   7. transfer/approve/allowance (ERC-20 selectors) all revert on the pool —
 *      no transfer surface exists
 */
import {
  createPublicClient,
  createWalletClient,
  decodeEventLog,
  encodePacked,
  erc20Abi,
  http,
  keccak256,
  parseEther,
  type Address,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { gnosis } from "viem/chains";
import { deployerAbi } from "../src/lib/abis/crowdstake-deployer";
import { tokenAbi } from "../src/lib/abis/token";
import { poolAbi } from "../src/lib/abis/pool";

const RPC = process.env.RPC_URL ?? "http://localhost:8547";
// The pool-mode-capable deployer (from the sibling contracts branch) — there
// is no live one yet, so it MUST be provided.
const DEPLOYER = process.env.DEPLOYER as Address | undefined;
if (!DEPLOYER) {
  console.error(
    "Set DEPLOYER to a pool-mode-capable CrowdStakeDeployer address (deploy the contracts branch onto the fork first).",
  );
  process.exit(2);
}
// anvil dev account #0 — publicly known, auto-funded on the fork. NEVER a real key.
const account = privateKeyToAccount(
  "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
);
const R1: Address = "0x1111111111111111111111111111111111111111";
const R2: Address = "0x2222222222222222222222222222222222222222";

const pub = createPublicClient({ chain: gnosis, transport: http(RPC) });
const wallet = createWalletClient({
  account,
  chain: gnosis,
  transport: http(RPC),
});

let failures = 0;
function ok(cond: boolean, label: string): void {
  console.log(`${cond ? "  ✔" : "  ✘ FAIL"} ${label}`);
  if (!cond) failures += 1;
}

/** Deploy one instance via the frontend deployer ABI; returns the token slot. */
async function deployInstance(issueToken: boolean): Promise<Address> {
  const salt = keccak256(
    encodePacked(["string"], [`pool-mode-${issueToken}-${Date.now()}`]),
  );
  const hash = await wallet.writeContract({
    address: DEPLOYER!,
    abi: deployerAbi,
    functionName: "deploy",
    args: [
      {
        owner: account.address,
        cycleLength: 200_000n,
        tokenName: issueToken ? "PoolModeToken" : "Pool Mode Community",
        // The wizard passes "" for pools (the pool's symbol() is the
        // UNDERLYING's) and a real ticker for token instances.
        tokenSymbol: issueToken ? "PMT" : "",
        maxVotingPoints: 10_000n,
        salt,
        registryKind: 0,
        initialRecipients: [R1, R2],
        proposalExpiry: 0n,
        distributionKind: 0,
        tokenImageURI: "",
        bannerImageURI: "",
        crossChain: false,
        issueToken,
      },
    ],
  });
  const receipt = await pub.waitForTransactionReceipt({ hash });
  ok(
    receipt.status === "success",
    `deploy(issueToken=${issueToken}) succeeded (${hash})`,
  );
  for (const log of receipt.logs) {
    try {
      const ev = decodeEventLog({
        abi: deployerAbi,
        data: log.data,
        topics: log.topics,
      });
      if (ev.eventName === "SystemDeployed") return ev.args.instance.token;
    } catch {
      /* not our event */
    }
  }
  throw new Error("SystemDeployed not found in deploy receipt");
}

/** Mirrors useInstanceKind: success+true → pool, revert → token. */
async function probeKind(addr: Address): Promise<"pool" | "token"> {
  try {
    const val = await pub.readContract({
      address: addr,
      abi: poolAbi,
      functionName: "isPool",
    });
    return val ? "pool" : "token";
  } catch {
    return "token";
  }
}

async function main(): Promise<void> {
  console.log(`depositor: ${account.address}`);
  console.log(`deployer:  ${DEPLOYER}`);

  /* 1 — pool deploy (issueToken=false, the app default). */
  const pool = await deployInstance(false);
  console.log(`  pool (Instance.token slot): ${pool}`);

  /* 2 — kind probe, both ways. */
  ok((await probeKind(pool)) === "pool", "isPool() → true: kind = pool");
  const token = await deployInstance(true);
  console.log(`  classic token instance:     ${token}`);
  ok(
    (await probeKind(token)) === "token",
    "classic instance: isPool() reverts (or false) — kind = token",
  );

  /* 3 — identity reads through the compat surface (tokenAbi). */
  const name = await pub.readContract({
    address: pool,
    abi: tokenAbi,
    functionName: "name",
  });
  ok(name === "Pool Mode Community", `name() is the instance name ("${name}")`);
  const symbol = await pub.readContract({
    address: pool,
    abi: tokenAbi,
    functionName: "symbol",
  });
  ok(
    symbol.length > 0 && symbol !== "PMT",
    `symbol() is the UNDERLYING asset's ("${symbol}"), not the deploy param ("")`,
  );
  const decimals = await pub.readContract({
    address: pool,
    abi: tokenAbi,
    functionName: "decimals",
  });
  ok(decimals === 18, `decimals() == 18 on the Gnosis fork (got ${decimals})`);

  /* 4 — deposit via the SAME mint signature the app uses (native path). */
  const depositWei = parseEther("10");
  const mintHash = await wallet.writeContract({
    address: pool,
    abi: tokenAbi,
    functionName: "mint",
    args: [account.address],
    value: depositWei,
  });
  await pub.waitForTransactionReceipt({ hash: mintHash });
  const bal = await pub.readContract({
    address: pool,
    abi: tokenAbi,
    functionName: "balanceOf",
    args: [account.address],
  });
  ok(bal === depositWei, `balanceOf == deposit (${bal})`);
  const supply = await pub.readContract({
    address: pool,
    abi: tokenAbi,
    functionName: "totalSupply",
  });
  ok(supply === depositWei, `totalSupply == deposit (${supply})`);

  /* 5 — yield surface reads + split round-trip. */
  const yieldAccrued = await pub.readContract({
    address: pool,
    abi: tokenAbi,
    functionName: "yieldAccrued",
  });
  ok(yieldAccrued >= 0n, `yieldAccrued() readable (${yieldAccrued})`);
  const totalYield = await pub.readContract({
    address: pool,
    abi: tokenAbi,
    functionName: "totalYieldAccrued",
  });
  ok(totalYield >= 0n, `totalYieldAccrued() readable (${totalYield})`);
  const splitBefore = await pub.readContract({
    address: pool,
    abi: tokenAbi,
    functionName: "yieldSplitOf",
    args: [account.address],
  });
  ok(splitBefore === 0, `yieldSplitOf() starts at 0 keepBps (${splitBefore})`);
  const setSplitHash = await wallet.writeContract({
    address: pool,
    abi: tokenAbi,
    functionName: "setYieldSplit",
    args: [2500],
  });
  await pub.waitForTransactionReceipt({ hash: setSplitHash });
  const splitAfter = await pub.readContract({
    address: pool,
    abi: tokenAbi,
    functionName: "yieldSplitOf",
    args: [account.address],
  });
  ok(splitAfter === 2500, `setYieldSplit(2500) round-trips (${splitAfter})`);
  const kept = await pub.readContract({
    address: pool,
    abi: tokenAbi,
    functionName: "keptYieldOf",
    args: [account.address],
  });
  ok(kept >= 0n, `keptYieldOf() readable (${kept})`);

  /* 6 — withdraw via the SAME burn signature the app uses. */
  const nativeBefore = await pub.getBalance({ address: account.address });
  const withdrawWei = parseEther("4");
  const burnHash = await wallet.writeContract({
    address: pool,
    abi: tokenAbi,
    functionName: "burn",
    args: [withdrawWei, account.address],
  });
  await pub.waitForTransactionReceipt({ hash: burnHash });
  const balAfter = await pub.readContract({
    address: pool,
    abi: tokenAbi,
    functionName: "balanceOf",
    args: [account.address],
  });
  ok(
    balAfter === depositWei - withdrawWei,
    `balanceOf dropped by the withdrawal (${balAfter})`,
  );
  const nativeAfter = await pub.getBalance({ address: account.address });
  // Withdrew 4 native minus gas — anything > 3.9 proves the payout landed.
  ok(
    nativeAfter - nativeBefore > parseEther("3.9"),
    `native balance rose by ≈ the withdrawal (+${nativeAfter - nativeBefore})`,
  );

  /* 7 — NO transfer surface: every ERC-20 transfer selector must revert. */
  const noSelector = async (
    label: string,
    fn: () => Promise<unknown>,
  ): Promise<void> => {
    try {
      await fn();
      ok(false, `${label} unexpectedly succeeded — pool has a ${label}!`);
    } catch {
      ok(true, `${label} reverts — selector absent`);
    }
  };
  await noSelector("transfer", () =>
    pub.simulateContract({
      account: account.address,
      address: pool,
      abi: erc20Abi,
      functionName: "transfer",
      args: [R1, 1n],
    }),
  );
  await noSelector("approve", () =>
    pub.simulateContract({
      account: account.address,
      address: pool,
      abi: erc20Abi,
      functionName: "approve",
      args: [R1, 1n],
    }),
  );
  await noSelector("allowance", () =>
    pub.readContract({
      address: pool,
      abi: erc20Abi,
      functionName: "allowance",
      args: [account.address, R1],
    }),
  );
  await noSelector("transferFrom", () =>
    pub.simulateContract({
      account: account.address,
      address: pool,
      abi: erc20Abi,
      functionName: "transferFrom",
      args: [account.address, R1, 1n],
    }),
  );

  console.log(failures === 0 ? "\nALL CHECKS PASSED" : `\n${failures} FAILED`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
