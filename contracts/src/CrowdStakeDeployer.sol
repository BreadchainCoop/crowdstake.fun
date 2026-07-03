// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AbstractCycleModule} from "./abstract/AbstractCycleModule.sol";
import {BaseDistributionManager} from "./base/BaseDistributionManager.sol";
import {MultiStrategyDistributionManager} from "./base/MultiStrategyDistributionManager.sol";
import {AbstractDistributionManager} from "./abstract/AbstractDistributionManager.sol";
import {BasisPointsVotingModule} from "./base/BasisPointsVotingModule.sol";
import {VotingDistributionStrategy} from "./implementation/strategies/VotingDistributionStrategy.sol";
import {EqualDistributionStrategy} from "./implementation/strategies/EqualDistributionStrategy.sol";
import {AdminRecipientRegistry} from "./implementation/registries/AdminRecipientRegistry.sol";
import {VotingRecipientRegistry} from "./implementation/registries/VotingRecipientRegistry.sol";
import {SexyDaiYield} from "./implementation/token/SexyDaiYield.sol";
import {AbstractToken} from "./abstract/AbstractToken.sol";
import {TimeWeightedVotingPower} from "./implementation/TimeWeightedVotingPower.sol";
import {IVotingPowerStrategy} from "./interfaces/IVotingPowerStrategy.sol";
import {IVotesCheckpoints} from "./interfaces/IVotesCheckpoints.sol";
import {IDistributionStrategy} from "./interfaces/IDistributionStrategy.sol";

/// @notice Minimal view of CrowdStakeFactory's deployment entrypoints.
interface ICrowdStakeFactory {
    function create(address beacon, bytes calldata payload, bytes32 salt) external returns (address);
    function createToken(address beacon, bytes calldata payload, bytes32 salt) external returns (address);
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
    ICrowdStakeFactory public immutable FACTORY;
    address public immutable CYCLE_BEACON;
    address public immutable REGISTRY_BEACON; // AdminRecipientRegistry
    address public immutable VOTING_REGISTRY_BEACON; // VotingRecipientRegistry
    address public immutable TOKEN_BEACON;
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

    /// @notice Emitted once a full instance is deployed and handed to its owner.
    event SystemDeployed(address indexed owner, address indexed deployer, bytes32 indexed salt, Instance instance);

    constructor(
        address factory,
        address cycleBeacon,
        address registryBeacon,
        address votingRegistryBeacon,
        address tokenBeacon,
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
        DIST_MANAGER_BEACON = distManagerBeacon;
        MULTI_DIST_MANAGER_BEACON = multiDistManagerBeacon;
        STRATEGY_BEACON = strategyBeacon;
        EQUAL_STRATEGY_BEACON = equalStrategyBeacon;
        VOTING_BEACON = votingBeacon;
    }

    /// @notice Deploy a full, working CrowdStake instance in one transaction.
    function deploy(Params calldata p) external returns (Instance memory inst) {
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

        bytes32 baseSalt = keccak256(abi.encodePacked(p.salt, msg.sender));
        address self = address(this);

        // 1. Cycle module (deployer-owned for wiring).
        inst.cycleModule = FACTORY.create(
            CYCLE_BEACON,
            abi.encodeWithSelector(AbstractCycleModule.initialize.selector, p.cycleLength, self),
            keccak256(abi.encodePacked(baseSalt, "cycle"))
        );

        // 2. Recipient registry — admin-controlled or democratic.
        if (p.registryKind == uint8(RegistryKind.Voting)) {
            inst.registry = FACTORY.create(
                VOTING_REGISTRY_BEACON,
                abi.encodeWithSelector(
                    VotingRecipientRegistry.initialize.selector, p.owner, p.initialRecipients, p.proposalExpiry
                ),
                keccak256(abi.encodePacked(baseSalt, "registry"))
            );
        } else {
            inst.registry = FACTORY.create(
                REGISTRY_BEACON,
                abi.encodeWithSelector(AdminRecipientRegistry.initialize.selector, p.owner),
                keccak256(abi.encodePacked(baseSalt, "registry"))
            );
        }

        // 3. Token (deployer-owned so it can set the yield claimer).
        inst.token = FACTORY.createToken(
            TOKEN_BEACON,
            abi.encodeWithSelector(SexyDaiYield.initialize.selector, p.tokenName, p.tokenSymbol, self),
            keccak256(abi.encodePacked(baseSalt, "token"))
        );

        // 4. Time-weighted voting power (immutable; deployed directly).
        inst.votingPowerStrategy =
            address(new TimeWeightedVotingPower(IVotesCheckpoints(inst.token), AbstractCycleModule(inst.cycleModule)));

        // 5-6. Distribution manager + strategies (kind-dependent; deployer-owned, wired below).
        if (p.distributionKind == uint8(DistributionKind.Proportional)) {
            _deployProportional(inst, baseSalt, self, p.owner);
        } else {
            _deployMulti(inst, baseSalt, self, p.owner, p.distributionKind == uint8(DistributionKind.Split));
        }

        // 7. Voting module.
        IVotingPowerStrategy[] memory vps = new IVotingPowerStrategy[](1);
        vps[0] = IVotingPowerStrategy(inst.votingPowerStrategy);
        inst.votingModule = FACTORY.create(
            VOTING_BEACON,
            abi.encodeWithSelector(
                BasisPointsVotingModule.initialize.selector, p.maxVotingPoints, vps, inst.distributionManager, p.owner
            ),
            keccak256(abi.encodePacked(baseSalt, "voting"))
        );

        // Wire shared references + authorise the manager as the token's yield claimer.
        AbstractDistributionManager(inst.distributionManager).setVotingModule(inst.votingModule);
        AbstractCycleModule(inst.cycleModule).setDistributionManager(inst.distributionManager);
        AbstractToken(inst.token).setYieldClaimer(inst.distributionManager);

        // Seed instance artwork on the distribution manager while still owner-of-record.
        if (bytes(p.tokenImageURI).length != 0 || bytes(p.bannerImageURI).length != 0) {
            AbstractDistributionManager(inst.distributionManager).setInstanceMetadata(p.tokenImageURI, p.bannerImageURI);
        }

        // Hand the temporarily-owned contracts to the final owner.
        AbstractToken(inst.token).transferOwnership(p.owner);
        AbstractDistributionManager(inst.distributionManager).transferOwnership(p.owner);
        AbstractCycleModule(inst.cycleModule).transferOwnership(p.owner);

        emit SystemDeployed(p.owner, msg.sender, p.salt, inst);
    }

