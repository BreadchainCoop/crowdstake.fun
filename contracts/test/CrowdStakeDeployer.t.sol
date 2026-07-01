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
import {VotingRecipientRegistry} from "../src/implementation/registries/VotingRecipientRegistry.sol";
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
    address internal constant FOUNDER = address(0xF00D);

    string internal constant TOKEN_IMG = "ipfs://bafyTokenImage";
    string internal constant BANNER_IMG = "https://example.org/banner.png";

    function setUp() public {
        CrowdStakeFactory factory = new CrowdStakeFactory(address(this));

        address cycleBeacon = address(new UpgradeableBeacon(address(new CycleModule()), address(this)));
        address registryBeacon = address(new UpgradeableBeacon(address(new AdminRecipientRegistry()), address(this)));
        address votingRegistryBeacon =
            address(new UpgradeableBeacon(address(new VotingRecipientRegistry()), address(this)));
        address tokenBeacon = address(new UpgradeableBeacon(address(new SexyDaiYield(WXDAI, SXDAI)), address(this)));
        address distBeacon = address(new UpgradeableBeacon(address(new BaseDistributionManager()), address(this)));
        address stratBeacon = address(new UpgradeableBeacon(address(new VotingDistributionStrategy()), address(this)));
        address votingBeacon = address(new UpgradeableBeacon(address(new BasisPointsVotingModule()), address(this)));

        address[] memory beacons = new address[](7);
        beacons[0] = cycleBeacon;
        beacons[1] = registryBeacon;
        beacons[2] = votingRegistryBeacon;
        beacons[3] = tokenBeacon;
        beacons[4] = distBeacon;
        beacons[5] = stratBeacon;
        beacons[6] = votingBeacon;
        factory.allowlistBeacons(beacons);

        deployer = new CrowdStakeDeployer(
            address(factory),
            cycleBeacon,
            registryBeacon,
            votingRegistryBeacon,
            tokenBeacon,
            distBeacon,
            stratBeacon,
            votingBeacon
        );
    }

    function _adminParams(bytes32 salt) internal pure returns (CrowdStakeDeployer.Params memory) {
        return CrowdStakeDeployer.Params({
            owner: OWNER,
            cycleLength: 100,
            tokenName: "Admin Stake",
            tokenSymbol: "ADMN",
            maxVotingPoints: 10_000,
            salt: salt,
            registryKind: 0,
            initialRecipients: new address[](0),
            proposalExpiry: 0,
            tokenImageURI: "",
            bannerImageURI: ""
        });
    }

    function _votingParams(bytes32 salt, address[] memory founders, uint256 expiry)
        internal
        pure
        returns (CrowdStakeDeployer.Params memory)
    {
        return CrowdStakeDeployer.Params({
            owner: OWNER,
            cycleLength: 100,
            tokenName: "Demo Stake",
            tokenSymbol: "DEMO",
            maxVotingPoints: 10_000,
            salt: salt,
            registryKind: 1,
            initialRecipients: founders,
            proposalExpiry: expiry,
            tokenImageURI: "",
            bannerImageURI: ""
        });
    }

    function test_DeploysAdminInstance() public {
        CrowdStakeDeployer.Instance memory i = deployer.deploy(_adminParams("admin-1"));
        assertEq(IOwnable(i.registry).owner(), OWNER, "registry owner");
        assertEq(AdminRecipientRegistry(i.registry).getRecipientCount(), 0, "admin starts empty");
        assertEq(AbstractToken(i.token).yieldClaimer(), i.distributionManager, "yieldClaimer wired");
        assertEq(AbstractCycleModule(i.cycleModule).getCurrentCycle(), 1, "cycle #1");
    }

    function test_DeploysVotingInstance() public {
        address[] memory founders = new address[](1);
        founders[0] = FOUNDER;
        CrowdStakeDeployer.Instance memory i = deployer.deploy(_votingParams("voting-1", founders, 7 days));

        VotingRecipientRegistry reg = VotingRecipientRegistry(i.registry);
        assertEq(reg.owner(), OWNER, "registry owner");
        assertEq(reg.proposalExpiry(), 7 days, "proposal expiry");
        assertEq(reg.getRecipientCount(), 1, "one founding recipient");
        assertTrue(reg.isRecipient(FOUNDER), "founder is a recipient");

        assertEq(AbstractToken(i.token).yieldClaimer(), i.distributionManager, "yieldClaimer wired");
        assertEq(AbstractCycleModule(i.cycleModule).distributionManager(), i.distributionManager, "cycle->distMgr");
    }

    function test_VotingFounderCanProposeExecuteProcess() public {
        address[] memory founders = new address[](1);
        founders[0] = FOUNDER;
        CrowdStakeDeployer.Instance memory i = deployer.deploy(_votingParams("voting-2", founders, 7 days));
        VotingRecipientRegistry reg = VotingRecipientRegistry(i.registry);

        vm.prank(FOUNDER);
        uint256 pid = reg.proposeAddition(address(0xBEEF));
        reg.executeProposal(pid);
        reg.processQueue();
        assertEq(reg.getRecipientCount(), 2, "candidate added by unanimous (n=1) vote");
        assertTrue(reg.isRecipient(address(0xBEEF)), "new recipient active");
    }

    // ---- Instance metadata ----

    function test_DeploySeedsMetadata() public {
        CrowdStakeDeployer.Params memory p = _adminParams("meta-1");
        p.tokenImageURI = TOKEN_IMG;
        p.bannerImageURI = BANNER_IMG;
        CrowdStakeDeployer.Instance memory i = deployer.deploy(p);

        AbstractDistributionManager dm = AbstractDistributionManager(i.distributionManager);
        assertEq(dm.tokenImageURI(), TOKEN_IMG, "token image seeded");
        assertEq(dm.bannerImageURI(), BANNER_IMG, "banner image seeded");
        assertGt(bytes(dm.contractURI()).length, 0, "contractURI assembled");
        // The token pulls contractURI from its distribution manager (the claimer).
        assertEq(AbstractToken(i.token).contractURI(), dm.contractURI(), "token pulls contractURI from dist manager");
    }

    function test_OwnerCanUpdateMetadata() public {
        CrowdStakeDeployer.Instance memory i = deployer.deploy(_adminParams("meta-2"));
        AbstractDistributionManager dm = AbstractDistributionManager(i.distributionManager);
        assertEq(dm.tokenImageURI(), "", "starts empty");

        vm.prank(OWNER);
        dm.setInstanceMetadata(TOKEN_IMG, BANNER_IMG);
        assertEq(dm.tokenImageURI(), TOKEN_IMG, "owner updated token image");
        assertEq(dm.bannerImageURI(), BANNER_IMG, "owner updated banner");
    }

    function test_RevertWhen_NonOwnerSetsMetadata() public {
        CrowdStakeDeployer.Instance memory i = deployer.deploy(_adminParams("meta-3"));
        vm.prank(address(0xDEAD));
        vm.expectRevert();
        AbstractDistributionManager(i.distributionManager).setInstanceMetadata(TOKEN_IMG, BANNER_IMG);
    }

    // ---- Guards ----

    function test_RevertWhen_VotingEmptyInitialRecipients() public {
        vm.expectRevert(CrowdStakeDeployer.EmptyInitialRecipients.selector);
        deployer.deploy(_votingParams("bad-1", new address[](0), 7 days));
    }

    function test_RevertWhen_VotingZeroProposalExpiry() public {
        address[] memory founders = new address[](1);
        founders[0] = FOUNDER;
        vm.expectRevert(CrowdStakeDeployer.ZeroProposalExpiry.selector);
        deployer.deploy(_votingParams("bad-2", founders, 0));
    }

    function test_RevertWhen_OwnerIsZero() public {
        CrowdStakeDeployer.Params memory p = _adminParams("z");
        p.owner = address(0);
        vm.expectRevert(CrowdStakeDeployer.ZeroOwner.selector);
        deployer.deploy(p);
    }
}
