// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {CrowdStakeFactory} from "../src/CrowdStakeFactory.sol";
import {CycleModule} from "../src/implementation/CycleModule.sol";
import {AdminRecipientRegistry} from "../src/implementation/registries/AdminRecipientRegistry.sol";
import {BasisPointsVotingModule} from "../src/base/BasisPointsVotingModule.sol";
import {BaseDistributionManager} from "../src/base/BaseDistributionManager.sol";
import {EqualDistributionStrategy} from "../src/implementation/strategies/EqualDistributionStrategy.sol";
import {TokenBasedVotingPower} from "../src/implementation/strategies/TokenBasedVotingPower.sol";
import {IVotingPowerStrategy} from "../src/interfaces/IVotingPowerStrategy.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {ICycleModule} from "../src/interfaces/ICycleModule.sol";

contract CrowdStakeFactoryTest is Test {
    CrowdStakeFactory public factory;
    address public owner;

    event CreateModule(address module, address beacon, bytes payload);
    event CreateTokenBasedVotingPower(address votingPower, address votingToken);

    function setUp() public {
        owner = address(this);
        factory = new CrowdStakeFactory(owner);
    }

    function test_CreateModuleCycleModule() public {
        // Deploy implementation
        CycleModule impl = new CycleModule();
        address beacon = address(new UpgradeableBeacon(address(impl), owner));

        // Whitelist beacon
        address[] memory beacons = new address[](1);
        beacons[0] = beacon;
        factory.whitelistBeacons(beacons);

        // Create module via factory
        bytes memory payload = abi.encodeWithSelector(CycleModule.initialize.selector, 1000, owner);

        address moduleAddr = factory.createModule(beacon, payload, keccak256("cycle-salt"));
        assertTrue(moduleAddr != address(0));

        // Verify the module works
        CycleModule module = CycleModule(moduleAddr);
        assertEq(module.cycleLength(), 1000);
        assertEq(module.getCurrentCycle(), 1);
        assertTrue(module.authorized(owner));
    }

    function test_CreateModuleAdminRecipientRegistry() public {
        // Deploy implementation
        AdminRecipientRegistry impl = new AdminRecipientRegistry();
        address beacon = address(new UpgradeableBeacon(address(impl), owner));

        // Whitelist beacon
        address[] memory beacons = new address[](1);
        beacons[0] = beacon;
        factory.whitelistBeacons(beacons);

        // Create module via factory
        bytes memory payload = abi.encodeWithSelector(AdminRecipientRegistry.initialize.selector, owner);
        address moduleAddr = factory.createModule(beacon, payload, keccak256("registry-salt"));

        // Verify
        AdminRecipientRegistry registry = AdminRecipientRegistry(moduleAddr);
        assertEq(registry.owner(), owner);
        assertEq(registry.getRecipientCount(), 0);
    }

    function test_ComputeModuleAddress() public {
        CycleModule impl = new CycleModule();
        address beacon = address(new UpgradeableBeacon(address(impl), owner));

        address[] memory beacons = new address[](1);
        beacons[0] = beacon;
        factory.whitelistBeacons(beacons);

        bytes memory payload = abi.encodeWithSelector(CycleModule.initialize.selector, 1000, owner);
        bytes32 salt = keccak256("deterministic-salt");

        // Pre-compute address
        address predicted = factory.computeModuleAddress(beacon, payload, salt);

        // Deploy
        address actual = factory.createModule(beacon, payload, salt);

        assertEq(predicted, actual, "Predicted address should match actual");
    }

    function test_CreateTokenBasedVotingPower() public {
        // Use a mock token address (doesn't need to be real for deployment test)
        address mockToken = address(0xBEEF);

        // Ensure the mock has code (TokenBasedVotingPower checks IVotes but not in constructor for code)
        vm.etch(mockToken, hex"00");

        address vpAddr = factory.createTokenBasedVotingPower(mockToken, keccak256("vp-salt"));
        assertTrue(vpAddr != address(0));

        TokenBasedVotingPower vp = TokenBasedVotingPower(vpAddr);
        assertEq(address(vp.VOTING_TOKEN()), mockToken);
    }

    function test_ComputeTokenBasedVotingPowerAddress() public {
        address mockToken = address(0xBEEF);
        vm.etch(mockToken, hex"00");
        bytes32 salt = keccak256("vp-salt");

        address predicted = factory.computeTokenBasedVotingPowerAddress(mockToken, salt);
        address actual = factory.createTokenBasedVotingPower(mockToken, salt);

        assertEq(predicted, actual, "Predicted address should match actual");
    }

    function test_CreateModuleRevertsOnNonWhitelistedBeacon() public {
        address fakeBeacon = address(0xDEAD);
        bytes memory payload = abi.encodeWithSelector(CycleModule.initialize.selector, 1000, owner);

        vm.expectRevert(CrowdStakeFactory.NotWhitelistedBeacon.selector);
        factory.createModule(fakeBeacon, payload, keccak256("salt"));
    }

    function test_MultipleModulesFromSameBeacon() public {
        CycleModule impl = new CycleModule();
        address beacon = address(new UpgradeableBeacon(address(impl), owner));

        address[] memory beacons = new address[](1);
        beacons[0] = beacon;
        factory.whitelistBeacons(beacons);

        // Deploy two instances with different salts
        bytes memory payload = abi.encodeWithSelector(CycleModule.initialize.selector, 1000, owner);
        address module1 = factory.createModule(beacon, payload, keccak256("salt1"));
        address module2 = factory.createModule(beacon, payload, keccak256("salt2"));

        assertTrue(module1 != module2, "Different salts should produce different addresses");
        assertEq(CycleModule(module1).cycleLength(), 1000);
        assertEq(CycleModule(module2).cycleLength(), 1000);
    }
}
