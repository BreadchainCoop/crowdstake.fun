// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {CrowdStakeFactory} from "../src/CrowdStakeFactory.sol";
import {CrowdStakeDeployer} from "../src/CrowdStakeDeployer.sol";

import {CycleModule} from "../src/implementation/CycleModule.sol";
import {BasisPointsVotingModule} from "../src/base/BasisPointsVotingModule.sol";
import {BaseDistributionManager} from "../src/base/BaseDistributionManager.sol";
import {VotingDistributionStrategy} from "../src/implementation/strategies/VotingDistributionStrategy.sol";
import {AdminRecipientRegistry} from "../src/implementation/registries/AdminRecipientRegistry.sol";
import {VotingRecipientRegistry} from "../src/implementation/registries/VotingRecipientRegistry.sol";
import {SexyDaiYield} from "../src/implementation/token/SexyDaiYield.sol";

/// @notice Fresh, self-contained deploy of the ONE canonical CrowdStakeDeployer plus its
///         own CrowdStakeFactory and beacons. The token + distribution-manager impls now
///         carry per-instance metadata (ERC-7572 contractURI). The broadcaster owns the
///         factory/beacons, so this relies on no prior deployment and needs no external
///         allowlist tx. Used for the fork e2e and (deferred) the mainnet cutover.
contract DeployCrowdStakeDeployer is Script {
    // Gnosis underlying tokens for SexyDaiYield.
    address constant WXDAI = 0xe91D153E0b41518A2Ce8Dd3D7944Fa863463a97d;
    address constant SXDAI = 0xaf204776c7245bF4147c2612BF6e5972Ee483701;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address me = vm.addr(pk);
        vm.startBroadcast(pk);

        CrowdStakeFactory factory = new CrowdStakeFactory(me);

        address cycleBeacon = address(new UpgradeableBeacon(address(new CycleModule()), me));
        address adminRegBeacon = address(new UpgradeableBeacon(address(new AdminRecipientRegistry()), me));
        address votingRegBeacon = address(new UpgradeableBeacon(address(new VotingRecipientRegistry()), me));
        address tokenBeacon = address(new UpgradeableBeacon(address(new SexyDaiYield(WXDAI, SXDAI)), me));
        address distBeacon = address(new UpgradeableBeacon(address(new BaseDistributionManager()), me));
        address stratBeacon = address(new UpgradeableBeacon(address(new VotingDistributionStrategy()), me));
        address votingBeacon = address(new UpgradeableBeacon(address(new BasisPointsVotingModule()), me));

        address[] memory beacons = new address[](7);
        beacons[0] = cycleBeacon;
        beacons[1] = adminRegBeacon;
        beacons[2] = votingRegBeacon;
        beacons[3] = tokenBeacon;
        beacons[4] = distBeacon;
        beacons[5] = stratBeacon;
        beacons[6] = votingBeacon;
        factory.allowlistBeacons(beacons);

        CrowdStakeDeployer d = new CrowdStakeDeployer(
            address(factory),
            cycleBeacon,
            adminRegBeacon,
            votingRegBeacon,
            tokenBeacon,
            distBeacon,
            stratBeacon,
            votingBeacon
        );

        vm.stopBroadcast();
        console.log("CrowdStakeDeployer:", address(d));
        console.log("FACTORY:", address(factory));
    }
}
