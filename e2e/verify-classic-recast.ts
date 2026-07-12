/*
 * On-chain verification for CLASSIC vote recasting via the EIP-712 signature
 * path (castVoteWithSignature). EIP-712 parity is the delicate part, so this
 * script imports the EXACT frontend signing helpers (classicVoteDomain,
 * CLASSIC_VOTE_TYPES, classicPointsHash from src/lib/vote-signature) and the
 * app's generated ABIs — any drift between the dapp and the contracts fails
 * here first.
 *
 * Run against an anvil fork of Gnosis (publicnode: rpc.gnosischain.com
 * rate-limits forks):
 *   anvil --fork-url https://gnosis-rpc.publicnode.com --chain-id 100 --port 8547
 *   RPC_URL=http://localhost:8547 npx tsx e2e/verify-classic-recast.ts
 *
 * What it proves:
 *   1. deploy a fresh classic instance via the LIVE v2 deployer (forked state)
 *   2. mint stake, accrue time-weighted power, vote 70/30 via voteWithData
 *   3. a direct re-vote reverts AlreadyVotedInCurrentCycle (why the UI
 *      needs the signature path at all)
 *   4. validateSignature() returns true for the frontend-built signature —
 *      byte-for-byte EIP-712 parity with the contract's assembly hash
 *   5. castVoteWithSignature succeeds and getCurrentVotingDistribution now
 *      shows ONLY the new 10/90 ballot (old 70/30 fully reverted)
 *   6. reusing the nonce reverts NonceAlreadyUsed
 *   7. feature-detect + the OLD live v1 default instance: its module turns
 *      out to EXPOSE the same VOTE_TYPEHASH/castVoteWithSignature (so the
 *      UI's probe enables recast there too) — this section proves the v1
 *      recast also REPLACES the ballot instead of double-counting it
 */
import {
  BaseError,
  ContractFunctionRevertedError,
  createPublicClient,
  createWalletClient,
  decodeEventLog,
  encodePacked,
  http,
  keccak256,
  parseEther,
  type Address,
  type Hex,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { gnosis } from "viem/chains";
import { votingModuleAbi } from "../src/lib/abis/voting-module";
import { tokenAbi } from "../src/lib/abis/token";
import { votingPowerAbi } from "../src/lib/abis/voting-power";
import { recipientRegistryAbi } from "../src/lib/abis/recipient-registry";
import { cycleModuleAbi } from "../src/lib/abis/cycle-module";
import { deployerAbi } from "../src/lib/abis/crowdstake-deployer";
import {
  CLASSIC_VOTE_TYPES,
  classicPointsHash,
  classicVoteDomain,
} from "../src/lib/vote-signature";

const RPC = process.env.RPC_URL ?? "http://localhost:8547";
// Live v2 (family-aware) deployer on Gnosis — present in the forked state.
const DEPLOYER: Address = "0xD9dbc941C5e66D1cC67C6612d221263eD1A27C55";
// The OLD live default instance (v1 modules) — mirrors src/lib/constants.ts.
const V1_VOTING_MODULE: Address = "0xf921AF0C0fCd4A9dE0F6C58b34b05DBCCf0aAc42";
const V1_TOKEN: Address = "0x7E94a840143E3D5C78f367bBe45e6fB6e55098ec";
const V1_POWER: Address = "0x3F477A1FD83F56537BEE5cC05406fF4628e7A399";
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

async function mine(blocks: number): Promise<void> {
  await fetch(RPC, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      jsonrpc: "2.0",
      id: 1,
      method: "anvil_mine",
      params: ["0x" + blocks.toString(16)],
    }),
  });
}

/**
 * Ratio equality up to integer flooring: each allocation is
 * floor(power * points_i / totalPoints), so cross-multiplied sides can differ
 * by a few wei on ~1e18-1e20 magnitudes. 1e6 wei of slack is invisible at
 * that scale but catches any real residue from an unreverted ballot.
 */
function ratioIs(a: bigint, b: bigint, num: bigint, den: bigint): boolean {
  const lhs = a * den;
  const rhs = b * num;
  const diff = lhs > rhs ? lhs - rhs : rhs - lhs;
  return diff <= 1_000_000n;
}

