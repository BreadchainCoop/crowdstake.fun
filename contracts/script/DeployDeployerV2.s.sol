// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {CrowdStakeDeployerV2} from "../src/CrowdStakeDeployerV2.sol";

/// @notice Deploys CrowdStakeDeployerV2 wired to the LIVE Gnosis factory + beacons.
///         The VotingRecipientRegistry beacon (0x498a0b…) is already allowlisted on
///         the live factory, so no factory change is required.
contract DeployDeployerV2 is Script {
    // Live Gnosis deployment (contracts/deployments/gnosis-factory.json + broadcast log).
    address constant FACTORY = 0x75b383Dc91822Bc8138a75fd8E7aE144f88AEed6;
    address constant CYCLE_BEACON = 0x4108acEDbF2D0e1806A589903945A0CA260Bf2Da;
    address constant ADMIN_REGISTRY_BEACON = 0x856f8c0D2D56aCfC0d77b98BdD2Aec9283b6bBeA;
    address constant VOTING_REGISTRY_BEACON = 0x498A0bcfdAd24dcCad33783893B0F714970AEfF5;
    address constant TOKEN_BEACON = 0x97B0A0Ef59Cb1e43C29E6748eBAF03f109f5486f;
    address constant DIST_MANAGER_BEACON = 0xAA3A42Be84Bb45d59faF15b44f72943d4D0665b4;
    address constant STRATEGY_BEACON = 0xC47deCD27Ea604e6B423CcA1d1C4cBEc328930c1;
    address constant VOTING_BEACON = 0x8D8855FAE60FaFfF906305b9fDA8840d7d7Ec3d1;

    function run() external {
        vm.startBroadcast();
        CrowdStakeDeployerV2 d = new CrowdStakeDeployerV2(
            FACTORY,
            CYCLE_BEACON,
            ADMIN_REGISTRY_BEACON,
            VOTING_REGISTRY_BEACON,
            TOKEN_BEACON,
            DIST_MANAGER_BEACON,
            STRATEGY_BEACON,
            VOTING_BEACON
        );
        vm.stopBroadcast();
        console.log("CrowdStakeDeployerV2:", address(d));
    }
}
