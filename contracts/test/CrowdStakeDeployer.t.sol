// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {CrowdStakeFactory} from "../src/CrowdStakeFactory.sol";
import {CrowdStakeDeployer} from "../src/CrowdStakeDeployer.sol";

import {CycleModule} from "../src/implementation/CycleModule.sol";
import {AbstractCycleModule} from "../src/abstract/AbstractCycleModule.sol";
import {BasisPointsVotingModule} from "../src/base/BasisPointsVotingModule.sol";
import {BaseDistributionManager} from "../src/base/BaseDistributionManager.sol";
import {AbstractDistributionManager} from "../src/abstract/AbstractDistributionManager.sol";
import {VotingDistributionStrategy} from "../src/implementation/strategies/VotingDistributionStrategy.sol";
import {AdminRecipientRegistry} from "../src/implementation/registries/AdminRecipientRegistry.sol";
import {SexyDaiYield} from "../src/implementation/token/SexyDaiYield.sol";
import {AbstractToken} from "../src/abstract/AbstractToken.sol";

interface IOwnable {
    function owner() external view returns (address);
}

contract CrowdStakeDeployerTest is Test {
    CrowdStakeDeployer internal deployer;

    address internal constant WXDAI = address(0x11dA1);
    address internal constant SXDAI = address(0x5DA1);
    address internal constant OWNER = address(0xABCD);

    function setUp() public {
        CrowdStakeFactory factory = new CrowdStakeFactory(address(this));

        address cycleBeacon = address(new UpgradeableBeacon(address(new CycleModule()), address(this)));
        address registryBeacon = address(new UpgradeableBeacon(address(new AdminRecipientRegistry()), address(this)));
        address tokenBeacon = address(new UpgradeableBeacon(address(new SexyDaiYield(WXDAI, SXDAI)), address(this)));
        address distBeacon = address(new UpgradeableBeacon(address(new BaseDistributionManager()), address(this)));
        address stratBeacon = address(new UpgradeableBeacon(address(new VotingDistributionStrategy()), address(this)));
        address votingBeacon = address(new UpgradeableBeacon(address(new BasisPointsVotingModule()), address(this)));

        address[] memory beacons = new address[](6);
        beacons[0] = cycleBeacon;
        beacons[1] = registryBeacon;
        beacons[2] = tokenBeacon;
        beacons[3] = distBeacon;
        beacons[4] = stratBeacon;
        beacons[5] = votingBeacon;
        factory.allowlistBeacons(beacons);

        deployer = new CrowdStakeDeployer(
            address(factory), cycleBeacon, registryBeacon, tokenBeacon, distBeacon, stratBeacon, votingBeacon
        );
    }

    function _deploy(bytes32 salt) internal returns (CrowdStakeDeployer.Instance memory) {
        return deployer.deploy(
            CrowdStakeDeployer.Params({
                owner: OWNER,
                cycleLength: 100,
                tokenName: "Test Stake",
                tokenSymbol: "TSTK",
                maxVotingPoints: 10_000,
                salt: salt
            })
        );
    }

    function test_DeploysFullyWiredInstance() public {
        CrowdStakeDeployer.Instance memory i = _deploy("instance-1");

        // Every contract handed to the owner.
        assertEq(IOwnable(i.token).owner(), OWNER, "token owner");
        assertEq(IOwnable(i.cycleModule).owner(), OWNER, "cycle owner");
        assertEq(IOwnable(i.distributionManager).owner(), OWNER, "distMgr owner");
        assertEq(IOwnable(i.registry).owner(), OWNER, "registry owner");
        assertEq(IOwnable(i.distributionStrategy).owner(), OWNER, "strategy owner");
        assertEq(IOwnable(i.votingModule).owner(), OWNER, "voting owner");

        // Wiring complete.
        assertEq(AbstractToken(i.token).yieldClaimer(), i.distributionManager, "yieldClaimer");
        assertEq(AbstractCycleModule(i.cycleModule).distributionManager(), i.distributionManager, "cycle->distMgr");
        assertEq(
            address(BaseDistributionManager(i.distributionManager).distributionStrategy()),
            i.distributionStrategy,
            "distMgr->strategy"
        );
        assertEq(
            address(AbstractDistributionManager(i.distributionManager).votingModule()),
            i.votingModule,
            "distMgr->voting"
        );

        // Sane initial state.
        assertEq(AbstractCycleModule(i.cycleModule).getCurrentCycle(), 1, "cycle #1");
        assertEq(BasisPointsVotingModule(i.votingModule).maxPoints(), 10_000, "maxPoints");
        assertEq(AdminRecipientRegistry(i.registry).getRecipientCount(), 0, "no recipients yet");
    }

    function test_DistinctSaltsGiveDistinctInstances() public {
        CrowdStakeDeployer.Instance memory a = _deploy("alpha");
        CrowdStakeDeployer.Instance memory b = _deploy("beta");
        assertTrue(a.token != b.token, "distinct tokens");
        assertTrue(a.distributionManager != b.distributionManager, "distinct managers");
    }

    function test_RevertWhen_OwnerIsZero() public {
        vm.expectRevert(CrowdStakeDeployer.ZeroOwner.selector);
        deployer.deploy(
            CrowdStakeDeployer.Params({
                owner: address(0),
                cycleLength: 100,
                tokenName: "x",
                tokenSymbol: "x",
                maxVotingPoints: 10_000,
                salt: "z"
            })
        );
    }
}
