// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {CrowdStakeFactory} from "../src/CrowdStakeFactory.sol";
import {CycleModule} from "../src/implementation/CycleModule.sol";
import {AbstractCycleModule} from "../src/abstract/AbstractCycleModule.sol";
import {BaseDistributionManager} from "../src/base/BaseDistributionManager.sol";
import {AbstractDistributionManager} from "../src/abstract/AbstractDistributionManager.sol";
import {IVotingPowerStrategy} from "../src/interfaces/IVotingPowerStrategy.sol";

import {MockUSD} from "../src/cova/mocks/MockUSD.sol";
import {MockUSDVault} from "../src/cova/mocks/MockUSDVault.sol";
import {CovaDollarYield} from "../src/cova/CovaDollarYield.sol";
import {CovaProjectRegistry} from "../src/cova/CovaProjectRegistry.sol";
import {OnePersonOneVotePower} from "../src/cova/OnePersonOneVotePower.sol";
import {CovaPointsVotingModule} from "../src/cova/CovaPointsVotingModule.sol";
import {CovaArtFundStrategy} from "../src/cova/CovaArtFundStrategy.sol";
import {CovaWithdrawals} from "../src/cova/CovaWithdrawals.sol";

/// @title DeployCova
/// @notice Deploys the COVA system fully on the crowdstake stack — every
///         module through {CrowdStakeFactory} beacons, wired like the
///         protocol's own Deploy script — and seeds the front end's data.
contract DeployCova is Script {
    uint256 constant E = 1e18;
    uint256 constant CYCLE = 5; // blocks (~1 min on Sepolia) — demo cadence

    address dep;
    MockUSD usd;
    MockUSDVault vault;
    OnePersonOneVotePower power;
    CrowdStakeFactory factory;
    address cyc;
    address reg;
    address tok;
    address dm;
    address strat;
    address voting;
    address wd;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        dep = vm.addr(pk);

        vm.startBroadcast(pk);
        _infra();
        _system();
        _seed();
        vm.stopBroadcast();

        console.log("=== COVA (crowdstake-native) deployed on Sepolia ===");
        console.log("MockUSD:            ", address(usd));
        console.log("MockUSDVault:       ", address(vault));
        console.log("CovaDollarYield cUSD:", tok);
        console.log("OnePersonOneVote:   ", address(power));
        console.log("CrowdStakeFactory:  ", address(factory));
        console.log("CycleModule:        ", cyc);
        console.log("CovaProjectRegistry:", reg);
        console.log("CovaPointsVoting:   ", voting);
        console.log("CovaArtFundStrategy:", strat);
        console.log("DistributionManager:", dm);
        console.log("CovaWithdrawals:    ", wd);
    }

    function _infra() internal {
        usd = new MockUSD();
        vault = new MockUSDVault(address(usd));
        power = new OnePersonOneVotePower(dep);
        factory = new CrowdStakeFactory(dep);
    }

    function _beacon(address impl) internal returns (address) {
        return address(new UpgradeableBeacon(impl, dep));
    }

    function _system() internal {
        address cycB = _beacon(address(new CycleModule()));
        address regB = _beacon(address(new CovaProjectRegistry()));
        address tokB = _beacon(address(new CovaDollarYield(address(usd), address(vault))));
        address dmB = _beacon(address(new BaseDistributionManager()));
        address stB = _beacon(address(new CovaArtFundStrategy()));
        address vmB = _beacon(address(new CovaPointsVotingModule()));
        address wdB = _beacon(address(new CovaWithdrawals()));
        address[] memory bs = new address[](7);
        bs[0] = cycB;
        bs[1] = regB;
        bs[2] = tokB;
        bs[3] = dmB;
        bs[4] = stB;
        bs[5] = vmB;
        bs[6] = wdB;
        factory.allowlistBeacons(bs);

        cyc = factory.create(
            cycB, abi.encodeWithSelector(AbstractCycleModule.initialize.selector, CYCLE, dep), keccak256("cova-cyc")
        );
        reg = factory.create(
            regB, abi.encodeWithSelector(CovaProjectRegistry.initialize.selector, dep), keccak256("cova-reg")
        );
        tok = factory.createToken(
            tokB,
            abi.encodeWithSelector(CovaDollarYield.initialize.selector, "COVA USD", "cUSD", dep),
            keccak256("cova-tok")
        );
        dm = factory.create(
            dmB,
            abi.encodeWithSelector(BaseDistributionManager.initialize.selector, cyc, reg, tok, dep, address(0), dep),
            keccak256("cova-dm")
        );
        strat = factory.create(
            stB,
            abi.encodeWithSelector(CovaArtFundStrategy.initialize.selector, tok, dm, dep, uint256(5)),
            keccak256("cova-st")
        );
        IVotingPowerStrategy[] memory vps = new IVotingPowerStrategy[](1);
        vps[0] = IVotingPowerStrategy(address(power));
        voting = factory.create(
            vmB, abi.encodeWithSelector(CovaPointsVotingModule.initialize.selector, vps, dm, dep), keccak256("cova-vm")
        );
        wd = factory.create(
            wdB,
            abi.encodeWithSelector(CovaWithdrawals.initialize.selector, tok, address(power), dep),
            keccak256("cova-wd")
        );

        BaseDistributionManager(dm).setDistributionStrategy(strat);
        AbstractDistributionManager(dm).setVotingModule(voting);
        AbstractCycleModule(cyc).setDistributionManager(dm);
        CovaDollarYield(tok).setYieldClaimer(dm);
    }

    function _seed() internal {
        address[] memory mem = new address[](5);
        mem[0] = dep;
        mem[1] = 0x86213f1cf0a501857B70Df35c1cb3C2EcF112844; // requested member
        mem[2] = vm.addr(0xC0FFEE01);
        mem[3] = vm.addr(0xC0FFEE02);
        mem[4] = vm.addr(0xC0FFEE03);
        power.addMembers(mem);

        CovaProjectRegistry R = CovaProjectRegistry(reg);
        R.registerProject(
            address(0xA11CE0001),
            5000 * E,
            2000 * E,
            "Mural at the old textile mill",
            "Large-scale community mural; paint, scaffolding, food."
        );
        R.registerProject(
            address(0xA11CE0002),
            3000 * E,
            1500 * E,
            "Community theatre series",
            "Weekly riverside performances; sound + costumes."
        );
        R.registerProject(
            address(0xA11CE0003),
            1200 * E,
            400 * E,
            "Photography zine, 200 copies",
            "Print and distribute an estuary photography zine."
        );
        R.registerProject(
            address(0xA11CE0004),
            2400 * E,
            1800 * E,
            "Sculpture for the plaza",
            "Steel + concrete plinth piece, plaza commission."
        );
        R.registerProject(
            address(0xA11CE0005),
            1800 * E,
            800 * E,
            "Workshops for youth at risk",
            "Three months of weekend painting workshops."
        );
        R.registerProject(
            address(0xA11CE0006),
            1500 * E,
            500 * E,
            "Print studio open hours",
            "Subsidize open studio hours; ink + plates."
        );
        R.processQueue();

        // Art Fund pool: mint cUSD (principal -> vault), then simulate yield.
        usd.mint(dep, 100_000 * E);
        usd.approve(tok, 100_000 * E);
        CovaDollarYield(tok).mint(dep, 100_000 * E);
        vault.simulateYield(8000 * E);

        // Four dedicated funds.
        usd.mint(dep, 5350 * E);
        usd.approve(tok, 5350 * E);
        CovaDollarYield(tok).mint(dep, 5350 * E);
        CovaDollarYield(tok).approve(wd, 5350 * E);
        CovaWithdrawals(wd)
            .allocateInflow([uint256(1200 * E), 800 * E, 950 * E, 2400 * E], "Quarterly cooperative allocation");
    }
}
