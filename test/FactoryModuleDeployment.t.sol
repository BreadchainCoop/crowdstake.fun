// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {CrowdStakeFactory} from "../src/CrowdStakeFactory.sol";
import {CycleModule} from "../src/implementation/CycleModule.sol";
import {AbstractCycleModule} from "../src/abstract/AbstractCycleModule.sol";
import {BasisPointsVotingModule} from "../src/base/BasisPointsVotingModule.sol";
import {BaseDistributionManager} from "../src/base/BaseDistributionManager.sol";
import {EqualDistributionStrategy} from "../src/implementation/strategies/EqualDistributionStrategy.sol";
import {RecipientRegistry} from "../src/implementation/registries/RecipientRegistry.sol";
import {AdminRecipientRegistry} from "../src/implementation/registries/AdminRecipientRegistry.sol";
import {ICycleModule} from "../src/interfaces/ICycleModule.sol";

contract FactoryModuleDeploymentTest is Test {
    CrowdStakeFactory public factory;
    address public owner;

    function setUp() public {
        owner = address(this);
        factory = new CrowdStakeFactory(owner);
    }

    // ============ CycleModule via Factory ============

    function test_createCycleModuleViaFactory() public {
        // Deploy implementation and beacon
        address impl = address(new CycleModule());
        address beacon = address(new UpgradeableBeacon(impl, owner));

        // Whitelist beacon
        address[] memory beacons = new address[](1);
        beacons[0] = beacon;
        factory.whitelistBeacons(beacons);

        // Create module via factory
        bytes memory payload = abi.encodeWithSelector(AbstractCycleModule.initialize.selector, 100, owner);
        address module = factory.createModule(beacon, payload, keccak256("cycle-salt"));

        // Verify module was deployed and initialized
        assertTrue(module != address(0));
        assertEq(ICycleModule(module).cycleLength(), 100);
        assertEq(ICycleModule(module).getCurrentCycle(), 1);
    }

    function test_computeModuleAddress() public {
        address impl = address(new CycleModule());
        address beacon = address(new UpgradeableBeacon(impl, owner));

        address[] memory beacons = new address[](1);
        beacons[0] = beacon;
        factory.whitelistBeacons(beacons);

        bytes memory payload = abi.encodeWithSelector(AbstractCycleModule.initialize.selector, 100, owner);
        bytes32 salt = keccak256("cycle-salt");

        // Compute address before deployment
        address predicted = factory.computeModuleAddress(beacon, payload, salt);

        // Deploy and verify
        address actual = factory.createModule(beacon, payload, salt);
        assertEq(predicted, actual);
    }

    function test_createModuleRevertsNotWhitelistedBeacon() public {
        address impl = address(new CycleModule());
        address beacon = address(new UpgradeableBeacon(impl, owner));

        bytes memory payload = abi.encodeWithSelector(AbstractCycleModule.initialize.selector, 100, owner);

        vm.expectRevert(CrowdStakeFactory.NotWhitelistedBeacon.selector);
        factory.createModule(beacon, payload, keccak256("salt"));
    }

    // ============ RecipientRegistry via Factory ============

    function test_createRecipientRegistryViaFactory() public {
        address impl = address(new RecipientRegistry());
        address beacon = address(new UpgradeableBeacon(impl, owner));

        address[] memory beacons = new address[](1);
        beacons[0] = beacon;
        factory.whitelistBeacons(beacons);

        bytes memory payload = abi.encodeWithSelector(RecipientRegistry.initialize.selector, owner);
        address module = factory.createModule(beacon, payload, keccak256("registry-salt"));

        assertTrue(module != address(0));
        assertTrue(module.code.length > 0);
    }

    function test_createAdminRecipientRegistryViaFactory() public {
        address impl = address(new AdminRecipientRegistry());
        address beacon = address(new UpgradeableBeacon(impl, owner));

        address[] memory beacons = new address[](1);
        beacons[0] = beacon;
        factory.whitelistBeacons(beacons);

        bytes memory payload = abi.encodeWithSelector(AdminRecipientRegistry.initialize.selector, owner);
        address module = factory.createModule(beacon, payload, keccak256("admin-registry-salt"));

        assertTrue(module != address(0));
        assertTrue(module.code.length > 0);
    }

    // ============ EqualDistributionStrategy via Factory ============

    function test_createEqualDistributionStrategyViaFactory() public {
        address impl = address(new EqualDistributionStrategy());
        address beacon = address(new UpgradeableBeacon(impl, owner));

        address[] memory beacons = new address[](1);
        beacons[0] = beacon;
        factory.whitelistBeacons(beacons);

        address yieldToken = address(0x111);
        address recipientRegistry = address(0x222);
        address distributionManager = address(0x333);

        bytes memory payload = abi.encodeWithSelector(
            EqualDistributionStrategy.initialize.selector, yieldToken, recipientRegistry, distributionManager
        );
        address module = factory.createModule(beacon, payload, keccak256("strategy-salt"));

        assertTrue(module != address(0));
        assertTrue(module.code.length > 0);
    }

    // ============ Multiple Modules with Different Salts ============

    function test_createMultipleModulesSameBaconDifferentSalts() public {
        address impl = address(new CycleModule());
        address beacon = address(new UpgradeableBeacon(impl, owner));

        address[] memory beacons = new address[](1);
        beacons[0] = beacon;
        factory.whitelistBeacons(beacons);

        bytes memory payload1 = abi.encodeWithSelector(AbstractCycleModule.initialize.selector, 100, owner);
        bytes memory payload2 = abi.encodeWithSelector(AbstractCycleModule.initialize.selector, 200, owner);

        address module1 = factory.createModule(beacon, payload1, keccak256("salt-1"));
        address module2 = factory.createModule(beacon, payload2, keccak256("salt-2"));

        assertTrue(module1 != module2);
        assertEq(ICycleModule(module1).cycleLength(), 100);
        assertEq(ICycleModule(module2).cycleLength(), 200);
    }

    // ============ Beacon Upgrade Affects All Proxies ============

    function test_beaconUpgradeAffectsAllProxies() public {
        address impl = address(new CycleModule());
        UpgradeableBeacon beacon = new UpgradeableBeacon(impl, owner);

        address[] memory beacons = new address[](1);
        beacons[0] = address(beacon);
        factory.whitelistBeacons(beacons);

        bytes memory payload = abi.encodeWithSelector(AbstractCycleModule.initialize.selector, 100, owner);
        address module = factory.createModule(address(beacon), payload, keccak256("salt"));

        // Verify module works
        assertEq(ICycleModule(module).cycleLength(), 100);

        // Deploy new implementation and upgrade beacon
        address newImpl = address(new CycleModule());
        beacon.upgradeTo(newImpl);

        // Module still works after upgrade (state preserved)
        assertEq(ICycleModule(module).cycleLength(), 100);
        assertEq(ICycleModule(module).getCurrentCycle(), 1);
    }
}
