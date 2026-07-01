// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AbstractCycleModule} from "./abstract/AbstractCycleModule.sol";
import {BaseDistributionManager} from "./base/BaseDistributionManager.sol";
import {AbstractDistributionManager} from "./abstract/AbstractDistributionManager.sol";
import {BasisPointsVotingModule} from "./base/BasisPointsVotingModule.sol";
import {VotingDistributionStrategy} from "./implementation/strategies/VotingDistributionStrategy.sol";
import {AdminRecipientRegistry} from "./implementation/registries/AdminRecipientRegistry.sol";
import {VotingRecipientRegistry} from "./implementation/registries/VotingRecipientRegistry.sol";
import {SexyDaiYield} from "./implementation/token/SexyDaiYield.sol";
import {AbstractToken} from "./abstract/AbstractToken.sol";
import {TimeWeightedVotingPower} from "./implementation/TimeWeightedVotingPower.sol";
import {IVotingPowerStrategy} from "./interfaces/IVotingPowerStrategy.sol";
import {IVotesCheckpoints} from "./interfaces/IVotesCheckpoints.sol";

/// @notice Minimal view of CrowdStakeFactory's deployment entrypoints.
interface ICrowdStakeFactory {
    function create(address beacon, bytes calldata payload, bytes32 salt) external returns (address);
    function createToken(address beacon, bytes calldata payload, bytes32 salt) external returns (address);
}

/// @title CrowdStakeDeployerV2
/// @notice One-transaction deployer for a complete, fully-wired CrowdStake instance.
///         Identical to CrowdStakeDeployer except the caller chooses the recipient
///         registry kind: an admin-controlled registry (the original behaviour) or a
///         democratic VotingRecipientRegistry where current recipients vote to add and
///         remove members. Reuses the same factory + allowlisted beacons (the voting
///         registry beacon is already on the live factory's allowlist).
contract CrowdStakeDeployerV2 {
    ICrowdStakeFactory public immutable FACTORY;
    address public immutable CYCLE_BEACON;
    address public immutable REGISTRY_BEACON; // AdminRecipientRegistry
    address public immutable VOTING_REGISTRY_BEACON; // VotingRecipientRegistry
    address public immutable TOKEN_BEACON;
    address public immutable DIST_MANAGER_BEACON;
    address public immutable STRATEGY_BEACON;
    address public immutable VOTING_BEACON;

    /// @notice 0 = admin-controlled registry, 1 = democratic (recipient-voted).
    enum RegistryKind {
        Admin,
        Voting
    }

    struct Params {
        address owner;
        uint256 cycleLength;
        string tokenName;
        string tokenSymbol;
        uint256 maxVotingPoints;
        bytes32 salt;
        // --- V2 additions ---
        uint8 registryKind; // 0 = admin, 1 = democratic
        address[] initialRecipients; // democratic only: the founding recipient cohort
        uint256 proposalExpiry; // democratic only: seconds a proposal stays open
    }

    struct Instance {
        address cycleModule;
        address registry;
        address token;
        address votingPowerStrategy;
        address distributionManager;
        address distributionStrategy;
        address votingModule;
    }

    error ZeroOwner();
    error ZeroCycleLength();
    error InvalidRegistryKind();
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
        address strategyBeacon,
        address votingBeacon
    ) {
        FACTORY = ICrowdStakeFactory(factory);
        CYCLE_BEACON = cycleBeacon;
        REGISTRY_BEACON = registryBeacon;
        VOTING_REGISTRY_BEACON = votingRegistryBeacon;
        TOKEN_BEACON = tokenBeacon;
        DIST_MANAGER_BEACON = distManagerBeacon;
        STRATEGY_BEACON = strategyBeacon;
        VOTING_BEACON = votingBeacon;
    }

    /// @notice Deploy a full, working CrowdStake instance in one transaction.
    function deploy(Params calldata p) external returns (Instance memory inst) {
        if (p.owner == address(0)) revert ZeroOwner();
        if (p.cycleLength == 0) revert ZeroCycleLength();
        if (p.registryKind > uint8(RegistryKind.Voting)) revert InvalidRegistryKind();
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

        // 5. Distribution manager (deployer-owned; placeholders corrected below).
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

        // 6. Voting distribution strategy (votes drive the split).
        inst.distributionStrategy = FACTORY.create(
            STRATEGY_BEACON,
            abi.encodeWithSelector(
                VotingDistributionStrategy.initialize.selector, inst.token, inst.distributionManager, p.owner
            ),
            keccak256(abi.encodePacked(baseSalt, "strategy"))
        );

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

        // Wire references + authorise the manager as the token's yield claimer.
        BaseDistributionManager(inst.distributionManager).setDistributionStrategy(inst.distributionStrategy);
        AbstractDistributionManager(inst.distributionManager).setVotingModule(inst.votingModule);
        AbstractCycleModule(inst.cycleModule).setDistributionManager(inst.distributionManager);
        AbstractToken(inst.token).setYieldClaimer(inst.distributionManager);

        // Hand the temporarily-owned contracts to the final owner.
        AbstractToken(inst.token).transferOwnership(p.owner);
        AbstractDistributionManager(inst.distributionManager).transferOwnership(p.owner);
        AbstractCycleModule(inst.cycleModule).transferOwnership(p.owner);

        emit SystemDeployed(p.owner, msg.sender, p.salt, inst);
    }
}