    /// @dev Proportional: BaseDistributionManager (single strategy) + VotingDistributionStrategy.
    ///      The manager is created with a placeholder strategy, then wired via
    ///      setDistributionStrategy once the strategy (which references the manager) exists.
    function _deployProportional(Instance memory inst, bytes32 baseSalt, address self, address owner) private {
        inst.distributionManager = FACTORY.create(
            DIST_MANAGER_BEACON,
            abi.encodeWithSelector(
                BaseDistributionManager.initialize.selector,
                inst.cycleModule,
                inst.registry,
                inst.token,
                self, // placeholder votingModule
                address(0), // placeholder strategy
                self // deployer owns it temporarily
            ),
            keccak256(abi.encodePacked(baseSalt, "dist-manager"))
        );

        inst.distributionStrategy = FACTORY.create(
            STRATEGY_BEACON,
            abi.encodeWithSelector(
                VotingDistributionStrategy.initialize.selector, inst.token, inst.distributionManager, owner
            ),
            keccak256(abi.encodePacked(baseSalt, "strategy"))
        );

        BaseDistributionManager(inst.distributionManager).setDistributionStrategy(inst.distributionStrategy);
    }

    /// @dev Equal / Split: MultiStrategyDistributionManager (permits zero-voter cycles). Created
    ///      with an empty strategy set, then wired via setStrategies once the strategies (which
    ///      reference the manager) exist. `split` adds a VotingDistributionStrategy so half the
    ///      yield is distributed by votes and half equally; otherwise it is purely equal.
    function _deployMulti(Instance memory inst, bytes32 baseSalt, address self, address owner, bool split) private {
        IDistributionStrategy[] memory none = new IDistributionStrategy[](0);
        inst.distributionManager = FACTORY.create(
            MULTI_DIST_MANAGER_BEACON,
            abi.encodeWithSelector(
                MultiStrategyDistributionManager.initialize.selector,
                inst.cycleModule,
                inst.registry,
                inst.token,
                self, // placeholder votingModule
                none, // empty; strategies wired below via setStrategies
                self // deployer owns it temporarily
            ),
            keccak256(abi.encodePacked(baseSalt, "dist-manager"))
        );

        address equalStrat = FACTORY.create(
            EQUAL_STRATEGY_BEACON,
            abi.encodeWithSelector(
                EqualDistributionStrategy.initialize.selector, inst.token, inst.distributionManager, owner
            ),
            keccak256(abi.encodePacked(baseSalt, "equal-strategy"))
        );

        IDistributionStrategy[] memory strategies;
        if (split) {
            // Primary = voting (proportional half), secondary = equal half.
            inst.distributionStrategy = FACTORY.create(
                STRATEGY_BEACON,
                abi.encodeWithSelector(
                    VotingDistributionStrategy.initialize.selector, inst.token, inst.distributionManager, owner
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
