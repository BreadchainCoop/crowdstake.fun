// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {CrowdStakeFactory} from "../../src/CrowdStakeFactory.sol";
import {CycleModule} from "../../src/implementation/CycleModule.sol";
import {AbstractCycleModule} from "../../src/abstract/AbstractCycleModule.sol";
import {BaseDistributionManager} from "../../src/base/BaseDistributionManager.sol";
import {AbstractDistributionManager} from "../../src/abstract/AbstractDistributionManager.sol";
import {IVotingPowerStrategy} from "../../src/interfaces/IVotingPowerStrategy.sol";

import {MockUSD} from "../../src/cova/mocks/MockUSD.sol";
import {MockUSDVault} from "../../src/cova/mocks/MockUSDVault.sol";
import {CovaDollarYield} from "../../src/cova/CovaDollarYield.sol";
import {CovaProjectRegistry} from "../../src/cova/CovaProjectRegistry.sol";
import {OnePersonOneVotePower} from "../../src/cova/OnePersonOneVotePower.sol";
import {CovaPointsVotingModule} from "../../src/cova/CovaPointsVotingModule.sol";
import {CovaArtFundStrategy} from "../../src/cova/CovaArtFundStrategy.sol";
import {CovaWithdrawals} from "../../src/cova/CovaWithdrawals.sol";

