import { parseAbi } from "viem";

/**
 * CrowdStakeDeployer — the one canonical one-tx deployer. Params carries the
 * recipient-registry kind (admin vs democratic), the democratic config, and two
 * instance artwork URIs seeded onto the distribution manager at deploy.
 * SystemDeployed's Instance tuple is unchanged (registry -> recipientRegistry
 * is remapped in use-deploy).
 */
export const deployerAbi = parseAbi([
  "function deploy((address owner, uint256 cycleLength, string tokenName, string tokenSymbol, uint256 maxVotingPoints, bytes32 salt, uint8 registryKind, address[] initialRecipients, uint256 proposalExpiry, string tokenImageURI, string bannerImageURI) p) returns ((address cycleModule, address registry, address token, address votingPowerStrategy, address distributionManager, address distributionStrategy, address votingModule))",
  "event SystemDeployed(address indexed owner, address indexed deployer, bytes32 indexed salt, (address cycleModule, address registry, address token, address votingPowerStrategy, address distributionManager, address distributionStrategy, address votingModule) instance)",
  "error ZeroOwner()",
  "error ZeroCycleLength()",
  "error InvalidRegistryKind()",
  "error EmptyInitialRecipients()",
  "error ZeroProposalExpiry()",
]);
