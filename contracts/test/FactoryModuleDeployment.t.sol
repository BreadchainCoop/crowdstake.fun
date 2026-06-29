// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {CrowdStakeFactory} from "../src/CrowdStakeFactory.sol";
import {CycleModule} from "../src/implementation/CycleModule.sol";
import {AbstractCycleModule} from "../src/abstract/AbstractCycleModule.sol";
import {ICycleModule} from "../src/interfaces/ICycleModule.sol";
import {BasisPointsVotingModule} from "../src/base/BasisPointsVotingModule.sol";
import {IVotingPowerStrategy} from "../src/interfaces/IVotingPowerStrategy.sol";
import {BaseDistributionManager} from "../src/base/BaseDistributionManager.sol";
import {MultiStrategyDistributionManager} from "../src/base/MultiStrategyDistributionManager.sol";
import {EqualDistributionStrategy} from "../src/implementation/strategies/EqualDistributionStrategy.sol";
import {VotingDistributionStrategy} from "../src/implementation/strategies/VotingDistributionStrategy.sol";
import {AdminRecipientRegistry} from "../src/implementation/registries/AdminRecipientRegistry.sol";
import {RecipientRegistry} from "../src/implementation/registries/RecipientRegistry.sol";
import {VotingRecipientRegistry} from "../src/implementation/registries/VotingRecipientRegistry.sol";
import {IDistributionStrategy} from "../src/interfaces/IDistributionStrategy.sol";
import {MockDistributionModule} from "./mocks/MockDistributionModule.sol";

