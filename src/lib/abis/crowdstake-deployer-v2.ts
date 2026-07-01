import { parseAbi } from "viem";

/**
 * CrowdStakeDeployerV2 — one-tx deployer that adds a registry-kind choice
 * (admin vs democratic/recipient-voted) on top of V1. SystemDeployed is
 * unchanged from V1; only deploy()'s Params tuple gains three fields.
 */
export const deployerV2Abi = parseAbi([
  "function deploy((address owner, uint256 cycleLength, string tokenName, string tokenSymbol, uint256 maxVotingPoints, bytes32 salt, uint8 registryKind, address[] initialRecipients, uint256 proposalExpiry) p) returns ((address cycleModule, address registry, address token, address votingPowerStrategy, address distributionManager, address distributionStrategy, address votingModule))",
  "event SystemDeployed(address indexed owner, address indexed deployer, bytes32 indexed salt, (address cycleModule, address registry, address token, address votingPowerStrategy, address distributionManager, address distributionStrategy, address votingModule) instance)",
  "error ZeroOwner()",
  "error ZeroCycleLength()",
  "error InvalidRegistryKind()",
  "error EmptyInitialRecipients()",
  "error ZeroProposalExpiry()",
]);
