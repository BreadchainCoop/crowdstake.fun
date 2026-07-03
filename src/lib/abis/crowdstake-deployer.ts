import { parseAbi } from "viem";

/**
 * CrowdStakeDeployer — the one canonical one-tx deployer. Params carries the
 * recipient-registry kind (admin vs democratic), the democratic config, the
 * yield distribution kind (0 = proportional, 1 = equal, 2 = split half/half),
 * and two instance artwork URIs seeded onto the distribution manager at deploy.
 * The Instance tuple's `registry` is remapped to `recipientRegistry` in
 * use-deploy; `secondaryDistributionStrategy` is the equal strategy in split
 * mode (zero address otherwise).
 */
export const deployerAbi = parseAbi([
  "function deploy((address owner, uint256 cycleLength, string tokenName, string tokenSymbol, uint256 maxVotingPoints, bytes32 salt, uint8 registryKind, address[] initialRecipients, uint256 proposalExpiry, uint8 distributionKind, string tokenImageURI, string bannerImageURI) p) returns ((address cycleModule, address registry, address token, address votingPowerStrategy, address distributionManager, address distributionStrategy, address secondaryDistributionStrategy, address votingModule))",
  "event SystemDeployed(address indexed owner, address indexed deployer, bytes32 indexed salt, (address cycleModule, address registry, address token, address votingPowerStrategy, address distributionManager, address distributionStrategy, address secondaryDistributionStrategy, address votingModule) instance)",
  "error ZeroOwner()",
  "error ZeroCycleLength()",
  "error InvalidRegistryKind()",
  "error InvalidDistributionKind()",
  "error EmptyInitialRecipients()",
  "error ZeroProposalExpiry()",
]);