contract FactoryModuleDeploymentTest is Test {
    CrowdStakeFactory public factory;
    address public owner;

    // Beacons for each module type
    address public cycleModuleBeacon;
    address public votingModuleBeacon;
    address public baseDistManagerBeacon;
    address public multiDistManagerBeacon;
    address public equalStrategyBeacon;
    address public votingStrategyBeacon;
    address public adminRegistryBeacon;
    address public registryBeacon;
    address public votingRegistryBeacon;

    function setUp() public {
        owner = address(this);
        factory = new CrowdStakeFactory(owner);

        // Deploy implementations and create beacons
        cycleModuleBeacon = _createBeacon(address(new CycleModule()));
        votingModuleBeacon = _createBeacon(address(new BasisPointsVotingModule()));
        baseDistManagerBeacon = _createBeacon(address(new BaseDistributionManager()));
        multiDistManagerBeacon = _createBeacon(address(new MultiStrategyDistributionManager()));
        equalStrategyBeacon = _createBeacon(address(new EqualDistributionStrategy()));
        votingStrategyBeacon = _createBeacon(address(new VotingDistributionStrategy()));
        adminRegistryBeacon = _createBeacon(address(new AdminRecipientRegistry()));
        registryBeacon = _createBeacon(address(new RecipientRegistry()));
        votingRegistryBeacon = _createBeacon(address(new VotingRecipientRegistry()));

        // Allowlist all beacons
        address[] memory beacons = new address[](9);
        beacons[0] = cycleModuleBeacon;
        beacons[1] = votingModuleBeacon;
        beacons[2] = baseDistManagerBeacon;
        beacons[3] = multiDistManagerBeacon;
        beacons[4] = equalStrategyBeacon;
        beacons[5] = votingStrategyBeacon;
        beacons[6] = adminRegistryBeacon;
        beacons[7] = registryBeacon;
        beacons[8] = votingRegistryBeacon;
        factory.allowlistBeacons(beacons);
    }

    function _createBeacon(address impl) internal returns (address) {
        return address(new UpgradeableBeacon(impl, owner));
    }

    // ============ when creating a cycle module ============

    function test_WhenCreatingACycleModule_ShouldDeployAndInitializeCorrectly() public {
        bytes memory payload = abi.encodeWithSelector(AbstractCycleModule.initialize.selector, 1000, owner);
        address module = factory.create(cycleModuleBeacon, payload, keccak256("cycle-salt"));

        ICycleModule cycle = ICycleModule(module);
        assertEq(cycle.getCurrentCycle(), 1);
        assertEq(CycleModule(module).cycleLength(), 1000);
        assertEq(CycleModule(module).owner(), owner);
    }

    // ============ when creating an admin recipient registry ============

    function test_WhenCreatingAnAdminRecipientRegistry_ShouldDeployAndInitializeCorrectly() public {
        bytes memory payload = abi.encodeWithSelector(AdminRecipientRegistry.initialize.selector, owner);
        address module = factory.create(adminRegistryBeacon, payload, keccak256("admin-registry-salt"));

        AdminRecipientRegistry registry = AdminRecipientRegistry(module);
        assertEq(registry.getRecipientCount(), 0);
        assertEq(registry.owner(), owner);
    }

    // ============ when creating a recipient registry ============

    function test_WhenCreatingARecipientRegistry_ShouldDeployAndInitializeCorrectly() public {
        bytes memory payload = abi.encodeWithSelector(RecipientRegistry.initialize.selector, owner);
        address module = factory.create(registryBeacon, payload, keccak256("registry-salt"));

        RecipientRegistry registry = RecipientRegistry(module);
        assertEq(registry.getRecipientCount(), 0);
        assertEq(registry.owner(), owner);
    }

    // ============ when creating a voting recipient registry ============

    function test_WhenCreatingAVotingRecipientRegistry_ShouldDeployAndInitializeCorrectly() public {
        address[] memory initialRecipients = new address[](2);
        initialRecipients[0] = address(0x111);
        initialRecipients[1] = address(0x222);

        bytes memory payload =
            abi.encodeWithSelector(VotingRecipientRegistry.initialize.selector, owner, initialRecipients, 7 days);
        address module = factory.create(votingRegistryBeacon, payload, keccak256("voting-registry-salt"));

        VotingRecipientRegistry registry = VotingRecipientRegistry(module);
        assertEq(registry.getRecipientCount(), 2);
        assertTrue(registry.isRecipient(address(0x111)));
        assertTrue(registry.isRecipient(address(0x222)));
        assertEq(registry.owner(), owner);
    }

    // ============ when creating an equal distribution strategy ============

    function test_WhenCreatingAnEqualDistributionStrategy_ShouldDeployAndInitializeCorrectly() public {
        // Deploy a registry first for the strategy to use
        bytes memory registryPayload = abi.encodeWithSelector(AdminRecipientRegistry.initialize.selector, owner);
        address registry = factory.create(adminRegistryBeacon, registryPayload, keccak256("strat-registry-salt"));

        address mockYieldToken = address(0xABC);
        address mockDistManager = address(0xDEF);
        vm.etch(mockYieldToken, hex"00"); // ensure it has code for the strategy
        vm.etch(mockDistManager, hex"00");

        // Mock the distribution manager to return the registry
        vm.mockCall(mockDistManager, abi.encodeWithSignature("recipientRegistry()"), abi.encode(registry));

        bytes memory payload = abi.encodeWithSelector(
            EqualDistributionStrategy.initialize.selector, mockYieldToken, mockDistManager, owner
        );
        address module = factory.create(equalStrategyBeacon, payload, keccak256("equal-strat-salt"));

        EqualDistributionStrategy strategy = EqualDistributionStrategy(module);
        assertEq(address(strategy.recipientRegistry()), registry);
        assertEq(strategy.distributionManager(), mockDistManager);
    }

    // ============ when creating a voting distribution strategy ============

    function test_WhenCreatingAVotingDistributionStrategy_ShouldDeployAndInitializeCorrectly() public {
        bytes memory registryPayload = abi.encodeWithSelector(AdminRecipientRegistry.initialize.selector, owner);
        address registry = factory.create(adminRegistryBeacon, registryPayload, keccak256("vstrat-registry-salt"));

        address mockYieldToken = address(0xABC);
        address mockDistManager = address(0xDEF);
        address mockVotingModule = address(0xBEEF);
        vm.etch(mockYieldToken, hex"00");
        vm.etch(mockVotingModule, hex"00");
        vm.etch(mockDistManager, hex"00");

        // Mock the distribution manager to return registry and voting module
        vm.mockCall(mockDistManager, abi.encodeWithSignature("recipientRegistry()"), abi.encode(registry));
        vm.mockCall(mockDistManager, abi.encodeWithSignature("votingModule()"), abi.encode(mockVotingModule));

        bytes memory payload = abi.encodeWithSelector(
            VotingDistributionStrategy.initialize.selector, mockYieldToken, mockDistManager, owner
        );
        address module = factory.create(votingStrategyBeacon, payload, keccak256("voting-strat-salt"));

        VotingDistributionStrategy strategy = VotingDistributionStrategy(module);
        assertEq(address(strategy.recipientRegistry()), registry);
        assertEq(address(strategy.votingModule()), mockVotingModule);
        assertEq(strategy.distributionManager(), mockDistManager);
    }

    // ============ when creating a basis points voting module ============

    function test_WhenCreatingABasisPointsVotingModule_ShouldDeployAndInitializeCorrectly() public {
        // Deploy dependencies first
        bytes memory cyclePayload = abi.encodeWithSelector(AbstractCycleModule.initialize.selector, 1000, owner);
        address cycleAddr = factory.create(cycleModuleBeacon, cyclePayload, keccak256("vm-cycle-salt"));

        bytes memory registryPayload = abi.encodeWithSelector(AdminRecipientRegistry.initialize.selector, owner);
        address registryAddr = factory.create(adminRegistryBeacon, registryPayload, keccak256("vm-registry-salt"));

        MockDistributionModule distModule = new MockDistributionModule(registryAddr, cycleAddr);

        // Use a mock voting power strategy
        address mockStrategy = address(0xFACE);
        vm.etch(mockStrategy, hex"00");
        vm.mockCall(mockStrategy, abi.encodeWithSignature("getCurrentVotingPower(address)"), abi.encode(uint256(0)));

        IVotingPowerStrategy[] memory strategies = new IVotingPowerStrategy[](1);
        strategies[0] = IVotingPowerStrategy(mockStrategy);

        bytes memory payload = abi.encodeWithSelector(
            BasisPointsVotingModule.initialize.selector,
            100, // maxPoints
            strategies,
            address(distModule),
            owner
        );
        address module = factory.create(votingModuleBeacon, payload, keccak256("voting-module-salt"));

        BasisPointsVotingModule votingModule = BasisPointsVotingModule(module);
        assertEq(votingModule.maxPoints(), 100);
        assertEq(address(votingModule.recipientRegistry()), registryAddr);
        assertEq(address(votingModule.cycleModule()), cycleAddr);
        // Owner is set via the _owner argument in initialize
        assertEq(votingModule.owner(), owner);
    }

    // ============ when creating a base distribution manager ============

    function test_WhenCreatingABaseDistributionManager_ShouldDeployAndInitializeCorrectly() public {
        // Deploy dependencies
        bytes memory cyclePayload = abi.encodeWithSelector(AbstractCycleModule.initialize.selector, 1000, owner);
        address cycleAddr = factory.create(cycleModuleBeacon, cyclePayload, keccak256("bdm-cycle-salt"));

        bytes memory registryPayload = abi.encodeWithSelector(AdminRecipientRegistry.initialize.selector, owner);
        address registryAddr = factory.create(adminRegistryBeacon, registryPayload, keccak256("bdm-registry-salt"));

        // Mock base token and voting module
        address mockBaseToken = address(0xB0BA);
        address mockVotingModule = address(0xBEEF);
        address mockStrategy = address(0xCAFE);
        vm.etch(mockBaseToken, hex"00");
        vm.etch(mockVotingModule, hex"00");
        vm.etch(mockStrategy, hex"00");

        bytes memory payload = abi.encodeWithSelector(
            BaseDistributionManager.initialize.selector,
            cycleAddr,
            registryAddr,
            mockBaseToken,
            mockVotingModule,
            mockStrategy,
            owner
        );
        address module = factory.create(baseDistManagerBeacon, payload, keccak256("base-dist-salt"));

        BaseDistributionManager manager = BaseDistributionManager(module);
        assertEq(address(manager.cycleManager()), cycleAddr);
        assertEq(address(manager.recipientRegistry()), registryAddr);
        assertEq(address(manager.distributionStrategy()), mockStrategy);
    }

    // ============ when creating a multi strategy distribution manager ============

    function test_WhenCreatingAMultiStrategyDistributionManager_ShouldDeployAndInitializeCorrectly() public {
        bytes memory cyclePayload = abi.encodeWithSelector(AbstractCycleModule.initialize.selector, 1000, owner);
        address cycleAddr = factory.create(cycleModuleBeacon, cyclePayload, keccak256("msdm-cycle-salt"));

        bytes memory registryPayload = abi.encodeWithSelector(AdminRecipientRegistry.initialize.selector, owner);
        address registryAddr = factory.create(adminRegistryBeacon, registryPayload, keccak256("msdm-registry-salt"));

        address mockBaseToken = address(0xB0BA);
        address mockVotingModule = address(0xBEEF);
        address mockStrategy1 = address(0xCAFE);
        address mockStrategy2 = address(0xFACE);
        vm.etch(mockBaseToken, hex"00");
        vm.etch(mockVotingModule, hex"00");
        vm.etch(mockStrategy1, hex"00");
        vm.etch(mockStrategy2, hex"00");

        IDistributionStrategy[] memory strategies = new IDistributionStrategy[](2);
        strategies[0] = IDistributionStrategy(mockStrategy1);
        strategies[1] = IDistributionStrategy(mockStrategy2);

        bytes memory payload = abi.encodeWithSelector(
            MultiStrategyDistributionManager.initialize.selector,
            cycleAddr,
            registryAddr,
            mockBaseToken,
            mockVotingModule,
            strategies,
            owner
        );
        address module = factory.create(multiDistManagerBeacon, payload, keccak256("multi-dist-salt"));

        MultiStrategyDistributionManager manager = MultiStrategyDistributionManager(module);
        assertEq(address(manager.cycleManager()), cycleAddr);
        assertEq(address(manager.recipientRegistry()), registryAddr);
        assertEq(manager.getStrategyCount(), 2);
    }

    // ============ when computing addresses ============

    function test_WhenComputingAddresses_ShouldReturnDeterministicAddress() public view {
        bytes memory payload = abi.encodeWithSelector(AbstractCycleModule.initialize.selector, 1000, owner);
        bytes32 salt = keccak256("compute-test");

        address predicted = factory.computeAddress(cycleModuleBeacon, payload, salt);
        assertTrue(predicted != address(0));
    }

    function test_WhenComputingAddresses_ShouldMatchActualDeploymentAddress() public {
        bytes memory payload = abi.encodeWithSelector(AbstractCycleModule.initialize.selector, 500, owner);
        bytes32 salt = keccak256("match-test");

        address predicted = factory.computeAddress(cycleModuleBeacon, payload, salt);
        address actual = factory.create(cycleModuleBeacon, payload, salt);
        assertEq(predicted, actual);
    }

    // ============ when using non-allowlisted beacon ============

    function test_RevertWhen_UsingNonAllowlistedBeacon() public {
        address fakeBeacon = address(0x999);
        bytes memory payload = abi.encodeWithSelector(AbstractCycleModule.initialize.selector, 1000, owner);

        vm.expectRevert(CrowdStakeFactory.NotAllowlistedBeacon.selector);
        factory.create(fakeBeacon, payload, keccak256("bad-salt"));
    }

    // ============ when assembling full system ============

    function test_WhenAssemblingFullSystem_ShouldDeployAndWireAllModules() public {
        // 1. Deploy CycleModule
        bytes memory cyclePayload = abi.encodeWithSelector(AbstractCycleModule.initialize.selector, 1000, owner);
        address cycleAddr = factory.create(cycleModuleBeacon, cyclePayload, keccak256("sys-cycle"));

        // 2. Deploy AdminRecipientRegistry
        bytes memory registryPayload = abi.encodeWithSelector(AdminRecipientRegistry.initialize.selector, owner);
        address registryAddr = factory.create(adminRegistryBeacon, registryPayload, keccak256("sys-registry"));

        // All modules deployed and initialized via the factory
        CycleModule cycle = CycleModule(cycleAddr);
        AdminRecipientRegistry registry = AdminRecipientRegistry(registryAddr);

        assertEq(cycle.getCurrentCycle(), 1);
        assertEq(cycle.owner(), owner);
        assertEq(registry.getRecipientCount(), 0);
        assertEq(registry.owner(), owner);

        // Add a recipient through the registry
        registry.queueRecipientAddition(address(0x111));
        registry.processQueue();
        assertEq(registry.getRecipientCount(), 1);
    }
}
