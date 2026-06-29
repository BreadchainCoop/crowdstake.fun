// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {MockDistributionManagerSimple} from "../test/mocks/MockDistributionManagerSimple.sol";
import {ChainlinkAutomation} from "../src/implementation/automation/ChainlinkAutomation.sol";

/// @title DeployMockAutomation
/// @notice Deploy script for mock distribution manager with Chainlink automation
contract DeployMockAutomation is Script {
    function run() external returns (address mockDistributionManager, address chainlinkAuto) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy MockDistributionManagerSimple
        MockDistributionManagerSimple mock = new MockDistributionManagerSimple();
        console.log("MockDistributionManagerSimple deployed at:", address(mock));
        console.log("Will trigger every 200 blocks");

        // Deploy ChainlinkAutomation with MockDistributionManagerSimple
        ChainlinkAutomation chainlink = new ChainlinkAutomation(address(mock));
        console.log("ChainlinkAutomation deployed at:", address(chainlink));

        // Log initial state
        console.log("Current block:", block.number);
        console.log("Last distribution block:", mock.getLastDistributionBlock());
        console.log("Blocks until next distribution:", mock.blocksUntilDistribution());
        console.log("Is distribution ready:", mock.isDistributionReady());

        vm.stopBroadcast();

        return (address(mock), address(chainlink));
    }

    /// @notice Deploy only the mock distribution manager
    function deployMockDistributionManagerSimple() external returns (address) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        MockDistributionManagerSimple mock = new MockDistributionManagerSimple();
        console.log("MockDistributionManagerSimple deployed at:", address(mock));

        vm.stopBroadcast();

        return address(mock);
    }

    /// @notice Deploy chainlink automation with existing distribution manager
    function deployChainlinkAutomation(address distributionManager) external returns (address) {
        require(distributionManager != address(0), "Invalid distribution manager");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        ChainlinkAutomation chainlink = new ChainlinkAutomation(distributionManager);
        console.log("ChainlinkAutomation deployed at:", address(chainlink));
        console.log("Using DistributionManager at:", distributionManager);

        vm.stopBroadcast();

        return address(chainlink);
    }
}
