// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AbstractCycleModule} from "./abstract/AbstractCycleModule.sol";
import {BaseDistributionManager} from "./base/BaseDistributionManager.sol";
import {MultiStrategyDistributionManager} from "./base/MultiStrategyDistributionManager.sol";
import {AbstractDistributionManager} from "./abstract/AbstractDistributionManager.sol";
import {VotingDistributionStrategy} from "./implementation/strategies/VotingDistributionStrategy.sol";
import {EqualDistributionStrategy} from "./implementation/strategies/EqualDistributionStrategy.sol";
import {AdminRecipientRegistry} from "./implementation/registries/AdminRecipientRegistry.sol";
import {VotingRecipientRegistry} from "./implementation/registries/VotingRecipientRegistry.sol";
import {SexyDaiYield} from "./implementation/token/SexyDaiYield.sol";
import {TimeWeightedVotingPower} from "./implementation/TimeWeightedVotingPower.sol";
import {IVotingPowerStrategy} from "./interfaces/IVotingPowerStrategy.sol";
import {IVotesCheckpoints} from "./interfaces/IVotesCheckpoints.sol";
import {IDistributionStrategy} from "./interfaces/IDistributionStrategy.sol";
import {IStakePool} from "./interfaces/IStakePool.sol";

/// @notice Minimal view of CrowdStakeFactory's deployment entrypoints.
interface ICrowdStakeFactory {
    function create(address beacon, bytes calldata payload, bytes32 salt) external returns (address);
    function createToken(address beacon, bytes calldata payload, bytes32 salt) external returns (address);
}

/// @notice The subset shared by the token (AbstractToken) and the pool (AbstractStakePool) that
///         the deployer wires identically, so mode branching stays confined to construction.
interface IYieldSurface {
    function setYieldClaimer(address yieldClaimer) external;
    function transferOwnership(address newOwner) external;
}

