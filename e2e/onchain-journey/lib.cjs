/* Shared harness lib: addresses, ABIs, viem clients, the Node-side signer that
 * backs the injected wallet, anvil fork cheatcodes, and on-chain reads used for
 * assertions. The signing key is read from env (TEST_PRIVATE_KEY) and never
 * leaves this Node process. */
const {
  createPublicClient,
  createWalletClient,
  http,
  parseAbi,
  hexToBigInt,
  decodeEventLog,
} = require("viem");
const { privateKeyToAccount } = require("viem/accounts");
const { gnosis } = require("viem/chains");

const RPC = process.env.TEST_RPC_URL || "http://localhost:8546";
const PK = process.env.TEST_PRIVATE_KEY || "";

// Live default-instance addresses (mirror src/lib/constants.ts).
const A = {
  token: "0x7E94a840143E3D5C78f367bBe45e6fB6e55098ec",
  distributionManager: "0xB38B15ad418202D3FdC1A139cEc51A8c13f59CB6",
  cycleModule: "0xDfBDa0C7061276C3B8a08aC38fEdeE63c0B63827",
  votingModule: "0xf921AF0C0fCd4A9dE0F6C58b34b05DBCCf0aAc42",
  recipientRegistry: "0x8e61175AbBC31A07237367e356833C83204945C2",
  votingPowerStrategy: "0x3F477A1FD83F56537BEE5cC05406fF4628e7A399",
  deployer: "0x6193210E25aAc4f645D2a7e9420Cb57B0F193033",
  WXDAI: "0xe91D153E0b41518A2Ce8Dd3D7944Fa863463a97d",
  SDAI: "0xaf204776c7245bF4147c2612BF6e5972Ee483701",
};

const tokenAbi = parseAbi([
  "function balanceOf(address) view returns (uint256)",
  "function totalSupply() view returns (uint256)",
  "function yieldAccrued() view returns (uint256)",
  "function getVotes(address) view returns (uint256)",
  "function delegates(address) view returns (address)",
]);
const votingAbi = parseAbi([
  "function getCurrentVotingDistribution() view returns (uint256[])",
  "function hasVotedInCurrentCycle(address) view returns (bool)",
  "function getVotingPowerStrategies() view returns (address[])",
]);
const cycleAbi = parseAbi([
  "function getCurrentCycle() view returns (uint256)",
  "function isCycleComplete() view returns (bool)",
  "function cycleLength() view returns (uint256)",
  "function getBlocksUntilNextCycle() view returns (uint256)",
]);
const distAbi = parseAbi([
  "function isDistributionReady() view returns (bool)",
  "function cycleManager() view returns (address)",
  "function votingModule() view returns (address)",
  "function recipientRegistry() view returns (address)",
  "function baseToken() view returns (address)",
  "function distributionStrategy() view returns (address)",
]);
const registryAbi = parseAbi([
  "function getRecipients() view returns (address[])",
  "function owner() view returns (address)",
]);
const deployerAbi = parseAbi([
  "event SystemDeployed(address indexed owner, address indexed deployer, bytes32 indexed salt, (address cycleModule, address registry, address token, address votingPowerStrategy, address distributionManager, address distributionStrategy, address votingModule) instance)",
]);
const wxdaiAbi = parseAbi([
  "function deposit() payable",
  "function transfer(address,uint256) returns (bool)",
]);

const pub = createPublicClient({ chain: gnosis, transport: http(RPC) });
const account = PK ? privateKeyToAccount(PK) : null;
const wallet = account
  ? createWalletClient({ account, chain: gnosis, transport: http(RPC) })
  : null;

const read = (address, abi, functionName, args) =>
  pub.readContract({ address, abi, functionName, args });

