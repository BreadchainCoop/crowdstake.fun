// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BasisPointsVotingModule} from "../base/BasisPointsVotingModule.sol";
import {IVotingPowerStrategy} from "../interfaces/IVotingPowerStrategy.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @notice Minimal interface for multiplier contracts. Just a view — no state mutation needed.
interface IMultiplier {
    function getMultiplier(address voter) external view returns (uint256);
}

/// @title MultiplierVotingModule
/// @author BreadKit
/// @notice Extends BasisPointsVotingModule with multiplier support and automatic vote streak tracking.
/// @dev Voters can pass `params` (ABI-encoded `uint256[]` of multiplier indices) to
///      `castVoteWithSignatureAndParams` for boosted voting power. Multipliers are combined
///      additively. The module also tracks consecutive-cycle participation ("streaks") which
///      multiplier contracts (like VotingStreakMultiplier) can read via public storage.
contract MultiplierVotingModule is BasisPointsVotingModule {
    using ECDSA for bytes32;

    // ============ Constants ============

    bytes32 public constant VOTE_WITH_PARAMS_TYPEHASH =
        keccak256("VoteWithParams(address voter,bytes32 pointsHash,uint256 nonce,bytes32 paramsHash)");

    uint256 public constant MAX_STREAK = 10;

    // ============ Errors ============

    error InvalidMultiplierIndex();

    // ============ Events ============

    event MultiplierAdded(address indexed multiplier);
    event MultiplierRemoved(uint256 index);

    // ============ Storage ============

    IMultiplier[] public multipliers;

    /// @notice The last cycle in which a user voted
    mapping(address => uint256) public lastVotedCycle;

    /// @notice Current consecutive-cycle voting streak
    mapping(address => uint256) public votingStreak;

    /// @dev Set before _processVote so multiplier logic can read it
    bytes private _currentParams;

    // ============ Initialization ============

    function initialize(
        uint256 _maxPoints,
        IVotingPowerStrategy[] calldata _strategies,
        address _distributionModule,
        address _recipientRegistry,
        address _cycleModule,
        address[] calldata _multipliers
    ) external initializer {
        maxPoints = _maxPoints;
        __AbstractVotingModule_init(_strategies, _distributionModule, _recipientRegistry, _cycleModule);

        for (uint256 i = 0; i < _multipliers.length; i++) {
            multipliers.push(IMultiplier(_multipliers[i]));
            emit MultiplierAdded(_multipliers[i]);
        }
    }

    // ============ External Functions ============

    /// @notice Casts a vote with multipliers
    /// @param params ABI-encoded uint256[] of multiplier indices
    function castVoteWithSignatureAndParams(
        address voter,
        uint256[] calldata points,
        uint256 nonce,
        bytes calldata signature,
        bytes calldata params
    ) external {
        if (isNonceUsed(voter, nonce)) revert NonceAlreadyUsed();
        if (!_validateVotePoints(points)) revert InvalidPointsDistribution();
        if (!validateSignatureWithParams(voter, points, nonce, signature, params)) revert InvalidSignature();

        usedNonces[voter][nonce] = true;

        _currentParams = params;
        uint256 votingPower = _calculateTotalVotingPower(voter);
        _processVote(voter, points, votingPower);
        delete _currentParams;

        emit VoteCast(voter, points, votingPower, nonce, signature);
    }

    function castBatchVotesWithSignatureAndParams(
        address[] calldata voters,
        uint256[][] calldata points,
        uint256[] calldata nonces,
        bytes[] calldata signatures,
        bytes[] calldata params
    ) external {
        if (voters.length != points.length) revert ArrayLengthMismatch();
        if (voters.length != nonces.length) revert ArrayLengthMismatch();
        if (voters.length != signatures.length) revert ArrayLengthMismatch();
        if (voters.length != params.length) revert ArrayLengthMismatch();
        if (voters.length > MAX_BATCH_SIZE) revert BatchTooLarge();

        for (uint256 i = 0; i < voters.length; i++) {
            if (isNonceUsed(voters[i], nonces[i])) revert NonceAlreadyUsed();
            if (!_validateVotePoints(points[i])) revert InvalidPointsDistribution();
            if (!validateSignatureWithParams(voters[i], points[i], nonces[i], signatures[i], params[i])) {
                revert InvalidSignature();
            }

            usedNonces[voters[i]][nonces[i]] = true;

            _currentParams = params[i];
            uint256 votingPower = _calculateTotalVotingPower(voters[i]);
            _processVote(voters[i], points[i], votingPower);
            delete _currentParams;
        }

        emit BatchVotesCast(voters, nonces);
    }

    // ============ View Functions ============

    function getMultipliers() external view returns (IMultiplier[] memory) {
        return multipliers;
    }

    function validateSignatureWithParams(
        address voter,
        uint256[] calldata points,
        uint256 nonce,
        bytes calldata signature,
        bytes calldata params
    ) public view returns (bool) {
        bytes32 typeHash = VOTE_WITH_PARAMS_TYPEHASH;
        bytes32 structHash;
        assembly {
            let ptr := mload(0x40)

            let pointsSize := mul(points.length, 0x20)
            calldatacopy(ptr, points.offset, pointsSize)
            let pointsHash := keccak256(ptr, pointsSize)

            let paramsSize := params.length
            calldatacopy(ptr, params.offset, paramsSize)
            let paramsHash := keccak256(ptr, paramsSize)

            mstore(ptr, typeHash)
            mstore(add(ptr, 0x20), voter)
            mstore(add(ptr, 0x40), pointsHash)
            mstore(add(ptr, 0x60), nonce)
            mstore(add(ptr, 0x80), paramsHash)
            structHash := keccak256(ptr, 0xa0)
        }
        bytes32 hash = _hashTypedDataV4(structHash);
        address signer = hash.recover(signature);
        return signer == voter;
    }

    // ============ Admin Functions ============

    function addMultiplier(address _multiplier) external onlyOwner {
        multipliers.push(IMultiplier(_multiplier));
        emit MultiplierAdded(_multiplier);
    }

    function removeMultiplier(uint256 index) external onlyOwner {
        if (index >= multipliers.length) revert InvalidMultiplierIndex();
        multipliers[index] = multipliers[multipliers.length - 1];
        multipliers.pop();
        emit MultiplierRemoved(index);
    }

    // ============ Internal Overrides ============

    /// @notice Updates streak, applies multipliers, then delegates to BasisPointsVotingModule
    function _processVote(address voter, uint256[] calldata points, uint256 votingPower) internal override {
        // Update voting streak
        uint256 currentCycle = cycleModule.getCurrentCycle();
        _updateStreak(voter, currentCycle);

        // Apply multipliers if params provided
        uint256 effectivePower = votingPower;
        if (_currentParams.length > 0) {
            uint256[] memory indices = abi.decode(_currentParams, (uint256[]));
            uint256 totalMultiplier = PRECISION; // base 1x

            for (uint256 i = 0; i < indices.length; i++) {
                if (indices[i] >= multipliers.length) revert InvalidMultiplierIndex();
                uint256 m = multipliers[indices[i]].getMultiplier(voter);
                if (m > PRECISION) {
                    totalMultiplier += (m - PRECISION);
                }
            }

            effectivePower = (votingPower * totalMultiplier) / PRECISION;
        }

        super._processVote(voter, points, effectivePower);
    }

    // ============ Internal Functions ============

    function _updateStreak(address voter, uint256 currentCycle) internal {
        uint256 lastCycle = lastVotedCycle[voter];

        if (lastCycle == currentCycle) {
            // Recast in same cycle — no streak change
            return;
        }

        if (lastCycle == currentCycle - 1) {
            // Consecutive cycle — extend streak (capped)
            uint256 s = votingStreak[voter];
            if (s < MAX_STREAK) {
                votingStreak[voter] = s + 1;
            }
        } else {
            // Streak broken — reset to 1
            votingStreak[voter] = 1;
        }

        lastVotedCycle[voter] = currentCycle;
    }

    // ============ Gap ============

    uint256[42] private __gap;
}
