// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AbstractVotingModule} from "../abstract/AbstractVotingModule.sol";
import {IVotingPowerStrategy} from "../interfaces/IVotingPowerStrategy.sol";

/// @title CovaPointsVotingModule
/// @author COVA Artist Cooperative
/// @notice Crowdstake {AbstractVotingModule} subclass implementing the front
///         end's single-round 100-point ballot, one-person-one-vote.
/// @dev Reuses the protocol's voting machinery (cycle module + recipient
///      registry derived from the distribution manager, voting-power
///      strategies, recast handling). Differences from `BasisPointsVotingModule`:
///        * accumulates *raw* points per project (projects are ranked by total
///          points received, per the spec), not power-weighted basis points;
///        * a ballot is gated by voting power > 0, i.e. cooperative membership
///          via {OnePersonOneVotePower} — every member counts equally;
///        * adds a direct `castVote(points)` entrypoint (the front end clicks,
///          it does not sign EIP-712); the inherited signature path still works.
contract CovaPointsVotingModule is AbstractVotingModule {
    uint256 public constant TOTAL_POINTS = 100;

    /// @custom:storage-location erc7201:crowdstake.storage.CovaPointsVotingModule
    struct CovaStore {
        mapping(uint256 => uint256[]) projectPoints; // cycle => points per recipient idx
        mapping(uint256 => mapping(address => uint256[])) voterPoints; // cycle => voter => points
        mapping(uint256 => mapping(address => bool)) voted; // cycle => voter => voted
        mapping(uint256 => uint256) voterCount; // cycle => distinct voters
    }

    // keccak256(abi.encode(uint256(keccak256("crowdstake.storage.CovaPointsVotingModule")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant COVA_STORE = 0x6363fef9d48a1db87563ec398e2bf318e1f5cd0d53e262d3de4c18440b2aea00;

    function _cs() private pure returns (CovaStore storage $) {
        assembly {
            $.slot := COVA_STORE
        }
    }

    error ExceedsTotalPoints();
    error NotAMember();

    event BallotRecorded(address indexed voter, uint256 indexed cycle, uint256[] points);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(IVotingPowerStrategy[] calldata _strategies, address _distributionModule, address _owner)
        external
        initializer
    {
        __AbstractVotingModule_init(_strategies, _distributionModule, _owner);
    }

    /// @notice Direct one-person-one-vote ballot (front-end path, no signature).
    /// @param points Points per project, index-aligned with the project
    ///        registry; total in [1, 100].
    function castVote(uint256[] calldata points) external {
        if (!_validateVotePoints(points)) revert InvalidPointsDistribution();
        uint256 vp = _calculateTotalVotingPower(msg.sender);
        _processVote(msg.sender, points, vp);
        emit VoteCast(msg.sender, points, vp, 0, "");
    }

    /// @notice Signature ballot (inherited crowdstake gas-abstracted path).
    function castVoteWithSignature(address voter, uint256[] calldata points, uint256 nonce, bytes calldata signature)
        external
    {
        _castSingleVote(voter, points, nonce, signature);
    }

    function getCurrentVotingDistribution() external view returns (uint256[] memory) {
        return _cs().projectPoints[cycleModule().getCurrentCycle()];
    }

    function getProjectPoints(uint256 cycle) external view returns (uint256[] memory) {
        return _cs().projectPoints[cycle];
    }

    function getCycleVoterCount(uint256 cycle) external view returns (uint256) {
        return _cs().voterCount[cycle];
    }

    function hasVotedInCycle(uint256 cycle, address voter) external view returns (bool) {
        return _cs().voted[cycle][voter];
    }

    /// @inheritdoc AbstractVotingModule
    /// @dev Raw-points accumulation, one-person-one-vote: power only gates
    ///      eligibility, it does not scale points. Recast fully reverses the
    ///      member's previous ballot in the cycle.
    function _processVote(address voter, uint256[] calldata points, uint256 votingPower) internal override {
        if (votingPower == 0) revert NotAMember();
        AbstractVotingModuleStorage storage base = _getAbstractVotingModuleStorage();
        CovaStore storage $ = _cs();
        uint256 c = base.cycleModule.getCurrentCycle();
        uint256[] storage pp = $.projectPoints[c];

        if ($.voted[c][voter]) {
            uint256[] storage prev = $.voterPoints[c][voter];
            for (uint256 i = 0; i < prev.length; i++) {
                pp[i] -= prev[i];
            }
        } else {
            $.voted[c][voter] = true;
            $.voterCount[c]++;
            base.totalCycleVotingPower[c] += votingPower;
        }

        delete $.voterPoints[c][voter];
        for (uint256 i = 0; i < points.length; i++) {
            $.voterPoints[c][voter].push(points[i]);
            if (i >= pp.length) pp.push(points[i]);
            else pp[i] += points[i];
        }
        base.accountLastVotedBlock[voter] = block.number;
        emit BallotRecorded(voter, c, points);
    }

    /// @inheritdoc AbstractVotingModule
    function _validateVotePoints(uint256[] calldata points) internal view override returns (bool) {
        if (points.length == 0) return false;
        if (points.length != _getAbstractVotingModuleStorage().recipientRegistry.getRecipientCount()) return false;
        uint256 total;
        for (uint256 i = 0; i < points.length; i++) {
            if (points[i] > TOTAL_POINTS) revert ExceedsTotalPoints();
            total += points[i];
        }
        if (total == 0) revert ZeroVotePoints();
        if (total > TOTAL_POINTS) revert ExceedsTotalPoints();
        return true;
    }
}
