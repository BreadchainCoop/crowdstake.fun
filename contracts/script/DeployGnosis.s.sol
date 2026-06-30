// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {CrowdStakeFactory} from "../src/CrowdStakeFactory.sol";

import {CycleModule} from "../src/implementation/CycleModule.sol";
import {AbstractCycleModule} from "../src/abstract/AbstractCycleModule.sol";
import {BasisPointsVotingModule} from "../src/base/BasisPointsVotingModule.sol";
import {BaseDistributionManager} from "../src/base/BaseDistributionManager.sol";
import {AbstractDistributionManager} from "../src/abstract/AbstractDistributionManager.sol";
import {EqualDistributionStrategy} from "../src/implementation/strategies/EqualDistributionStrategy.sol";
import {VotingDistributionStrategy} from "../src/implementation/strategies/VotingDistributionStrategy.sol";
import {AdminRecipientRegistry} from "../src/implementation/registries/AdminRecipientRegistry.sol";
import {RecipientRegistry} from "../src/implementation/registries/RecipientRegistry.sol";
import {VotingRecipientRegistry} from "../src/implementation/registries/VotingRecipientRegistry.sol";
import {MultiStrategyDistributionManager} from "../src/base/MultiStrategyDistributionManager.sol";
import {SexyDaiYield} from "../src/implementation/token/SexyDaiYield.sol";
import {AbstractToken} from "../src/abstract/AbstractToken.sol";
import {TimeWeightedVotingPower} from "../src/implementation/TimeWeightedVotingPower.sol";
import {IVotingPowerStrategy} from "../src/interfaces/IVotingPowerStrategy.sol";
import {IVotesCheckpoints} from "../src/interfaces/IVotesCheckpoints.sol";