/** Deepest custom-error name out of a viem revert, or "". */
function revertName(e: unknown): string {
  if (e instanceof BaseError) {
    const r = e.walk((err) => err instanceof ContractFunctionRevertedError);
    if (r instanceof ContractFunctionRevertedError)
      return r.data?.errorName ?? "";
  }
  return "";
}

async function main(): Promise<void> {
  console.log(`voter: ${account.address}`);

  /* 1 — deploy a fresh classic instance via the live v2 deployer. */
  const salt = keccak256(
    encodePacked(["string"], [`classic-recast-${Date.now()}`]),
  );
  const deployHash = await wallet.writeContract({
    address: DEPLOYER,
    abi: deployerAbi,
    functionName: "deploy",
    args: [
      {
        owner: account.address,
        cycleLength: 200_000n, // long cycle: the ballot stays open throughout
        tokenName: "RecastTest",
        tokenSymbol: "RCT",
        maxVotingPoints: 10_000n,
        salt,
        registryKind: 0, // admin registry
        initialRecipients: [R1, R2],
        proposalExpiry: 0n,
        distributionKind: 0, // proportional
        tokenImageURI: "",
        bannerImageURI: "",
        crossChain: false, // CLASSIC — familyId stays 0, onlyClassic paths open
        issueToken: true, // transferable ERC-20 — recasting exercises the token path
      },
    ],
  });
  const deployReceipt = await pub.waitForTransactionReceipt({
    hash: deployHash,
  });
  ok(deployReceipt.status === "success", `deploy() succeeded (${deployHash})`);

  let votingModule: Address | undefined;
  let token: Address | undefined;
  let votingPowerStrategy: Address | undefined;
  let registry: Address | undefined;
  for (const log of deployReceipt.logs) {
    try {
      const ev = decodeEventLog({
        abi: deployerAbi,
        data: log.data,
        topics: log.topics,
      });
      if (ev.eventName === "SystemDeployed") {
        votingModule = ev.args.instance.votingModule;
        token = ev.args.instance.token;
        votingPowerStrategy = ev.args.instance.votingPowerStrategy;
        registry = ev.args.instance.registry;
      }
    } catch {
      /* not our event */
    }
  }
  if (!votingModule || !token || !votingPowerStrategy || !registry) {
    throw new Error("SystemDeployed not found in deploy receipt");
  }
  console.log(`  instance votingModule: ${votingModule}`);

  /* Params.initialRecipients is democratic-only — an admin registry starts
   * empty, so add recipients the way the app's admin page does: queue then
   * processQueue (both onlyOwner is fine, we deployed as owner). */
  const queueHash = await wallet.writeContract({
    address: registry,
    abi: recipientRegistryAbi,
    functionName: "queueRecipientsAddition",
    args: [[R1, R2]],
  });
  await pub.waitForTransactionReceipt({ hash: queueHash });
  const processHash = await wallet.writeContract({
    address: registry,
    abi: recipientRegistryAbi,
    functionName: "processQueue",
  });
  await pub.waitForTransactionReceipt({ hash: processHash });
  const activeRecipients = await pub.readContract({
    address: registry,
    abi: recipientRegistryAbi,
    functionName: "getRecipients",
  });
  ok(
    activeRecipients.length === 2,
    `recipients active: [${activeRecipients.join(", ")}]`,
  );

  /* 2 — mint stake (native xDAI) and let time-weighted power accrue. */
  const mintHash = await wallet.writeContract({
    address: token,
    abi: tokenAbi,
    functionName: "mint",
    args: [account.address],
    value: parseEther("500"),
  });
  await pub.waitForTransactionReceipt({ hash: mintHash });
  let power = 0n;
  for (let i = 0; i < 20 && power === 0n; i++) {
    await mine(500);
    power = await pub.readContract({
      address: votingPowerStrategy,
      abi: votingPowerAbi,
      functionName: "getCurrentVotingPower",
      args: [account.address],
    });
  }
  ok(power > 0n, `voting power accrued: ${power}`);

  /* 3 — first vote 70/30 via the direct path (unchanged in the UI). */
  const firstPoints = [7000n, 3000n];
  const voteHash = await wallet.writeContract({
    address: votingModule,
    abi: votingModuleAbi,
    functionName: "voteWithData",
    args: [firstPoints, "0x"],
  });
  const voteReceipt = await pub.waitForTransactionReceipt({ hash: voteHash });
  ok(voteReceipt.status === "success", "voteWithData(70/30) succeeded");
  const before = await pub.readContract({
    address: votingModule,
    abi: votingModuleAbi,
    functionName: "getCurrentVotingDistribution",
  });
  console.log(`  distribution BEFORE recast: [${before.join(", ")}]`);
  ok(
    ratioIs(before[0], before[1], 7n, 3n),
    "before ratio is 70/30 (d0*3 == d1*7, flooring slack)",
  );
  const hasVoted = await pub.readContract({
    address: votingModule,
    abi: votingModuleAbi,
    functionName: "hasVotedInCurrentCycle",
    args: [account.address],
  });
  ok(hasVoted, "hasVotedInCurrentCycle == true");

  /* Direct re-vote is gated — this is WHY the UI needs the signature path. */
  try {
    await pub.simulateContract({
      account: account.address,
      address: votingModule,
      abi: votingModuleAbi,
      functionName: "voteWithData",
      args: [[1000n, 9000n], "0x"],
    });
    ok(false, "direct re-vote unexpectedly allowed");
  } catch (e) {
    ok(
      revertName(e) === "AlreadyVotedInCurrentCycle",
      `direct re-vote reverts AlreadyVotedInCurrentCycle (got: ${revertName(e)})`,
    );
  }

  /* 4+5 — RECAST 10/90 via the frontend signing code path.
   * This block mirrors useVote().recast in src/hooks/use-voting.ts
   * step-for-step: Date.now() nonce bumped past isNonceUsed, then EIP-712
   * signTypedData over classicVoteDomain/CLASSIC_VOTE_TYPES/classicPointsHash
   * (the wallet-side equivalent of wagmi's signTypedDataAsync). */
  const newPoints = [1000n, 9000n];
  let nonce = BigInt(Date.now());
  while (
    await pub.readContract({
      address: votingModule,
      abi: votingModuleAbi,
      functionName: "isNonceUsed",
      args: [account.address, nonce],
    })
  ) {
    nonce += 1n;
  }
  const signature = await account.signTypedData({
    domain: classicVoteDomain(gnosis.id, votingModule),
    types: CLASSIC_VOTE_TYPES,
    primaryType: "Vote",
    message: {
      voter: account.address,
      pointsHash: classicPointsHash(newPoints),
      nonce,
    },
  });

  // Parity proof BEFORE submitting: the contract's own assembly-built digest
  // must accept the frontend-built signature.
  const valid = await pub.readContract({
    address: votingModule,
    abi: votingModuleAbi,
    functionName: "validateSignature",
    args: [account.address, newPoints, nonce, signature],
  });
  ok(valid, "validateSignature() accepts the frontend-built signature");

  const recastHash = await wallet.writeContract({
    address: votingModule,
    abi: votingModuleAbi,
    functionName: "castVoteWithSignature",
    args: [account.address, newPoints, nonce, signature],
  });
  const recastReceipt = await pub.waitForTransactionReceipt({
    hash: recastHash,
  });
  ok(
    recastReceipt.status === "success",
    `castVoteWithSignature(10/90, nonce=${nonce}) succeeded (${recastHash})`,
  );

  const after = await pub.readContract({
    address: votingModule,
    abi: votingModuleAbi,
    functionName: "getCurrentVotingDistribution",
  });
  console.log(`  distribution AFTER recast:  [${after.join(", ")}]`);
  // The voter is the ONLY voter, so a clean 10/90 ratio proves the 70/30
  // ballot was fully reverted — any residue would skew the ratio.
  ok(
    ratioIs(after[0], after[1], 1n, 9n),
    "after ratio is 10/90 (d0*9 == d1) — old ballot fully reverted",
  );
  ok(after[0] < before[0], "recipient 1 allocation dropped (70% -> 10%)");
  ok(after[1] > before[1], "recipient 2 allocation rose (30% -> 90%)");
  // Single-count proof: the cycle's total tracked power equals ONE ballot's
  // worth (the recast subtracted the previous power before re-adding).
  const cycleModule = await pub.readContract({
    address: votingModule,
    abi: votingModuleAbi,
    functionName: "cycleModule",
  });
  const cycle = await pub.readContract({
    address: cycleModule,
    abi: cycleModuleAbi,
    functionName: "getCurrentCycle",
  });
  const totalCyclePower = await pub.readContract({
    address: votingModule,
    abi: votingModuleAbi,
    functionName: "totalCycleVotingPower",
    args: [cycle],
  });
  const afterSum = after[0] + after[1];
  console.log(
    `  totalCycleVotingPower: ${totalCyclePower} vs sum(after): ${afterSum}`,
  );
  ok(
    totalCyclePower - afterSum >= 0n && totalCyclePower - afterSum <= 10n,
    "cycle power counted ONCE (sum(after) == totalCycleVotingPower, flooring slack)",
  );
  const stillVoted = await pub.readContract({
    address: votingModule,
    abi: votingModuleAbi,
    functionName: "hasVotedInCurrentCycle",
    args: [account.address],
  });
  ok(stillVoted, "hasVotedInCurrentCycle still true after recast");

  /* 6 — replaying a used nonce must revert NonceAlreadyUsed. */
  const replayPoints = [5000n, 5000n];
  const replaySig = await account.signTypedData({
    domain: classicVoteDomain(gnosis.id, votingModule),
    types: CLASSIC_VOTE_TYPES,
    primaryType: "Vote",
    message: {
      voter: account.address,
      pointsHash: classicPointsHash(replayPoints),
      nonce, // reused on purpose
    },
  });
  try {
    await pub.simulateContract({
      account: account.address,
      address: votingModule,
      abi: votingModuleAbi,
      functionName: "castVoteWithSignature",
      args: [account.address, replayPoints, nonce, replaySig],
    });
    ok(false, "nonce reuse unexpectedly allowed");
  } catch (e) {
    ok(
      revertName(e) === "NonceAlreadyUsed",
      `reused nonce reverts NonceAlreadyUsed (got: ${revertName(e)})`,
    );
  }

  /* 7 — feature-detect + the OLD live v1 default instance. */
  const typehash = await pub.readContract({
    address: votingModule,
    abi: votingModuleAbi,
    functionName: "VOTE_TYPEHASH",
  });
  const expectedTypehash = keccak256(
    encodePacked(
      ["string"],
      ["Vote(address voter,bytes32 pointsHash,uint256 nonce)"],
    ),
  );
  ok(
    typehash === expectedTypehash,
    `v2 VOTE_TYPEHASH matches pinned type string (${typehash})`,
  );

  // Empirical finding: the old live v1 module EXPOSES the same
  // VOTE_TYPEHASH + castVoteWithSignature (the feature-detect probe enables
  // recast there), so prove its recast also REPLACES the ballot. All checks
  // are DELTA-based against the pre-test distribution, since the live
  // instance forks in with other voters' state.
  console.log("\nOLD live v1 default instance:");
  let v1Typehash: Hex | null = null;
  try {
    v1Typehash = await pub.readContract({
      address: V1_VOTING_MODULE,
      abi: votingModuleAbi,
      functionName: "VOTE_TYPEHASH",
    });
  } catch {
    /* would mean the UI probe keeps recast disabled there — also fine */
  }
  if (v1Typehash === null) {
    console.log(
      "  (VOTE_TYPEHASH reverted — UI probe keeps recast disabled; skipping)",
    );
  } else {
    ok(
      v1Typehash === expectedTypehash,
      "v1 VOTE_TYPEHASH present and identical — UI probe ENABLES recast",
    );
    const n = Number(
      await pub.readContract({
        address: V1_VOTING_MODULE,
        abi: votingModuleAbi,
        functionName: "getExpectedPointsLength",
      }),
    );
    if (n < 2) throw new Error("live instance has <2 recipients");
    const at = (d: readonly bigint[], i: number): bigint => d[i] ?? 0n;
    const zeros = (): bigint[] => Array.from({ length: n }, () => 0n);
    const d0 = await pub.readContract({
      address: V1_VOTING_MODULE,
      abi: votingModuleAbi,
      functionName: "getCurrentVotingDistribution",
    });
    const mintV1 = await wallet.writeContract({
      address: V1_TOKEN,
      abi: tokenAbi,
      functionName: "mint",
      args: [account.address],
      value: parseEther("100"),
    });
    await pub.waitForTransactionReceipt({ hash: mintV1 });
    let v1Power = 0n;
    for (let i = 0; i < 30 && v1Power === 0n; i++) {
      await mine(1000);
      v1Power = await pub.readContract({
        address: V1_POWER,
        abi: votingPowerAbi,
        functionName: "getCurrentVotingPower",
        args: [account.address],
      });
    }
    ok(v1Power > 0n, `v1 voting power accrued: ${v1Power}`);
    const p1 = zeros();
    p1[0] = 7000n;
    p1[1] = 3000n;
    const v1Vote = await wallet.writeContract({
      address: V1_VOTING_MODULE,
      abi: votingModuleAbi,
      functionName: "voteWithData",
      args: [p1, "0x"],
    });
    await pub.waitForTransactionReceipt({ hash: v1Vote });
    const d1 = await pub.readContract({
      address: V1_VOTING_MODULE,
      abi: votingModuleAbi,
      functionName: "getCurrentVotingDistribution",
    });
    console.log(`  v1 delta after voteWithData(70/30): [${d1.join(", ")}]`);
    const p2 = zeros();
    p2[0] = 1000n;
    p2[1] = 9000n;
    let v1Nonce = BigInt(Date.now());
    while (
      await pub.readContract({
        address: V1_VOTING_MODULE,
        abi: votingModuleAbi,
        functionName: "isNonceUsed",
        args: [account.address, v1Nonce],
      })
    ) {
      v1Nonce += 1n;
    }
    // Same frontend signing helpers, pointed at the v1 module's domain.
    const v1Sig = await account.signTypedData({
      domain: classicVoteDomain(gnosis.id, V1_VOTING_MODULE),
      types: CLASSIC_VOTE_TYPES,
      primaryType: "Vote",
      message: {
        voter: account.address,
        pointsHash: classicPointsHash(p2),
        nonce: v1Nonce,
      },
    });
    const v1Valid = await pub.readContract({
      address: V1_VOTING_MODULE,
      abi: votingModuleAbi,
      functionName: "validateSignature",
      args: [account.address, p2, v1Nonce, v1Sig],
    });
    ok(v1Valid, "v1 validateSignature() accepts the frontend-built signature");
    const v1Recast = await wallet.writeContract({
      address: V1_VOTING_MODULE,
      abi: votingModuleAbi,
      functionName: "castVoteWithSignature",
      args: [account.address, p2, v1Nonce, v1Sig],
    });
    const v1RecastReceipt = await pub.waitForTransactionReceipt({
      hash: v1Recast,
    });
    ok(
      v1RecastReceipt.status === "success",
      "v1 castVoteWithSignature(10/90) succeeded on a re-vote",
    );
    const d2 = await pub.readContract({
      address: V1_VOTING_MODULE,
      abi: votingModuleAbi,
      functionName: "getCurrentVotingDistribution",
    });
    console.log(`  v1 distribution after recast:       [${d2.join(", ")}]`);
    ok(
      ratioIs(at(d2, 0) - at(d0, 0), at(d2, 1) - at(d0, 1), 1n, 9n),
      "v1 delta ratio is 10/90 — old ballot replaced, not double-counted",
    );
    const deltaSum = d2.reduce((s, v, i) => s + v - at(d0, i), 0n);
    ok(
      deltaSum < (v1Power * 3n) / 2n,
      `v1 delta sum ${deltaSum} ≈ one ballot's power (not 2x)`,
    );
  }

  console.log(failures === 0 ? "\nALL CHECKS PASSED" : `\n${failures} FAILED`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
