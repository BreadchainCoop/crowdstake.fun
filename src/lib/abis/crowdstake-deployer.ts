import { parseAbi } from "viem";

/**
 * CrowdStakeDeployer — the one canonical one-tx deployer. Params carries the
 * recipient-registry kind (admin vs democratic), the democratic config, the
 * yield distribution kind (0 = proportional, 1 = equal, 2 = split half/half),
 * two instance artwork URIs seeded onto the distribution manager at deploy,
 * and the `crossChain` flag: when true the deployer derives a creator-scoped
 * familyId (familyIdOf) so sibling instances on other chains can share one
 * signed ballot; familyInstances(familyId) resolves a chain's sibling in one
 * eth_call. The Instance tuple's `registry` is remapped to `recipientRegistry`
 * in use-deploy; `secondaryDistributionStrategy` is the equal strategy in
 * split mode (zero address otherwise).
 *
 * `issueToken` is APPENDED to Params (struct-append keeps old callers'
 * calldata meaningful): false — the zero value, and the app's default — is
 * POOL MODE (a StakePool at the Instance tuple's `token` slot, no ERC-20
 * issued); true deploys the classic transferable token. It is NOT part of
 * familyIdOf/votingFamilyIdOf — family-wide mode consistency is enforced by
 * the deploy wizard sending one shared config to every chain.
 */
export const deployerAbi = parseAbi([
  "function deploy((address owner, uint256 cycleLength, string tokenName, string tokenSymbol, uint256 maxVotingPoints, bytes32 salt, uint8 registryKind, address[] initialRecipients, uint256 proposalExpiry, uint8 distributionKind, string tokenImageURI, string bannerImageURI, bool crossChain, bool issueToken) p) returns ((address cycleModule, address registry, address token, address votingPowerStrategy, address distributionManager, address distributionStrategy, address secondaryDistributionStrategy, address votingModule))",
  "function familyIdOf(address creator, bytes32 salt, string tokenName, string tokenSymbol, uint256 maxVotingPoints, uint8 registryKind, uint8 distributionKind) pure returns (bytes32)",
  "function votingFamilyIdOf(address creator, bytes32 salt, string tokenName, string tokenSymbol, uint256 maxVotingPoints, uint8 distributionKind, address[] initialRecipients, uint256 proposalExpiry) pure returns (bytes32)",
  "function familyInstances(bytes32 familyId) view returns ((address cycleModule, address registry, address token, address votingPowerStrategy, address distributionManager, address distributionStrategy, address secondaryDistributionStrategy, address votingModule))",
  // Capability flag added alongside the appended `issueToken` param (sibling
  // contracts branch). Deployers that predate pool mode DON'T expose this — the
  // read REVERTS, which is exactly how useDeployerPoolSupport detects that a
  // 14-field deploy() would revert there and forces issueToken=true.
  "function supportsPoolMode() view returns (bool)",
  "event SystemDeployed(address indexed owner, address indexed deployer, bytes32 indexed salt, (address cycleModule, address registry, address token, address votingPowerStrategy, address distributionManager, address distributionStrategy, address secondaryDistributionStrategy, address votingModule) instance)",
  "event FamilyDeployed(bytes32 indexed familyId, address indexed creator, address indexed owner)",
  "error ZeroOwner()",
  "error ZeroCycleLength()",
  "error InvalidRegistryKind()",
  "error InvalidDistributionKind()",
  "error EmptyInitialRecipients()",
  "error ZeroProposalExpiry()",
  "error FamilyAlreadyDeployed()",
]);