/// @title DeployGnosis
/// @notice Deploys a complete, *fully-wired and working* CrowdStake system on Gnosis Chain.
/// @dev Differs from Deploy.s.sol in three deliberate ways:
///      1. The distribution base/yield token is the freshly-deployed SexyDaiYield token itself
///         (it is the yield module — yield is realised as newly-minted project tokens), NOT an
///         external env token.
///      2. Uses VotingDistributionStrategy so on-chain votes drive the yield split.
///      3. Calls token.setYieldClaimer(distributionManager) — required for claimAndDistribute()
///         to be able to mint claimed yield; Deploy.s.sol omits this, leaving the system inert.
contract DeployGnosis is Script {
    struct SystemParams {
        address owner;
        address deployer;
        uint256 cycleLength;
        string tokenName;
        string tokenSymbol;
        uint256 maxVotingPoints;
        string salt;
    }

    CrowdStakeFactory public factory;

    address public cycleModuleBeacon;
    address public votingModuleBeacon;
    address public baseDistManagerBeacon;
    address public multiDistManagerBeacon;
    address public equalStrategyBeacon;
    address public votingStrategyBeacon;
    address public adminRegistryBeacon;
    address public registryBeacon;
    address public votingRegistryBeacon;
    address public tokenBeacon;

    address public cycleModule;
    address public registry;
    address public votingPowerStrategy;
    address public votingModule;
    address public distributionStrategy;
    address public distributionManager;
    address public token;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        SystemParams memory p = SystemParams({
            owner: vm.envAddress("OWNER"),
            deployer: deployer,
            cycleLength: vm.envUint("CYCLE_LENGTH"),
            tokenName: vm.envString("TOKEN_NAME"),
            tokenSymbol: vm.envString("TOKEN_SYMBOL"),
            maxVotingPoints: vm.envUint("MAX_VOTING_POINTS"),
            salt: vm.envString("SALT")
        });

        address wxDai = vm.envAddress("WXDAI");
        address sxDai = vm.envAddress("SXDAI");

        vm.startBroadcast(deployerPrivateKey);

        _deployInfrastructure(p.owner, deployer, wxDai, sxDai);
        _deploySystemInstance(p);

        vm.stopBroadcast();

        _logDeployment();
        _writeDeploymentJson();
    }

    function _deployInfrastructure(address owner, address deployer, address wxDai, address sxDai) internal {
        factory = new CrowdStakeFactory(deployer);

        cycleModuleBeacon = address(new UpgradeableBeacon(address(new CycleModule()), owner));
        votingModuleBeacon = address(new UpgradeableBeacon(address(new BasisPointsVotingModule()), owner));
        baseDistManagerBeacon = address(new UpgradeableBeacon(address(new BaseDistributionManager()), owner));
        multiDistManagerBeacon = address(new UpgradeableBeacon(address(new MultiStrategyDistributionManager()), owner));
        equalStrategyBeacon = address(new UpgradeableBeacon(address(new EqualDistributionStrategy()), owner));
        votingStrategyBeacon = address(new UpgradeableBeacon(address(new VotingDistributionStrategy()), owner));
        adminRegistryBeacon = address(new UpgradeableBeacon(address(new AdminRecipientRegistry()), owner));
        registryBeacon = address(new UpgradeableBeacon(address(new RecipientRegistry()), owner));
        votingRegistryBeacon = address(new UpgradeableBeacon(address(new VotingRecipientRegistry()), owner));
        tokenBeacon = address(new UpgradeableBeacon(address(new SexyDaiYield(wxDai, sxDai)), owner));

        address[] memory beacons = new address[](10);
        beacons[0] = cycleModuleBeacon;
        beacons[1] = votingModuleBeacon;
        beacons[2] = baseDistManagerBeacon;
        beacons[3] = multiDistManagerBeacon;
        beacons[4] = equalStrategyBeacon;
        beacons[5] = votingStrategyBeacon;
        beacons[6] = adminRegistryBeacon;
        beacons[7] = registryBeacon;
        beacons[8] = votingRegistryBeacon;
        beacons[9] = tokenBeacon;
        factory.allowlistBeacons(beacons);

        if (owner != deployer) {
            factory.transferOwnership(owner);
        }
    }

    function _deploySystemInstance(SystemParams memory p) internal {
        bytes32 baseSalt = keccak256(abi.encodePacked(p.salt));

        // 1. CycleModule (deployer-owned temporarily so we can wire the distManager)
        cycleModule = factory.create(
            cycleModuleBeacon,
            abi.encodeWithSelector(AbstractCycleModule.initialize.selector, p.cycleLength, p.deployer),
            keccak256(abi.encodePacked(baseSalt, "cycle"))
        );

        // 2. AdminRecipientRegistry
        registry = factory.create(
            adminRegistryBeacon,
            abi.encodeWithSelector(AdminRecipientRegistry.initialize.selector, p.owner),
            keccak256(abi.encodePacked(baseSalt, "registry"))
        );

        // 3. Token (SexyDaiYield) — IS the distribution base/yield token & yield module.
        token = factory.createToken(
            tokenBeacon,
            abi.encodeWithSelector(SexyDaiYield.initialize.selector, p.tokenName, p.tokenSymbol, p.owner),
            keccak256(abi.encodePacked(baseSalt, "token"))
        );

        // 4. Voting power strategy (constructor immutables; deployed directly)
        votingPowerStrategy =
            address(new TimeWeightedVotingPower(IVotesCheckpoints(token), AbstractCycleModule(cycleModule)));

        // 5a. Distribution manager — baseToken = the token itself; placeholders for votingModule/strategy.
        distributionManager = factory.create(
            baseDistManagerBeacon,
            abi.encodeWithSelector(
                BaseDistributionManager.initialize.selector,
                cycleModule,
                registry,
                token, // baseToken == the SexyDaiYield token (the yield module)
                p.owner, // placeholder votingModule — corrected in 5d
                address(0), // strategy — corrected in 5d
                p.deployer // deployer owns it temporarily for wiring
            ),
            keccak256(abi.encodePacked(baseSalt, "dist-manager"))
        );

        // 5b. VotingDistributionStrategy — yieldToken = the token; reads votes via the manager.
        distributionStrategy = factory.create(
            votingStrategyBeacon,
            abi.encodeWithSelector(VotingDistributionStrategy.initialize.selector, token, distributionManager, p.owner),
            keccak256(abi.encodePacked(baseSalt, "strategy"))
        );

        // 5c. BasisPointsVotingModule
        IVotingPowerStrategy[] memory vpStrategies = new IVotingPowerStrategy[](1);
        vpStrategies[0] = IVotingPowerStrategy(votingPowerStrategy);
        votingModule = factory.create(
            votingModuleBeacon,
            abi.encodeWithSelector(
                BasisPointsVotingModule.initialize.selector,
                p.maxVotingPoints,
                vpStrategies,
                distributionManager,
                p.owner
            ),
            keccak256(abi.encodePacked(baseSalt, "voting"))
        );

        // 5d. Wire real references into the distManager.
        BaseDistributionManager(distributionManager).setDistributionStrategy(distributionStrategy);
        AbstractDistributionManager(distributionManager).setVotingModule(votingModule);

        // 5e. Wire the distManager into the cycle module.
        AbstractCycleModule(cycleModule).setDistributionManager(distributionManager);

        // 6. CRITICAL: authorise the distManager to claim (mint) accrued yield.
        AbstractToken(token).setYieldClaimer(distributionManager);

        // Sanity checks.
        require(
            address(BaseDistributionManager(distributionManager).distributionStrategy()) == distributionStrategy,
            "strategy not wired"
        );
        require(
            address(AbstractDistributionManager(distributionManager).votingModule()) == votingModule,
            "votingModule not wired"
        );
        require(AbstractCycleModule(cycleModule).distributionManager() == distributionManager, "distManager not wired");
        require(AbstractToken(token).yieldClaimer() == distributionManager, "yieldClaimer not set");

        // Hand temporary-owned modules to the intended owner.
        if (p.owner != p.deployer) {
            AbstractDistributionManager(distributionManager).transferOwnership(p.owner);
            AbstractCycleModule(cycleModule).transferOwnership(p.owner);
        }
    }

    function _logDeployment() internal view {
        console.log("=== CrowdStake (Gnosis) deployed ===");
        console.log("FACTORY=%s", address(factory));
        console.log("TOKEN=%s", token);
        console.log("DISTRIBUTION_MANAGER=%s", distributionManager);
        console.log("CYCLE_MODULE=%s", cycleModule);
        console.log("VOTING_MODULE=%s", votingModule);
        console.log("RECIPIENT_REGISTRY=%s", registry);
        console.log("DISTRIBUTION_STRATEGY=%s", distributionStrategy);
        console.log("VOTING_POWER_STRATEGY=%s", votingPowerStrategy);
    }

    function _writeDeploymentJson() internal {
        string memory o = "deployment";
        vm.serializeAddress(o, "factory", address(factory));
        vm.serializeAddress(o, "token", token);
        vm.serializeAddress(o, "distributionManager", distributionManager);
        vm.serializeAddress(o, "cycleModule", cycleModule);
        vm.serializeAddress(o, "votingModule", votingModule);
        vm.serializeAddress(o, "recipientRegistry", registry);
        vm.serializeAddress(o, "distributionStrategy", distributionStrategy);
        string memory json = vm.serializeAddress(o, "votingPowerStrategy", votingPowerStrategy);
        vm.writeJson(json, "./deployments/gnosis.json");
    }
}