// On-chain reads (independent of the UI) used to assert each journey step.
const R = {
  balanceOf: (a) => read(A.token, tokenAbi, "balanceOf", [a]),
  totalSupply: () => read(A.token, tokenAbi, "totalSupply", []),
  yieldAccrued: () => read(A.token, tokenAbi, "yieldAccrued", []),
  getVotes: (a) => read(A.token, tokenAbi, "getVotes", [a]),
  hasVoted: (a) =>
    read(A.votingModule, votingAbi, "hasVotedInCurrentCycle", [a]),
  isDistributionReady: () =>
    read(A.distributionManager, distAbi, "isDistributionReady", []),
  currentCycle: () => read(A.cycleModule, cycleAbi, "getCurrentCycle", []),
  recipients: () => read(A.recipientRegistry, registryAbi, "getRecipients", []),
  // Resolve a freshly deployed instance from its distribution manager, the same
  // way the app does (src/lib/instance.ts), and read its registry owner.
  resolveInstance: async (distributionManager) => {
    const base = { address: distributionManager, abi: distAbi };
    const [cycleModule, votingModule, recipientRegistry, token, strategy] =
      await Promise.all([
        read(distributionManager, distAbi, "cycleManager", []),
        read(distributionManager, distAbi, "votingModule", []),
        read(distributionManager, distAbi, "recipientRegistry", []),
        read(distributionManager, distAbi, "baseToken", []),
        read(distributionManager, distAbi, "distributionStrategy", []),
      ]);
    void base;
    const vps = await read(
      votingModule,
      votingAbi,
      "getVotingPowerStrategies",
      [],
    );
    return {
      distributionManager,
      cycleModule,
      votingModule,
      recipientRegistry,
      token,
      distributionStrategy: strategy,
      votingPowerStrategy: vps[0],
    };
  },
  registryOwner: (registry) => read(registry, registryAbi, "owner", []),
  // The most recent instance deployed by `owner` via the deployer (decoded).
  latestDeployedInstance: async (owner) => {
    const logs = await pub.getLogs({
      address: A.deployer,
      fromBlock: "earliest",
      toBlock: "latest",
    });
    for (let i = logs.length - 1; i >= 0; i--) {
      try {
        const ev = decodeEventLog({
          abi: deployerAbi,
          data: logs[i].data,
          topics: logs[i].topics,
        });
        if (
          ev.eventName === "SystemDeployed" &&
          ev.args.owner.toLowerCase() === owner.toLowerCase()
        ) {
          return ev.args.instance;
        }
      } catch {
        /* not our event */
      }
    }
    return null;
  },
};

const hex = (n) => "0x" + BigInt(n).toString(16);
const rpc = (method, params = []) =>
  fetch(RPC, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: Date.now(), method, params }),
  })
    .then((r) => r.json())
    .then((j) => {
      if (j.error) throw new Error(method + ": " + j.error.message);
      return j.result;
    });

// Anvil fork cheatcodes (only used in the default fork mode).
const fork = {
  setBalance: (a, wei) => rpc("anvil_setBalance", [a, hex(wei)]),
  mine: (n) => rpc("anvil_mine", [hex(n)]),
  // sDAI yield is push-based: send WXDAI to the sDAI vault so yieldAccrued rises.
  forceYield: async (wei) => {
    await wallet.writeContract({
      address: A.WXDAI,
      abi: wxdaiAbi,
      functionName: "deposit",
      value: wei,
    });
    const h = await wallet.writeContract({
      address: A.WXDAI,
      abi: wxdaiAbi,
      functionName: "transfer",
      args: [A.SDAI, wei],
    });
    await pub.waitForTransactionReceipt({ hash: h });
  },
};

// The Node-side EIP-1193 handler the in-page shim proxies every call to.
// Reads forward to the fork RPC; signing happens here with the env key.
async function handle(method, params = []) {
  switch (method) {
    case "eth_requestAccounts":
    case "eth_accounts":
      return [account.address];
    case "eth_chainId":
      return "0x64";
    case "net_version":
      return "100";
    case "wallet_switchEthereumChain":
    case "wallet_addEthereumChain":
    case "wallet_revokePermissions":
      return null;
    case "wallet_requestPermissions":
      return [
        {
          parentCapability: "eth_accounts",
          caveats: [{ type: "restricted", value: [account.address] }],
        },
      ];
    case "personal_sign":
      return account.signMessage({ message: { raw: params[0] } });
    case "eth_signTypedData_v4":
      return account.signTypedData(JSON.parse(params[1]));
    case "eth_sendTransaction": {
      const t = params[0];
      return wallet.sendTransaction({
        to: t.to,
        data: t.data,
        value: t.value ? hexToBigInt(t.value) : undefined,
        gas: t.gas ? hexToBigInt(t.gas) : undefined,
      });
    }
    default:
      return pub.request({ method, params });
  }
}

module.exports = { A, R, rpc, hex, fork, handle, account, pub, wallet };
