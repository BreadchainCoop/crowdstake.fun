// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {CrowdStakeFactory} from "../src/CrowdStakeFactory.sol";

// Implementations
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
import {TimeWeightedVotingPower} from "../src/implementation/TimeWeightedVotingPower.sol";
import {IVotingPowerStrategy} from "../src/interfaces/IVotingPowerStrategy.sol";
import {IVotesCheckpoints} from "../src/interfaces/IVotesCheckpoints.sol";

/// @title Deploy
/// @notice Deploys the entire CrowdStake system via the factory pattern.
///         Step 1: Deploy factory + implementations + beacons + allowlist
///         Step 2: Deploy a full system instance via the factory
contract Deploy is Script {
    // ============ Deployed Infrastructure ============

    CrowdStakeFactory public factory;

    // Beacons
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

    // ============ Deployed System Instance ============

    address public cycleModule;
    address public registry;
    address public votingPowerStrategy;
    address public votingModule;
    address public distributionStrategy;
    address public distributionManager;
    address public token;

    /// @notice Deploy everything: factory infrastructure + a full system instance.
    ///
    /// Required env vars:
    ///   PRIVATE_KEY          - deployer private key
    ///   OWNER                - system owner address (receives admin rights)
    ///   CYCLE_LENGTH         - cycle length in blocks (e.g., 43200 for ~6h on Gnosis)
    ///   TOKEN_NAME           - ERC20 token name
    ///   TOKEN_SYMBOL         - ERC20 token symbol
    ///   YIELD_TOKEN          - address of the yield-bearing token (e.g., sDAI)
    ///   BASE_TOKEN           - address of the base token for distributions
    ///   MAX_VOTING_POINTS    - max basis points for voting (e.g., 10000)
    ///   SALT                 - deployment salt (string, used to derive CREATE2 salts)
    ///   WXDAI               - WXDAI token address (for SexyDaiYield implementation)
    ///   SXDAI               - sDAI token address (for SexyDaiYield implementation)
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.envAddress("OWNER");
        uint256 cycleLength = vm.envUint("CYCLE_LENGTH");
        string memory tokenName = vm.envString("TOKEN_NAME");
        string memory tokenSymbol = vm.envString("TOKEN_SYMBOL");
        address yieldToken = vm.envAddress("YIELD_TOKEN");
        address baseToken = vm.envAddress("BASE_TOKEN");
        uint256 maxVotingPoints = vm.envUint("MAX_VOTING_POINTS");
        string memory salt = vm.envString("SALT");
        address wxDai = vm.envAddress("WXDAI");
        address sxDai = vm.envAddress("SXDAI");

        vm.startBroadcast(deployerPrivateKey);

        _deployInfrastructure(owner, wxDai, sxDai);
        _deploySystemInstance(owner, cycleLength, tokenName, tokenSymbol, yieldToken, baseToken, maxVotingPoints, salt);

        vm.stopBroadcast();

        _logDeployment();
    }

    /// @notice Deploy only the factory infrastructure (factory + beacons).
    ///         Useful when you want to deploy instances separately or via a frontend.
    function deployInfrastructureOnly() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.envAddress("OWNER");
        address wxDai = vm.envAddress("WXDAI");
        address sxDai = vm.envAddress("SXDAI");

        vm.startBroadcast(deployerPrivateKey);
        _deployInfrastructure(owner, wxDai, sxDai);
        vm.stopBroadcast();

        console.log("\n=== Factory Infrastructure ===");
        console.log("Factory:                    ", address(factory));
        console.log("CycleModule beacon:         ", cycleModuleBeacon);
        console.log("VotingModule beacon:        ", votingModuleBeacon);
        console.log("BaseDistManager beacon:     ", baseDistManagerBeacon);
        console.log("MultiDistManager beacon:    ", multiDistManagerBeacon);
        console.log("EqualStrategy beacon:       ", equalStrategyBeacon);
        console.log("VotingStrategy beacon:      ", votingStrategyBeacon);
        console.log("AdminRegistry beacon:       ", adminRegistryBeacon);
        console.log("Registry beacon:            ", registryBeacon);
        console.log("VotingRegistry beacon:      ", votingRegistryBeacon);
        console.log("Token beacon:               ", tokenBeacon);
    }

    // ============ Internal: Infrastructure ============

    function _deployInfrastructure(address owner, address wxDai, address sxDai) internal {
        // 1. Deploy factory
        factory = new CrowdStakeFactory(owner);
        console.log("Factory deployed at:        ", address(factory));

        // 2. Deploy implementations
        address cycleImpl = address(new CycleModule());
        address votingImpl = address(new BasisPointsVotingModule());
        address baseDistImpl = address(new BaseDistributionManager());
        address multiDistImpl = address(new MultiStrategyDistributionManager());
        address equalStratImpl = address(new EqualDistributionStrategy());
        address votingStratImpl = address(new VotingDistributionStrategy());
        address adminRegImpl = address(new AdminRecipientRegistry());
        address regImpl = address(new RecipientRegistry());
        address votingRegImpl = address(new VotingRecipientRegistry());
        address tokenImpl = address(new SexyDaiYield(wxDai, sxDai));

        // 3. Create beacons (owner controls upgrades)
        cycleModuleBeacon = address(new UpgradeableBeacon(cycleImpl, owner));
        votingModuleBeacon = address(new UpgradeableBeacon(votingImpl, owner));
        baseDistManagerBeacon = address(new UpgradeableBeacon(baseDistImpl, owner));
        multiDistManagerBeacon = address(new UpgradeableBeacon(multiDistImpl, owner));
        equalStrategyBeacon = address(new UpgradeableBeacon(equalStratImpl, owner));
        votingStrategyBeacon = address(new UpgradeableBeacon(votingStratImpl, owner));
        adminRegistryBeacon = address(new UpgradeableBeacon(adminRegImpl, owner));
        registryBeacon = address(new UpgradeableBeacon(regImpl, owner));
        votingRegistryBeacon = address(new UpgradeableBeacon(votingRegImpl, owner));
        tokenBeacon = address(new UpgradeableBeacon(tokenImpl, owner));

        // 4. Allowlist all beacons
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

        console.log("All beacons deployed and allowlisted");
    }

    // ============ Internal: System Instance ============

    struct SystemParams {
        address owner;
        uint256 cycleLength;
        string tokenName;
        string tokenSymbol;
        address yieldToken;
        address baseToken;
        uint256 maxVotingPoints;
        string salt;
    }

    function _deploySystemInstance(
        address owner,
        uint256 cycleLength,
        string memory tokenName,
        string memory tokenSymbol,
        address yieldToken,
        address baseToken,
        uint256 maxVotingPoints,
        string memory salt
    ) internal {
        SystemParams memory p = SystemParams(owner, cycleLength, tokenName, tokenSymbol, yieldToken, baseToken, maxVotingPoints, salt);
        bytes32 baseSalt = keccak256(abi.encodePacked(p.salt));

        // 1. CycleModule
        cycleModule = factory.create(
            cycleModuleBeacon,
            abi.encodeWithSelector(AbstractCycleModule.initialize.selector, p.cycleLength, p.owner),
            keccak256(abi.encodePacked(baseSalt, "cycle"))
        );

        // 2. AdminRecipientRegistry
        registry = factory.create(
            adminRegistryBeacon,
            abi.encodeWithSelector(AdminRecipientRegistry.initialize.selector, p.owner),
            keccak256(abi.encodePacked(baseSalt, "registry"))
        );

        // 3. Token (SexyDaiYield)
        token = factory.createToken(
            tokenBeacon,
            abi.encodeWithSelector(SexyDaiYield.initialize.selector, p.tokenName, p.tokenSymbol, p.owner),
            keccak256(abi.encodePacked(baseSalt, "token"))
        );

        // 4. Voting power strategy (uses constructor immutables, deployed directly)
        votingPowerStrategy =
            address(new TimeWeightedVotingPower(IVotesCheckpoints(token), AbstractCycleModule(cycleModule)));

        // 5. Deploy the three mutually-dependent modules: distManager, votingModule, strategy.
        //
        //    Circular dependency: distManager needs votingModule + strategy addresses,
        //    votingModule needs distManager address, strategy needs distManager address.
        //    CREATE2 addresses depend on the full payload (including these addresses),
        //    so we cannot pre-compute a self-consistent set.
        //
        //    Resolution: deploy distManager first with placeholders (the deployer address
        //    for votingModule, address(0) for strategy), then deploy votingModule + strategy
        //    with the real distManager address, then wire both back via setters.

        // 5a. Deploy BaseDistributionManager (votingModule=placeholder, strategy=zero)
        distributionManager = factory.create(
            baseDistManagerBeacon,
            abi.encodeWithSelector(
                BaseDistributionManager.initialize.selector,
                cycleModule,
                registry,
                p.baseToken,
                p.owner, // placeholder — corrected in step 5d
                address(0), // strategy set in step 5d
                p.owner
            ),
            keccak256(abi.encodePacked(baseSalt, "dist-manager"))
        );

        // 5b. Deploy EqualDistributionStrategy with real distManager
        distributionStrategy = factory.create(
            equalStrategyBeacon,
            abi.encodeWithSelector(
                EqualDistributionStrategy.initialize.selector, p.yieldToken, registry, distributionManager, p.owner
            ),
            keccak256(abi.encodePacked(baseSalt, "strategy"))
        );

        // 5c. Deploy BasisPointsVotingModule with real distManager
        IVotingPowerStrategy[] memory vpStrategies = new IVotingPowerStrategy[](1);
        vpStrategies[0] = IVotingPowerStrategy(votingPowerStrategy);

        votingModule = factory.create(
            votingModuleBeacon,
            abi.encodeWithSelector(
                BasisPointsVotingModule.initialize.selector,
                p.maxVotingPoints,
                vpStrategies,
                distributionManager,
                registry,
                cycleModule,
                p.owner
            ),
            keccak256(abi.encodePacked(baseSalt, "voting"))
        );

        // 5d. Wire the real references into the distManager
        BaseDistributionManager(distributionManager).setDistributionStrategy(distributionStrategy);
        AbstractDistributionManager(distributionManager).setVotingModule(votingModule);
    }

    // ============ Logging ============

    function _logDeployment() internal view {
        console.log("\n=== Full System Deployed ===");
        console.log("Factory:                    ", address(factory));
        console.log("CycleModule:                ", cycleModule);
        console.log("AdminRecipientRegistry:     ", registry);
        console.log("Token:                      ", token);
        console.log("TimeWeightedVotingPower:    ", votingPowerStrategy);
        console.log("BasisPointsVotingModule:    ", votingModule);
        console.log("EqualDistributionStrategy:  ", distributionStrategy);
        console.log("BaseDistributionManager:    ", distributionManager);
    }
}