/// @title CovaCrowdstakeTest
/// @notice The front-end flows running through the real crowdstake stack:
///         AbstractToken yield, AbstractCycleModule, AbstractRecipientRegistry,
///         AbstractVotingModule (one-person-one-vote), AbstractDistribution
///         Strategy (min-viable allocation) + AbstractDistributionManager,
///         all deployed via CrowdStakeFactory; plus the COVA withdrawals module.
contract CovaCrowdstakeTest is Test {
    uint256 constant E = 1e18;
    uint256 constant CYCLE = 5;

    address coord = address(this);
    address m1 = address(0xA1);
    address m2 = address(0xA2);

    MockUSD usd;
    MockUSDVault vault;
    CovaDollarYield tok;
    CovaProjectRegistry reg;
    OnePersonOneVotePower power;
    CovaPointsVotingModule voting;
    CovaArtFundStrategy strat;
    BaseDistributionManager dm;
    CycleModule cyc;
    CovaWithdrawals wd;

    address[6] P = [address(0xB1), address(0xB2), address(0xB3), address(0xB4), address(0xB5), address(0xB6)];

    function _beacon(address impl) internal returns (address) {
        return address(new UpgradeableBeacon(impl, coord));
    }

    function setUp() public {
        usd = new MockUSD();
        vault = new MockUSDVault(address(usd));
        power = new OnePersonOneVotePower(coord);

        CrowdStakeFactory f = new CrowdStakeFactory(coord);
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
        f.allowlistBeacons(bs);

        cyc = CycleModule(
            f.create(
                cycB, abi.encodeWithSelector(AbstractCycleModule.initialize.selector, CYCLE, coord), keccak256("c")
            )
        );
        reg = CovaProjectRegistry(
            f.create(regB, abi.encodeWithSelector(CovaProjectRegistry.initialize.selector, coord), keccak256("r"))
        );
        tok = CovaDollarYield(
            f.createToken(
                tokB,
                abi.encodeWithSelector(CovaDollarYield.initialize.selector, "COVA USD", "cUSD", coord),
                keccak256("t")
            )
        );

        dm = BaseDistributionManager(
            f.create(
                dmB,
                abi.encodeWithSelector(
                    BaseDistributionManager.initialize.selector,
                    address(cyc),
                    address(reg),
                    address(tok),
                    coord,
                    address(0),
                    coord
                ),
                keccak256("d")
            )
        );

        strat = CovaArtFundStrategy(
            f.create(
                stB,
                abi.encodeWithSelector(
                    CovaArtFundStrategy.initialize.selector, address(tok), address(dm), coord, uint256(5)
                ),
                keccak256("s")
            )
        );

        IVotingPowerStrategy[] memory vps = new IVotingPowerStrategy[](1);
        vps[0] = IVotingPowerStrategy(address(power));
        voting = CovaPointsVotingModule(
            f.create(
                vmB,
                abi.encodeWithSelector(CovaPointsVotingModule.initialize.selector, vps, address(dm), coord),
                keccak256("v")
            )
        );

        dm.setDistributionStrategy(address(strat));
        AbstractDistributionManager(address(dm)).setVotingModule(address(voting));
        cyc.setDistributionManager(address(dm));
        tok.setYieldClaimer(address(dm));

        wd = CovaWithdrawals(
            f.create(
                wdB,
                abi.encodeWithSelector(CovaWithdrawals.initialize.selector, address(tok), address(power), coord),
                keccak256("w")
            )
        );

        address[] memory mem = new address[](3);
        mem[0] = coord;
        mem[1] = m1;
        mem[2] = m2;
        power.addMembers(mem);

        // Six projects (front-end defaults / worked example budgets).
        reg.registerProject(P[0], 5000 * E, 2000 * E, "Mural", "s");
        reg.registerProject(P[1], 3000 * E, 1500 * E, "Theatre", "s");
        reg.registerProject(P[2], 1200 * E, 400 * E, "Zine", "s");
        reg.registerProject(P[3], 5000 * E, 1800 * E, "Sculpture", "s");
        reg.registerProject(P[4], 5000 * E, 800 * E, "Workshops", "s");
        reg.registerProject(P[5], 5000 * E, 500 * E, "Print", "s");
        reg.processQueue();
    }

    function _mintCusd(uint256 amount) internal {
        usd.mint(coord, amount);
        usd.approve(address(tok), amount);
        tok.mint(coord, amount);
    }

    function _pts(uint256 a, uint256 b, uint256 c, uint256 d, uint256 e, uint256 f)
        internal
        pure
        returns (uint256[] memory p)
    {
        p = new uint256[](6);
        p[0] = a;
        p[1] = b;
        p[2] = c;
        p[3] = d;
        p[4] = e;
        p[5] = f;
    }

    // ---- token uses the crowdstake AbstractToken / yield machinery ----

    function test_tokenYieldViaAbstractToken() public {
        _mintCusd(1000 * E);
        assertEq(tok.balanceOf(coord), 1000 * E);
        assertEq(tok.yieldAccrued(), 0);
        vault.simulateYield(250 * E);
        assertEq(tok.yieldAccrued(), 250 * E, "yield = vault growth over principal");
    }

    // ---- full pipeline: vote -> cycle -> manager -> strategy allocation ----

    function test_roundFundsViaDistributionManager() public {
        _mintCusd(2_000_000 * E);
        vault.simulateYield(8000 * E); // Art Fund pool this cycle

        vm.prank(m1); // 77
        voting.castVote(_pts(20, 15, 13, 12, 9, 8));
        vm.prank(m2); // 73
        voting.castVote(_pts(18, 14, 13, 12, 9, 7));
        // totals: 38,29,26,24,18,15

        vm.roll(block.number + CYCLE + 1);
        assertTrue(dm.isDistributionReady(), "ready: cycle done, votes, yield");

        dm.claimAndDistribute();

        // Sculpture (P[3], min 1800) dropped; Print (P[5]) promoted; Zine
        // (P[2]) capped at its 1200 full budget.
        assertEq(tok.balanceOf(P[3]), 0, "sculpture dropped (below min viable)");
        assertEq(tok.balanceOf(P[2]), 1200 * E, "zine capped at full budget");
        assertEq(tok.balanceOf(P[0]), 2584 * E, "mural");
        assertEq(tok.balanceOf(P[1]), 1972 * E, "theatre");
        assertEq(tok.balanceOf(P[4]), 1224 * E, "workshops");
        assertEq(tok.balanceOf(P[5]), 1020 * E, "print (promoted)");
        assertEq(
            tok.balanceOf(P[0]) + tok.balanceOf(P[1]) + tok.balanceOf(P[2]) + tok.balanceOf(P[4]) + tok.balanceOf(P[5]),
            8000 * E,
            "whole Art Fund pool distributed"
        );
        assertEq(cyc.getCurrentCycle(), 2, "cycle advanced with distribution");
    }

    function test_distributionGatedByCycle() public {
        _mintCusd(1_000_000 * E);
        vault.simulateYield(8000 * E);
        vm.prank(m1);
        voting.castVote(_pts(20, 15, 13, 12, 9, 8));
        // cycle NOT complete yet
        assertFalse(dm.isDistributionReady(), "not ready before cycle elapses");
        vm.expectRevert(); // BaseDistributionManager.DistributionNotReady
        dm.claimAndDistribute();
    }

    function test_oneClaimPerCycleNoDrain() public {
        _mintCusd(1_000_000 * E);
        vault.simulateYield(8000 * E);
        vm.prank(m1);
        voting.castVote(_pts(20, 15, 13, 12, 9, 8));
        vm.roll(block.number + CYCLE + 1);
        dm.claimAndDistribute();
        // Second call in the same (new) cycle must revert: cycle reset, no time.
        vm.expectRevert();
        dm.claimAndDistribute();
    }

    function test_nonMemberCannotVote() public {
        vm.prank(address(0xDEAD));
        vm.expectRevert(CovaPointsVotingModule.NotAMember.selector);
        voting.castVote(_pts(50, 0, 0, 0, 0, 0));
    }

    function test_ballotCannotExceed100() public {
        vm.prank(m1);
        vm.expectRevert(CovaPointsVotingModule.ExceedsTotalPoints.selector);
        voting.castVote(_pts(60, 50, 0, 0, 0, 0));
    }

    // ---- withdrawals module (four funds, one-person-one-vote) ----

    function test_withdrawalFlow() public {
        _mintCusd(5350 * E);
        tok.approve(address(wd), 5350 * E);
        wd.allocateInflow([uint256(1200 * E), 800 * E, 950 * E, 2400 * E], "Quarterly");
        assertEq(wd.getFunds()[1], 800 * E);

        vm.prank(m1);
        uint256 id = wd.proposeWithdrawal(1, 300 * E, address(0xCAFE), "Workshop");
        vm.prank(m2);
        wd.voteWithdrawal(id, true);
        vm.prank(coord);
        wd.voteWithdrawal(id, true);
        vm.prank(m1);
        wd.closeWithdrawal(id);

        assertEq(uint8(wd.getWithdrawal(id).status), uint8(CovaWithdrawals.Status.Approved));
        assertEq(tok.balanceOf(address(0xCAFE)), 300 * E, "released to recipient");
        assertEq(wd.getFunds()[1], 500 * E, "education reduced");
    }

    function test_cannotWithdrawNonexistentFund() public {
        vm.prank(m1);
        vm.expectRevert(CovaWithdrawals.InvalidFund.selector);
        wd.proposeWithdrawal(4, 1, address(0xCAFE), "x");
    }
}
