export const distributionManagerAbi = [
  { type: "constructor", inputs: [], stateMutability: "nonpayable" },
  {
    type: "function",
    name: "baseToken",
    inputs: [],
    outputs: [{ name: "", type: "address", internalType: "contract IERC20" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "claimAndDistribute",
    inputs: [],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "cycleManager",
    inputs: [],
    outputs: [
      { name: "", type: "address", internalType: "contract ICycleModule" },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "distributionStrategy",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "address",
        internalType: "contract IDistributionStrategy",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "getTotalCurrentVotingPower",
    inputs: [],
    outputs: [{ name: "totalPower", type: "uint256", internalType: "uint256" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "initialize",
    inputs: [
      { name: "_cycleManager", type: "address", internalType: "address" },
      { name: "_recipientRegistry", type: "address", internalType: "address" },
      { name: "_baseToken", type: "address", internalType: "address" },
      { name: "_votingModule", type: "address", internalType: "address" },
      { name: "_strategy", type: "address", internalType: "address" },
      { name: "_owner", type: "address", internalType: "address" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "isDistributionReady",
    inputs: [],
    outputs: [{ name: "ready", type: "bool", internalType: "bool" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "owner",
    inputs: [],
    outputs: [{ name: "", type: "address", internalType: "address" }],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "recipientRegistry",
    inputs: [],
    outputs: [
      {
        name: "",
        type: "address",
        internalType: "contract IRecipientRegistry",
      },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "renounceOwnership",
    inputs: [],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "setDistributionStrategy",
    inputs: [{ name: "_strategy", type: "address", internalType: "address" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "setVotingModule",
    inputs: [
      { name: "_votingModule", type: "address", internalType: "address" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "transferOwnership",
    inputs: [{ name: "newOwner", type: "address", internalType: "address" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "votingModule",
    inputs: [],
    outputs: [
      { name: "", type: "address", internalType: "contract IVotingModule" },
    ],
    stateMutability: "view",
  },
  {
    type: "function",
    name: "yieldModule",
    inputs: [],
    outputs: [
      { name: "", type: "address", internalType: "contract IYieldModule" },
    ],
    stateMutability: "view",
  },
  {
    type: "event",
    name: "Initialized",
    inputs: [
      {
        name: "version",
        type: "uint64",
        indexed: false,
        internalType: "uint64",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "OwnershipTransferred",
    inputs: [
      {
        name: "previousOwner",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "newOwner",
        type: "address",
        indexed: true,
        internalType: "address",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "StrategySet",
    inputs: [
      {
        name: "strategy",
        type: "address",
        indexed: true,
        internalType: "address",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "VotingModuleSet",
    inputs: [
      {
        name: "votingModule",
        type: "address",
        indexed: true,
        internalType: "address",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "YieldClaimed",
    inputs: [
      {
        name: "amount",
        type: "uint256",
        indexed: false,
        internalType: "uint256",
      },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "YieldDistributed",
    inputs: [
      {
        name: "strategy",
        type: "address",
        indexed: true,
        internalType: "address",
      },
      {
        name: "amount",
        type: "uint256",
        indexed: false,
        internalType: "uint256",
      },
    ],
    anonymous: false,
  },
  { type: "error", name: "DistributionNotReady", inputs: [] },
  { type: "error", name: "InvalidAmount", inputs: [] },
  { type: "error", name: "InvalidInitialization", inputs: [] },
  { type: "error", name: "NoYieldAvailable", inputs: [] },
  { type: "error", name: "NotInitializing", inputs: [] },
  {
    type: "error",
    name: "OwnableInvalidOwner",
    inputs: [{ name: "owner", type: "address", internalType: "address" }],
  },
  {
    type: "error",
    name: "OwnableUnauthorizedAccount",
    inputs: [{ name: "account", type: "address", internalType: "address" }],
  },
  { type: "error", name: "ReentrancyGuardReentrantCall", inputs: [] },
  {
    type: "error",
    name: "SafeERC20FailedOperation",
    inputs: [{ name: "token", type: "address", internalType: "address" }],
  },
  { type: "error", name: "StrategyNotSet", inputs: [] },
  { type: "error", name: "ZeroAddress", inputs: [] },
] as const;
