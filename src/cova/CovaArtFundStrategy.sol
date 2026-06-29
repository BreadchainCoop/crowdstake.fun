// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AbstractDistributionStrategy} from "../abstract/AbstractDistributionStrategy.sol";
import {IDistributionManager} from "../interfaces/IDistributionManager.sol";
import {IVotingModule} from "../interfaces/IVotingModule.sol";
import {ICovaProjectRegistry} from "./interfaces/ICovaProjectRegistry.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title CovaArtFundStrategy
/// @author COVA Artist Cooperative
/// @notice Crowdstake {AbstractDistributionStrategy} implementing the Art Fund
///         single-round allocation: rank projects by points, take the top N,
///         allocate proportionally with full-budget caps, drop any project
///         below its Minimum Viable Budget and promote the next, recompute
///         until all funded projects are viable.
/// @dev Driven by the {AbstractDistributionManager}: each cycle the manager
///      claims the {CovaDollarYield} yield, forwards it here and calls
///      `distribute()`, then advances the {AbstractCycleModule}. So funding is
///      strictly cycle-paced through the protocol's cycle-coupled distribution
///      (no bespoke, drainable counter). Votes are read from the voting module
///      via the manager; budgets from the {CovaProjectRegistry}. Any
///      unallocated remainder stays as escrow and rolls into the next cycle.
contract CovaArtFundStrategy is AbstractDistributionStrategy {
    using SafeERC20 for IERC20;

    /// @custom:storage-location erc7201:crowdstake.storage.CovaArtFundStrategy
    struct Store {
        uint256 topN;
    }

    // keccak256(abi.encode(uint256(keccak256("crowdstake.storage.CovaArtFundStrategy")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORE = 0xa27033c73aec8f0bb2d8acbfcd4ed13c0b098e58859e098dcac59d3179606200;

    function _s() private pure returns (Store storage $) {
        assembly {
            $.slot := STORE
        }
    }

    error InvalidTopN();
    error InvalidVotesLength();

    event ProjectFunded(address indexed project, uint256 amount);
    event RoundDistributed(uint256 indexed distributionId, uint256 pool, uint256 distributed);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _yieldToken, address _distributionManager, address _owner, uint256 _topN)
        external
        initializer
    {
        if (_topN == 0) revert InvalidTopN();
        __AbstractDistributionStrategy_init(_yieldToken, _distributionManager, _owner);
        _s().topN = _topN;
    }

    function topN() external view returns (uint256) {
        return _s().topN;
    }

    function setTopN(uint256 n) external onlyOwner {
        if (n == 0) revert InvalidTopN();
        _s().topN = n;
    }

    /// @notice The voting module, read dynamically from the distribution
    ///         manager (so manager updates are reflected automatically).
    function votingModule() public view returns (IVotingModule) {
        return IDistributionManager(distributionManager()).votingModule();
    }

    /// @inheritdoc AbstractDistributionStrategy
    /// @dev `amount` is this cycle's yield (already transferred in by the
    ///      manager). The Art Fund pool is the strategy's whole token balance
    ///      (carry + this cycle's yield). Funds the viable top-N project leads;
    ///      the remainder stays for the next cycle.
    function distribute(uint256 amount) external override onlyDistributionManager {
        if (amount == 0) revert ZeroAmount();

        address[] memory projects = recipientRegistry().getRecipients();
        if (projects.length == 0) revert NoRecipients();

        uint256[] memory points = votingModule().getCurrentVotingDistribution();
        if (points.length != projects.length) revert InvalidVotesLength();

        IERC20 tok = yieldToken();
        uint256 pool = tok.balanceOf(address(this));

        (uint256[] memory alloc, uint256 distributed) = _computeAllocations(pool, projects, points);

        for (uint256 i = 0; i < projects.length; i++) {
            if (alloc[i] > 0) {
                tok.safeTransfer(projects[i], alloc[i]);
                emit ProjectFunded(projects[i], alloc[i]);
            }
        }

        Store storage $ = _s();
        uint256 id = ++_getAbstractDistributionStrategyStorage().distributionId;
        emit RoundDistributed(id, pool, distributed);
        emit DistributionExecuted(id);
        $; // silence
    }

    // ---- single-round allocation (top-N, full cap, min-viable redistribution) ----

    function _computeAllocations(uint256 pool, address[] memory projects, uint256[] memory points)
        internal
        view
        returns (uint256[] memory alloc, uint256 total)
    {
        uint256 n = projects.length;
        alloc = new uint256[](n);
        if (pool == 0) return (alloc, 0);

        (uint256[] memory full, uint256[] memory minv) = _budgets(projects);
        uint256[] memory rank = _rank(points, minv);
        if (rank.length == 0) return (alloc, 0);

        (uint256[] memory sel, uint256[] memory selAlloc) = _finalize(pool, points, full, minv, rank);
        for (uint256 s = 0; s < sel.length; s++) {
            alloc[sel[s]] = selAlloc[s];
            total += selAlloc[s];
        }
    }

    function _budgets(address[] memory projects) internal view returns (uint256[] memory full, uint256[] memory minv) {
        ICovaProjectRegistry reg = ICovaProjectRegistry(address(recipientRegistry()));
        uint256 n = projects.length;
        full = new uint256[](n);
        minv = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            ICovaProjectRegistry.Project memory p = reg.project(projects[i]);
            full[i] = p.fullBudget;
            minv[i] = p.minViableBudget;
        }
    }

    function _finalize(
        uint256 pool,
        uint256[] memory points,
        uint256[] memory full,
        uint256[] memory minv,
        uint256[] memory rank
    ) internal view returns (uint256[] memory sel, uint256[] memory selAlloc) {
        uint256 nTop = _s().topN;
        bool[] memory excluded = new bool[](rank.length);
        while (true) {
            sel = _selectTop(rank, excluded, nTop);
            if (sel.length == 0) return (sel, new uint256[](0));
            selAlloc = _allocateCapped(pool, sel, points, full);
            int256 drop = _weakestBelowMin(sel, selAlloc, minv);
            if (drop < 0) return (sel, selAlloc);
            _exclude(rank, excluded, sel[uint256(drop)]);
        }
    }

    function _rank(uint256[] memory points, uint256[] memory minv) internal pure returns (uint256[] memory rank) {
        uint256 n = points.length;
        uint256 c;
        for (uint256 i = 0; i < n; i++) {
            if (points[i] > 0) c++;
        }
        rank = new uint256[](c);
        uint256 k;
        for (uint256 i = 0; i < n; i++) {
            if (points[i] > 0) rank[k++] = i;
        }
        for (uint256 a = 1; a < c; a++) {
            uint256 cur = rank[a];
            uint256 b = a;
            while (b > 0 && _before(cur, rank[b - 1], points, minv)) {
                rank[b] = rank[b - 1];
                b--;
            }
            rank[b] = cur;
        }
    }

    function _before(uint256 x, uint256 y, uint256[] memory points, uint256[] memory minv) private pure returns (bool) {
        if (points[x] != points[y]) return points[x] > points[y];
        if (minv[x] != minv[y]) return minv[x] < minv[y];
        return x < y;
    }

    function _selectTop(uint256[] memory rank, bool[] memory excluded, uint256 nTop)
        private
        pure
        returns (uint256[] memory sel)
    {
        uint256 avail;
        for (uint256 i = 0; i < rank.length; i++) {
            if (!excluded[i]) avail++;
        }
        uint256 take = avail < nTop ? avail : nTop;
        sel = new uint256[](take);
        uint256 k;
        for (uint256 i = 0; i < rank.length && k < take; i++) {
            if (!excluded[i]) sel[k++] = rank[i];
        }
    }

    function _allocateCapped(uint256 pool, uint256[] memory sel, uint256[] memory points, uint256[] memory full)
        private
        pure
        returns (uint256[] memory a)
    {
        uint256 m = sel.length;
        a = new uint256[](m);
        bool[] memory capped = new bool[](m);
        uint256 remaining = pool;
        for (uint256 pass = 0; pass < m; pass++) {
            uint256 sumPts;
            for (uint256 i = 0; i < m; i++) {
                if (!capped[i]) sumPts += points[sel[i]];
            }
            if (sumPts == 0) break;
            bool newCap = false;
            for (uint256 i = 0; i < m; i++) {
                if (capped[i]) continue;
                uint256 want = (remaining * points[sel[i]]) / sumPts;
                uint256 cap = full[sel[i]];
                if (want >= cap) {
                    a[i] = cap;
                    capped[i] = true;
                    remaining -= cap;
                    newCap = true;
                }
            }
            if (newCap) continue;
            for (uint256 i = 0; i < m; i++) {
                if (!capped[i]) a[i] = (remaining * points[sel[i]]) / sumPts;
            }
            break;
        }
    }

    function _weakestBelowMin(uint256[] memory sel, uint256[] memory a, uint256[] memory minv)
        private
        pure
        returns (int256 drop)
    {
        drop = -1;
        for (uint256 s = 0; s < sel.length; s++) {
            if (a[s] < minv[sel[s]]) drop = int256(s);
        }
    }

    function _exclude(uint256[] memory rank, bool[] memory excluded, uint256 proj) private pure {
        for (uint256 c = 0; c < rank.length; c++) {
            if (rank[c] == proj) {
                excluded[c] = true;
                return;
            }
        }
    }
}
