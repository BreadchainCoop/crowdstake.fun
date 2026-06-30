// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AbstractCycleModule} from "./abstract/AbstractCycleModule.sol";
import {BaseDistributionManager} from "./base/BaseDistributionManager.sol";
import {AbstractDistributionManager} from "./abstract/AbstractDistributionManager.sol";
import {BasisPointsVotingModule} from "./base/BasisPointsVotingModule.sol";
import {VotingDistributionStrategy} from "./implementation/strategies/VotingDistributionStrategy.sol";
import {AdminRecipientRegistry} from "./implementation/registries/AdminRecipientRegistry.sol";
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

/// @title CrowdStakeDeployer
/// @notice One-transaction deployer for a complete, fully-wired CrowdStake instance
///         (the voting-driven configuration). Reuses an existing factory + allowlisted
///         beacons. Mirrors DeployGnosis._deploySystemInstance: the deployer temporarily
///         owns the cycle module, token, and distribution manager so it can wire references
///         and set the yield claimer, then hands every contract to `params.owner`.
contract CrowdStakeDeployer {
    ICrowdStakeFactory public immutable FACTORY;
    address public immutable CYCLE_BEACON;
    address public immutable REGISTRY_BEACON;
    address public immutable TOKEN_BEACON;
    address public immutable DIST_MANAGER_BEACON;
    address public immutable STRATEGY_BEACON;
    address public immutable VOTING_BEACON;

    struct Params {
        address owner;
        uint256 cycleLength;
        string tokenName;
        string tokenSymbol;
        uint256 maxVotingPoints;
        bytes32 salt;
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

    /// @notice Emitted once a full instance is deployed and handed to its owner.
    event SystemDeployed(address indexed owner, address indexed deployer, bytes32 indexed salt, Instance instance);

    constructor(
        address factory,
        address cycleBeacon,
        address registryBeacon,
        address tokenBeacon,
        address distManagerBeacon,
        address strategyBeacon,
        address votingBeacon
    ) {
        FACTORY = ICrowdStakeFactory(factory);
        CYCLE_BEACON = cycleBeacon;
        REGISTRY_BEACON = registryBeacon;
        TOKEN_BEACON = tokenBeacon;
        DIST_MANAGER_BEACON = distManagerBeacon;
        STRATEGY_BEACON = strategyBeacon;
        VOTING_BEACON = votingBeacon;
    }

    /// @notice Deploy a full, working CrowdStake instance in one transaction.
    /// @param p owner / cycle length / token name+symbol / max voting points / salt
    /// @return inst the seven deployed addresses
    function deploy(Params calldata p) external returns (Instance memory inst) {
        if (p.owner == address(0)) revert ZeroOwner();
        if (p.cycleLength == 0) revert ZeroCycleLength();

        // Scope CREATE2 salts to (caller, salt) so distinct users/instances never collide
        // (the factory already scopes by msg.sender, which is this deployer for every call).
        bytes32 baseSalt = keccak256(abi.encodePacked(p.salt, msg.sender));
        address self = address(this);

        // 1. Cycle module (deployer-owned for wiring).
        inst.cycleModule = FACTORY.create(
            CYCLE_BEACON,
            abi.encodeWithSelector(AbstractCycleModule.initialize.selector, p.cycleLength, self),
            keccak256(abi.encodePacked(baseSalt, "cycle"))
        );

        // 2. Admin recipient registry (owned by the final owner).
        inst.registry = FACTORY.create(
            REGISTRY_BEACON,
            abi.encodeWithSelector(AdminRecipientRegistry.initialize.selector, p.owner),
            keccak256(abi.encodePacked(baseSalt, "registry"))
        );

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
                inst.token, // baseToken == token (the yield module)
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