/// @title CrowdStakeDeployer
/// @notice The one canonical, one-transaction deployer for a complete, fully-wired
///         CrowdStake instance. The caller chooses:
///           - the recipient registry kind — an admin-controlled registry or a democratic
///             VotingRecipientRegistry where current recipients vote to add/remove members;
///           - the yield distribution strategy — proportional to votes, split equally among
///             recipients, or a 50/50 split of the two (see {DistributionKind});
///         and optionally supplies instance artwork (token + banner image URIs) that is
///         written to the distribution manager (the app's canonical per-instance key) in the
///         same tx. Reuses one CrowdStakeFactory + its allowlisted beacons.
contract CrowdStakeDeployer {
    /// @notice Protocol tag mixed into every familyId — prevents cross-protocol collisions.
    bytes32 private constant FAMILY_TAG = keccak256("crowdstake.family.v2");

    ICrowdStakeFactory public immutable FACTORY;
    address public immutable CYCLE_BEACON;
    address public immutable REGISTRY_BEACON; // AdminRecipientRegistry
    address public immutable VOTING_REGISTRY_BEACON; // VotingRecipientRegistry
    address public immutable TOKEN_BEACON;
    address public immutable POOL_BEACON; // StakePool (pool mode; matches TOKEN_BEACON's yield kind)
    address public immutable DIST_MANAGER_BEACON; // BaseDistributionManager (single strategy)
    address public immutable MULTI_DIST_MANAGER_BEACON; // MultiStrategyDistributionManager
    address public immutable STRATEGY_BEACON; // VotingDistributionStrategy
    address public immutable EQUAL_STRATEGY_BEACON; // EqualDistributionStrategy
    address public immutable VOTING_BEACON;

    /// @notice 0 = admin-controlled registry, 1 = democratic (recipient-voted).
    enum RegistryKind {
        Admin,
        Voting
    }

    /// @notice How claimed yield is split among recipients each cycle.
    /// @dev Proportional uses BaseDistributionManager + VotingDistributionStrategy (votes drive
    ///      the split; a cycle with zero votes never distributes). Equal and Split use
    ///      MultiStrategyDistributionManager, which permits zero-voter cycles:
    ///        - Equal: a single EqualDistributionStrategy (every recipient gets 1/N).
    ///        - Split: [VotingDistributionStrategy, EqualDistributionStrategy] — half the yield
    ///          is distributed by votes, half equally. (The vote half still needs votes to be
    ///          present at cycle end, otherwise the proportional strategy reverts.)
    enum DistributionKind {
        Proportional,
        Equal,
        Split
    }

    struct Params {
        address owner;
        uint256 cycleLength;
        string tokenName;
        string tokenSymbol;
        uint256 maxVotingPoints;
        bytes32 salt;
        // Recipient governance
        uint8 registryKind; // 0 = admin, 1 = democratic
        address[] initialRecipients; // democratic only: the founding recipient cohort
        uint256 proposalExpiry; // democratic only: seconds a proposal stays open
        // Yield distribution
        uint8 distributionKind; // 0 = proportional, 1 = equal, 2 = split (half/half)
        // Instance artwork (off-chain URIs: ipfs/https/data). Empty = none.
        string tokenImageURI;
        string bannerImageURI;
        // Cross-chain family: true = this instance joins the familyIdOf(...) family and its
        // voting module accepts ONLY chain-agnostic castCrossChainVote ballots.
        bool crossChain;
        // Token vs pool mode. ZERO VALUE (false) = POOL MODE = default: NO token is issued,
        // deposits are ledger entries in a StakePool, and distributions pay the UNDERLYING asset.
        // true = classic token mode (a SexyDaiYield/StableYield ERC-20 is minted), byte-identical
        // to the pre-pool-mode deploy path.
        bool issueToken;
    }

    /// @notice The PRE-pool-mode Params layout (13 fields, no issueToken). Kept ONLY so pinned,
    ///         per-instance IPFS frontends that encode the OLD `deploy` selector (0xfd759538) still
    ///         work against this deployer instead of hard-reverting on the changed selector.
    /// @dev Field order MUST stay byte-identical to the historical Params. The {deploy} overload
    ///      that takes this fills issueToken = true (classic token mode) and delegates to the new
    ///      path, so a legacy call deploys exactly the classic token instance it always did.
    struct LegacyParams {
        address owner;
        uint256 cycleLength;
        string tokenName;
        string tokenSymbol;
        uint256 maxVotingPoints;
        bytes32 salt;
        uint8 registryKind;
        address[] initialRecipients;
        uint256 proposalExpiry;
        uint8 distributionKind;
        string tokenImageURI;
        string bannerImageURI;
        bool crossChain;
    }

    struct Instance {
        address cycleModule;
        address registry;
        address token;
        address votingPowerStrategy;
        address distributionManager;
        address distributionStrategy; // primary: voting strat (proportional/split) or equal strat (equal)
        address secondaryDistributionStrategy; // split only: the equal strat; else address(0)
        address votingModule;
    }

    error ZeroOwner();
    error ZeroCycleLength();
    error InvalidRegistryKind();
    error InvalidDistributionKind();
    error EmptyInitialRecipients();
    error ZeroProposalExpiry();
    error FamilyAlreadyDeployed();

    /// @notice Emitted once a full instance is deployed and handed to its owner.
    event SystemDeployed(address indexed owner, address indexed deployer, bytes32 indexed salt, Instance instance);

    /// @notice Emitted when a cross-chain family instance is deployed on this chain.
    event FamilyDeployed(bytes32 indexed familyId, address indexed creator, address indexed owner);

    /// @notice The family instance deployed on this chain, by familyId (zero addresses = none).
    /// @dev The public getter returns the full 8-address tuple, so ONE eth_call per chain
    ///      resolves a sibling completely.
    mapping(bytes32 => Instance) public familyInstances;

    constructor(
        address factory,
        address cycleBeacon,
        address registryBeacon,
        address votingRegistryBeacon,
        address tokenBeacon,
        address poolBeacon,
        address distManagerBeacon,
        address multiDistManagerBeacon,
        address strategyBeacon,
        address equalStrategyBeacon,
        address votingBeacon
    ) {
        FACTORY = ICrowdStakeFactory(factory);
        CYCLE_BEACON = cycleBeacon;
        REGISTRY_BEACON = registryBeacon;
        VOTING_REGISTRY_BEACON = votingRegistryBeacon;
        TOKEN_BEACON = tokenBeacon;
        POOL_BEACON = poolBeacon;
        DIST_MANAGER_BEACON = distManagerBeacon;
        MULTI_DIST_MANAGER_BEACON = multiDistManagerBeacon;
        STRATEGY_BEACON = strategyBeacon;
        EQUAL_STRATEGY_BEACON = equalStrategyBeacon;
        VOTING_BEACON = votingBeacon;
    }

    /// @notice On-chain capability probe: this deployer understands pool mode (the issueToken
    ///         toggle) and exposes a POOL_BEACON.
    /// @dev Appending `issueToken` to Params changed deploy()'s selector (0xfd759538 → 0x1be9a993),
    ///      so a new-ABI call against an OLD deployer reverts. The deploy wizard calls this probe to
    ///      decide whether to surface the pool toggle; old deployers lack the function and the
    ///      staticcall reverts, which the wizard reads as "no pool mode".
    function supportsPoolMode() external pure returns (bool) {
        return true;
    }

    /// @notice The deterministic identity a deploy(p) with p.crossChain would create/extend.
    /// @dev Creator-scoped (only the same wallet can extend its family), protocol-tagged, and
    ///      config-committing: a different name/symbol/maxPoints/registryKind/distributionKind
    ///      can NEVER merge into one family.
    function familyIdOf(
        address creator,
        bytes32 salt,
        string memory tokenName,
        string memory tokenSymbol,
        uint256 maxVotingPoints,
        uint8 registryKind,
        uint8 distributionKind
    ) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                FAMILY_TAG,
                creator,
                salt,
                keccak256(bytes(tokenName)),
                keccak256(bytes(tokenSymbol)),
                maxVotingPoints,
                registryKind,
                distributionKind
            )
        );
    }

    /// @notice The familyId for a Voting-kind cross-chain deploy — commits the founding cohort.
    /// @dev A democratic family MUST commit its initialRecipients and proposalExpiry: same
    ///      creator/salt with different founders on two chains would otherwise mint one family
    ///      with permanently drifted electorates and no heal path. Folds the base familyIdOf with
    ///      keccak256(abi.encodePacked(initialRecipients)) and proposalExpiry. Admin-kind stays on
    ///      the base familyIdOf (byte-identical to today).
    function votingFamilyIdOf(
        address creator,
        bytes32 salt,
        string memory tokenName,
        string memory tokenSymbol,
        uint256 maxVotingPoints,
        uint8 distributionKind,
        address[] memory initialRecipients,
        uint256 proposalExpiry
    ) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                familyIdOf(
                    creator, salt, tokenName, tokenSymbol, maxVotingPoints, uint8(RegistryKind.Voting), distributionKind
                ),
                keccak256(abi.encodePacked(initialRecipients)),
                proposalExpiry
            )
        );
    }

    /// @notice Deploy a full, working CrowdStake instance in one transaction.
    function deploy(Params calldata p) external returns (Instance memory) {
        return _deploy(p, msg.sender);
    }

    /// @dev Shared deploy body. `creator` is the ORIGINAL caller (msg.sender of the public
    ///      entrypoint) so family scoping/salting/events stay correct even when invoked through the
    ///      legacy overload — never read msg.sender here (it would be `this` on a self-call).
    function _deploy(Params memory p, address creator) internal returns (Instance memory inst) {
        if (p.owner == address(0)) revert ZeroOwner();
        if (p.cycleLength == 0) revert ZeroCycleLength();
        if (p.registryKind > uint8(RegistryKind.Voting)) revert InvalidRegistryKind();
        if (p.distributionKind > uint8(DistributionKind.Split)) revert InvalidDistributionKind();
        if (p.registryKind == uint8(RegistryKind.Voting)) {
            // Pre-validate here so a bad config reverts cleanly instead of deep in
            // the registry's initialize (which would abort the whole one-tx deploy).
            if (p.initialRecipients.length == 0) revert EmptyInitialRecipients();
            if (p.proposalExpiry == 0) revert ZeroProposalExpiry();
        }

        // NOTE: familyId derivation is intentionally NOT a function of issueToken (token vs pool
        // mode). Enforcing that every sibling in a cross-chain family shares the same mode is the
        // deploy wizard's job, not the on-chain derivation's — keeping issueToken out of the
        // family id preserves byte-identical family ids for existing token-mode families.
        bytes32 familyId;
        if (p.crossChain) {
            // Voting-kind families commit their founding cohort + expiry; admin-kind stays on the
            // base derivation (byte-identical to today).
            if (p.registryKind == uint8(RegistryKind.Voting)) {
                familyId = votingFamilyIdOf(
                    creator,
                    p.salt,
                    p.tokenName,
                    p.tokenSymbol,
                    p.maxVotingPoints,
                    p.distributionKind,
                    p.initialRecipients,
                    p.proposalExpiry
                );
            } else {
                familyId = familyIdOf(
                    creator, p.salt, p.tokenName, p.tokenSymbol, p.maxVotingPoints, p.registryKind, p.distributionKind
                );
            }
            if (familyInstances[familyId].votingModule != address(0)) revert FamilyAlreadyDeployed();
        }

        bytes32 baseSalt = keccak256(abi.encodePacked(p.salt, creator));
        address self = address(this);

        // 1. Cycle module (deployer-owned for wiring).
        inst.cycleModule = FACTORY.create(
            CYCLE_BEACON,
            abi.encodeWithSelector(AbstractCycleModule.initialize.selector, p.cycleLength, self),
            keccak256(abi.encodePacked(baseSalt, "cycle"))
        );

        // 2. Recipient registry — admin-controlled or democratic. familyId (0 when !crossChain)
        //    is threaded in so family instances accept the chain-agnostic governance signatures.
        //    encodeWithSignature: `initialize` is overloaded, so `.selector` is ambiguous.
        if (p.registryKind == uint8(RegistryKind.Voting)) {
            inst.registry = FACTORY.create(
                VOTING_REGISTRY_BEACON,
                abi.encodeWithSignature(
                    "initialize(address,address[],uint256,bytes32)",
                    p.owner,
                    p.initialRecipients,
                    p.proposalExpiry,
                    familyId
                ),
                keccak256(abi.encodePacked(baseSalt, "registry"))
            );
        } else {
            inst.registry = FACTORY.create(
                REGISTRY_BEACON,
                abi.encodeWithSignature("initialize(address,bytes32)", p.owner, familyId),
                keccak256(abi.encodePacked(baseSalt, "registry"))
            );
        }

        // 3. Yield surface (deployer-owned so it can set the yield claimer).
        //    - Token mode (issueToken == true): a SexyDaiYield/StableYield ERC-20 is minted.
        //    - Pool mode (issueToken == false, the ZERO-VALUE default): a StakePool records ledger
        //      entries and issues NO token. `inst.token` carries the POOL address here — intentional:
        //      the frontend treats inst.token as the balance/yield surface regardless of mode.
        //    Both impls share the initialize(string,string,address) shape and both implement
        //    IVotesCheckpoints, so steps 4/7 and the yield-claimer wiring are mode-agnostic.
        //
        //    The asset the DistributionManager claims and distributes:
        //      - token mode: the token itself (yieldModule == baseToken, as in the classic path).
        //      - pool mode:  the UNDERLYING asset (WXDAI/USDC). The pool is the yield source, but
        //                    baseToken = underlying so recipients receive the real asset.
        address distributedAsset;
        if (p.issueToken) {
            inst.token = FACTORY.createToken(
                TOKEN_BEACON,
                abi.encodeWithSelector(SexyDaiYield.initialize.selector, p.tokenName, p.tokenSymbol, self),
                keccak256(abi.encodePacked(baseSalt, "token"))
            );
            distributedAsset = inst.token;
        } else {
            inst.token = FACTORY.createToken(
                POOL_BEACON,
                abi.encodeWithSignature("initialize(string,string,address)", p.tokenName, p.tokenSymbol, self),
                keccak256(abi.encodePacked(baseSalt, "token"))
            );
            distributedAsset = IStakePool(inst.token).underlyingAsset();
        }

        // 4. Time-weighted voting power (immutable; deployed directly). Reads only
        //    numCheckpoints/checkpoints via IVotesCheckpoints, which both the token (ERC20Votes)
        //    and the pool implement identically — so the SAME strategy is used unchanged.
        inst.votingPowerStrategy =
            address(new TimeWeightedVotingPower(IVotesCheckpoints(inst.token), AbstractCycleModule(inst.cycleModule)));

        // 5-6. Distribution manager + strategies (kind-dependent; deployer-owned, wired below).
        //      The DM's baseToken and the strategy's yieldToken are the distributedAsset (the
        //      underlying in pool mode, the token in token mode).
        if (p.distributionKind == uint8(DistributionKind.Proportional)) {
            _deployProportional(inst, baseSalt, self, p.owner, distributedAsset);
        } else {
            _deployMulti(
                inst, baseSalt, self, p.owner, distributedAsset, p.distributionKind == uint8(DistributionKind.Split)
            );
        }

        // In pool mode the yield-bearing surface (the pool) is distinct from the distributed asset
        // (the underlying), so point the DM's yield module at the pool. Token mode leaves
        // yieldModule == baseToken (set in initialize), byte-identical to the classic path.
        if (!p.issueToken) {
            AbstractDistributionManager(inst.distributionManager).setYieldModule(inst.token);
        }

        // 7. Voting module (familyId = 0 → classic chain-bound instance).
        //    encodeWithSignature: `initialize` is overloaded, so `.selector` is ambiguous.
        IVotingPowerStrategy[] memory vps = new IVotingPowerStrategy[](1);
        vps[0] = IVotingPowerStrategy(inst.votingPowerStrategy);
        inst.votingModule = FACTORY.create(
            VOTING_BEACON,
            abi.encodeWithSignature(
                "initialize(uint256,address[],address,address,bytes32)",
                p.maxVotingPoints,
                vps,
                inst.distributionManager,
                p.owner,
                familyId
            ),
            keccak256(abi.encodePacked(baseSalt, "voting"))
        );

        // Wire shared references + authorise the manager as the yield surface's yield claimer.
        // setYieldClaimer(address) has the same signature on the token and the pool.
        AbstractDistributionManager(inst.distributionManager).setVotingModule(inst.votingModule);
        AbstractCycleModule(inst.cycleModule).setDistributionManager(inst.distributionManager);
        IYieldSurface(inst.token).setYieldClaimer(inst.distributionManager);

        // Seed instance artwork on the distribution manager while still owner-of-record.
        if (bytes(p.tokenImageURI).length != 0 || bytes(p.bannerImageURI).length != 0) {
            AbstractDistributionManager(inst.distributionManager).setInstanceMetadata(p.tokenImageURI, p.bannerImageURI);
        }

        // Hand the temporarily-owned contracts to the final owner.
        // transferOwnership(address) has the same signature on the token and the pool.
        IYieldSurface(inst.token).transferOwnership(p.owner);
        AbstractDistributionManager(inst.distributionManager).transferOwnership(p.owner);
        AbstractCycleModule(inst.cycleModule).transferOwnership(p.owner);

        // Record the family sibling only after full wiring, so a resolved instance is usable.
        if (p.crossChain) {
            familyInstances[familyId] = inst;
            emit FamilyDeployed(familyId, creator, p.owner);
        }

        emit SystemDeployed(p.owner, creator, p.salt, inst);
    }

    /// @notice Backward-compatible deploy for callers encoding the PRE-pool-mode ABI.
    /// @dev Pinned, per-instance IPFS frontends encode the old `deploy((...13 fields...))` selector
    ///      (0xfd759538). Appending issueToken changed the primary {deploy} selector to 0x1be9a993,
    ///      so without this overload those frozen frontends would hard-revert. This overload accepts
    ///      the legacy 13-field struct, sets issueToken = true (classic token mode — what those
    ///      frontends always got), and forwards to the new path. Result is byte-identical to a
    ///      pre-pool-mode deploy.
    function deploy(LegacyParams calldata legacy) external returns (Instance memory) {
        // Delegate through the internal body (NOT this.deploy) so msg.sender — the family
        // creator/salt — is the original caller, not the deployer.
        return _deploy(
            Params({
                owner: legacy.owner,
                cycleLength: legacy.cycleLength,
                tokenName: legacy.tokenName,
                tokenSymbol: legacy.tokenSymbol,
                maxVotingPoints: legacy.maxVotingPoints,
                salt: legacy.salt,
                registryKind: legacy.registryKind,
                initialRecipients: legacy.initialRecipients,
                proposalExpiry: legacy.proposalExpiry,
                distributionKind: legacy.distributionKind,
                tokenImageURI: legacy.tokenImageURI,
                bannerImageURI: legacy.bannerImageURI,
                crossChain: legacy.crossChain,
                issueToken: true // legacy callers always got a classic token instance
            }),
            msg.sender
        );
    }

    /// @dev Proportional: BaseDistributionManager (single strategy) + VotingDistributionStrategy.
    ///      The manager is created with a placeholder strategy, then wired via
    ///      setDistributionStrategy once the strategy (which references the manager) exists.
    /// @param distributedAsset The ERC-20 the manager distributes: the token in token mode, the
    ///        UNDERLYING asset in pool mode. Used as both the DM's baseToken and the strategy's
    ///        yieldToken. In pool mode the DM's yieldModule is repointed to the pool by the caller.
    function _deployProportional(
        Instance memory inst,
        bytes32 baseSalt,
        address self,
        address owner,
        address distributedAsset
    ) private {
        inst.distributionManager = FACTORY.create(
            DIST_MANAGER_BEACON,
            abi.encodeWithSelector(
                BaseDistributionManager.initialize.selector,
                inst.cycleModule,
                inst.registry,
                distributedAsset,
                self, // placeholder votingModule
                address(0), // placeholder strategy
                self // deployer owns it temporarily
            ),
            keccak256(abi.encodePacked(baseSalt, "dist-manager"))
        );

        inst.distributionStrategy = FACTORY.create(
            STRATEGY_BEACON,
            abi.encodeWithSelector(
                VotingDistributionStrategy.initialize.selector, distributedAsset, inst.distributionManager, owner
            ),
            keccak256(abi.encodePacked(baseSalt, "strategy"))
        );

        BaseDistributionManager(inst.distributionManager).setDistributionStrategy(inst.distributionStrategy);
    }

    /// @dev Equal / Split: MultiStrategyDistributionManager (permits zero-voter cycles). Created
    ///      with an empty strategy set, then wired via setStrategies once the strategies (which
    ///      reference the manager) exist. `split` adds a VotingDistributionStrategy so half the
    ///      yield is distributed by votes and half equally; otherwise it is purely equal.
    /// @param distributedAsset The ERC-20 the manager distributes: the token in token mode, the
    ///        UNDERLYING asset in pool mode. Used as the DM's baseToken and every strategy's
    ///        yieldToken. In pool mode the DM's yieldModule is repointed to the pool by the caller.
    function _deployMulti(
        Instance memory inst,
        bytes32 baseSalt,
        address self,
        address owner,
        address distributedAsset,
        bool split
    ) private {
        IDistributionStrategy[] memory none = new IDistributionStrategy[](0);
        inst.distributionManager = FACTORY.create(
            MULTI_DIST_MANAGER_BEACON,
            abi.encodeWithSelector(
                MultiStrategyDistributionManager.initialize.selector,
                inst.cycleModule,
                inst.registry,
                distributedAsset,
                self, // placeholder votingModule
                none, // empty; strategies wired below via setStrategies
                self // deployer owns it temporarily
            ),
            keccak256(abi.encodePacked(baseSalt, "dist-manager"))
        );

        address equalStrat = FACTORY.create(
            EQUAL_STRATEGY_BEACON,
            abi.encodeWithSelector(
                EqualDistributionStrategy.initialize.selector, distributedAsset, inst.distributionManager, owner
            ),
            keccak256(abi.encodePacked(baseSalt, "equal-strategy"))
        );

        IDistributionStrategy[] memory strategies;
        if (split) {
            // Primary = voting (proportional half), secondary = equal half.
            inst.distributionStrategy = FACTORY.create(
                STRATEGY_BEACON,
                abi.encodeWithSelector(
                    VotingDistributionStrategy.initialize.selector, distributedAsset, inst.distributionManager, owner
                ),
                keccak256(abi.encodePacked(baseSalt, "strategy"))
            );
            inst.secondaryDistributionStrategy = equalStrat;
            strategies = new IDistributionStrategy[](2);
            strategies[0] = IDistributionStrategy(inst.distributionStrategy);
            strategies[1] = IDistributionStrategy(equalStrat);
        } else {
            // Pure equal: the equal strategy is the primary and only strategy.
            inst.distributionStrategy = equalStrat;
            strategies = new IDistributionStrategy[](1);
            strategies[0] = IDistributionStrategy(equalStrat);
        }

        MultiStrategyDistributionManager(inst.distributionManager).setStrategies(strategies);
    }
}
