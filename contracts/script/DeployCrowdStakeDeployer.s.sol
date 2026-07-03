// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {CrowdStakeFactory} from "../src/CrowdStakeFactory.sol";
import {CrowdStakeDeployer} from "../src/CrowdStakeDeployer.sol";

import {CycleModule} from "../src/implementation/CycleModule.sol";
import {BasisPointsVotingModule} from "../src/base/BasisPointsVotingModule.sol";
import {BaseDistributionManager} from "../src/base/BaseDistributionManager.sol";
import {MultiStrategyDistributionManager} from "../src/base/MultiStrategyDistributionManager.sol";
import {VotingDistributionStrategy} from "../src/implementation/strategies/VotingDistributionStrategy.sol";
import {EqualDistributionStrategy} from "../src/implementation/strategies/EqualDistributionStrategy.sol";
import {AdminRecipientRegistry} from "../src/implementation/registries/AdminRecipientRegistry.sol";
import {VotingRecipientRegistry} from "../src/implementation/registries/VotingRecipientRegistry.sol";
import {SexyDaiYield} from "../src/implementation/token/SexyDaiYield.sol";
import {StableYield} from "../src/implementation/token/StableYield.sol";

/// @notice Fresh, self-contained deploy of the ONE canonical CrowdStakeDeployer plus its
///         own CrowdStakeFactory and beacons. The token + distribution-manager impls now
///         carry per-instance metadata (ERC-7572 contractURI). The broadcaster owns the
///         factory/beacons, so this relies on no prior deployment and needs no external
///         allowlist tx. Used for the fork e2e and the mainnet/L2 cutovers.
///
/// @dev CHAIN-PARAMETERIZED yield token. Two kinds (env YIELD_KIND, default "native"):
///      - "native": SexyDaiYield(ASSET, YIELD_VAULT) — deposit native, ASSET is the
///                  wrapped-native (WXDAI); the vault (sDAI) is denominated in it. Gnosis.
///      - "stable": StableYield(ASSET, YIELD_VAULT) — deposit an ERC-20 stablecoin (ASSET,
///                  e.g. USDC); higher-yield Morpho USDC vaults on Arbitrum/Optimism.
///      Defaults are Gnosis WXDAI+sDAI. See contracts/deployments/yield-assets.md.
contract DeployCrowdStakeDeployer is Script {
    // Gnosis defaults (native xDAI → WXDAI → sDAI).
    address constant DEFAULT_ASSET = 0xe91D153E0b41518A2Ce8Dd3D7944Fa863463a97d; // WXDAI
    address constant DEFAULT_YIELD_VAULT = 0xaf204776c7245bF4147c2612BF6e5972Ee483701; // sDAI

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address me = vm.addr(pk);
        // ASSET is the deposit token: wrapped-native for "native", a stablecoin for "stable".
        // (WRAPPED_NATIVE kept as an alias for backwards compatibility.)
        address asset = vm.envOr("ASSET", vm.envOr("WRAPPED_NATIVE", DEFAULT_ASSET));
        address yieldVault = vm.envOr("YIELD_VAULT", DEFAULT_YIELD_VAULT);
        vm.startBroadcast(pk);

        CrowdStakeFactory factory = new CrowdStakeFactory(me);

        address cycleBeacon = address(new UpgradeableBeacon(address(new CycleModule()), me));
        address adminRegBeacon = address(new UpgradeableBeacon(address(new AdminRecipientRegistry()), me));
        address votingRegBeacon = address(new UpgradeableBeacon(address(new VotingRecipientRegistry()), me));
        address tokenBeacon = address(new UpgradeableBeacon(_tokenImpl(asset, yieldVault), me));
        address distBeacon = address(new UpgradeableBeacon(address(new BaseDistributionManager()), me));
        address multiDistBeacon = address(new UpgradeableBeacon(address(new MultiStrategyDistributionManager()), me));
        address stratBeacon = address(new UpgradeableBeacon(address(new VotingDistributionStrategy()), me));
        address equalStratBeacon = address(new UpgradeableBeacon(address(new EqualDistributionStrategy()), me));
        address votingBeacon = address(new UpgradeableBeacon(address(new BasisPointsVotingModule()), me));

        address[] memory beacons = new address[](9);
        beacons[0] = cycleBeacon;
        beacons[1] = adminRegBeacon;
        beacons[2] = votingRegBeacon;
        beacons[3] = tokenBeacon;
        beacons[4] = distBeacon;
        beacons[5] = multiDistBeacon;
        beacons[6] = stratBeacon;
        beacons[7] = equalStratBeacon;
        beacons[8] = votingBeacon;
        factory.allowlistBeacons(beacons);

        CrowdStakeDeployer d = new CrowdStakeDeployer(
            address(factory),
            cycleBeacon,
            adminRegBeacon,
            votingRegBeacon,
            tokenBeacon,
            distBeacon,
            multiDistBeacon,
            stratBeacon,
            equalStratBeacon,
            votingBeacon
        );

        vm.stopBroadcast();
        console.log("CrowdStakeDeployer:", address(d));
        console.log("FACTORY:", address(factory));
        console.log("YIELD_KIND:", _stable() ? "stable" : "native");
        console.log("ASSET:", asset);
        console.log("YIELD_VAULT:", yieldVault);
    }

    /// @dev "stable" → StableYield (ERC-20 stablecoin deposit); else native SexyDaiYield.
    function _stable() internal view returns (bool) {
        return keccak256(bytes(vm.envOr("YIELD_KIND", string("native")))) == keccak256(bytes("stable"));
    }

    /// @dev Deploy the token implementation matching YIELD_KIND (broadcast-safe).
    function _tokenImpl(address asset, address yieldVault) internal returns (address) {
        return _stable() ? address(new StableYield(asset, yieldVault)) : address(new SexyDaiYield(asset, yieldVault));
    }
}
