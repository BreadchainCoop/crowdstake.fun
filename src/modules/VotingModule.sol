// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../interfaces/IVotingModule.sol";
import "../interfaces/IVotingPowerStrategy.sol";

/// @title VotingModule
/// @notice Handles voting on yield distribution with signature-based voting and multiple strategies
/// @dev Implements IVotingModule with EIP-712 signature verification, point-based voting,
///      and support for multiple voting power strategies (issues #2, #22)
/// @author BreadKit Protocol
contract VotingModule is IVotingModule, OwnableUpgradeable, EIP712Upgradeable {
    using ECDSA for bytes32;

    /// @notice EIP-712 typehash for vote signatures
    bytes32 public constant VOTE_TYPEHASH = keccak256("Vote(address voter,uint256[] points,uint256 nonce)");

    /// @notice Maximum points a voter can allocate across all recipients
    uint256 public maxPoints;

    /// @notice Number of recipients (projects) in the current cycle
    uint256 public recipientCount;

    /// @notice Array of voting power strategies
    IVotingPowerStrategy[] public votingPowerStrategies;

    /// @notice Current voting distribution totals per recipient
    uint256[] public currentDistribution;

    /// @notice Total votes cast in the current cycle
    uint256 public totalVotesCast;

    /// @notice Voter's current point distribution per cycle
    /// @dev voter => points[]
    mapping(address => uint256[]) public voterDistributions;

    /// @notice Whether a voter has voted in the current cycle
    mapping(address => bool) public hasVotedInCycle;

    /// @notice Nonce tracking per voter for replay protection
    mapping(address => mapping(uint256 => bool)) public usedNonces;

    // Events
    /// @notice Emitted when a vote is cast
    event VoteCast(address indexed voter, uint256[] points, uint256 votingPower);

    /// @notice Emitted when a vote is recast (updated)
    event VoteRecast(address indexed voter, uint256[] oldPoints, uint256[] newPoints);

    /// @notice Emitted when voting power strategies are updated
    event VotingPowerStrategiesUpdated(uint256 strategyCount);

    /// @notice Emitted when max points is updated
    event MaxPointsUpdated(uint256 oldMax, uint256 newMax);

    /// @notice Emitted when recipient count is updated
    event RecipientCountUpdated(uint256 oldCount, uint256 newCount);

    /// @notice Emitted when the cycle is reset
    event CycleReset(uint256 totalVotes);

    // Errors
    error InvalidPointsLength();
    error PointsExceedMax();
    error ZeroVotingPower();
    error InvalidSignature();
    error NonceAlreadyUsed();
    error InvalidMaxPoints();
    error NoStrategies();
    error ZeroPoints();

    /// @notice Initialize the voting module
    /// @param admin Admin address
    /// @param _maxPoints Maximum points allocatable per vote
    /// @param _recipientCount Number of recipients
    /// @param _strategies Array of voting power strategy addresses
    function initialize(
        address admin,
        uint256 _maxPoints,
        uint256 _recipientCount,
        IVotingPowerStrategy[] memory _strategies
    ) public initializer {
        __Ownable_init(admin);
        __EIP712_init("BreadKitVoting", "1");

        if (_maxPoints == 0) revert InvalidMaxPoints();
        if (_strategies.length == 0) revert NoStrategies();

        maxPoints = _maxPoints;
        recipientCount = _recipientCount;
        currentDistribution = new uint256[](_recipientCount);

        for (uint256 i = 0; i < _strategies.length; i++) {
            votingPowerStrategies.push(_strategies[i]);
        }
    }

    /// @inheritdoc IVotingModule
    function vote(uint256[] calldata points) external override {
        _vote(msg.sender, points);
    }

    /// @inheritdoc IVotingModule
    function castVote(uint256[] calldata points) external override {
        _vote(msg.sender, points);
    }

    /// @inheritdoc IVotingModule
    function voteWithMultipliers(uint256[] calldata points, uint256[] calldata multiplierIndices) external override {
        // Multipliers are applied through the voting power strategies
        // For now, this delegates to the standard vote
        // Future: use multiplierIndices to select specific strategies
        _vote(msg.sender, points);
    }

    /// @inheritdoc IVotingModule
    function castVoteWithMultipliers(uint256[] calldata points, uint256[] calldata multiplierIndices)
        external
        override
    {
        _vote(msg.sender, points);
    }

    /// @inheritdoc IVotingModule
    function castVoteWithSignature(address voter, uint256[] calldata points, uint256 nonce, bytes calldata signature)
        external
        override
    {
        _verifySignature(voter, points, nonce, signature);
        _vote(voter, points);
    }

    /// @inheritdoc IVotingModule
    function castBatchVotesWithSignature(
        address[] calldata voters,
        uint256[][] calldata points,
        uint256[] calldata nonces,
        bytes[] calldata signatures
    ) external override {
        require(
            voters.length == points.length && voters.length == nonces.length && voters.length == signatures.length,
            "Array length mismatch"
        );

        for (uint256 i = 0; i < voters.length; i++) {
            _verifySignature(voters[i], points[i], nonces[i], signatures[i]);
            _vote(voters[i], points[i]);
        }
    }

    /// @inheritdoc IVotingModule
    function delegate(address delegatee) external override {
        // Delegation is handled at the token level (ERC20Votes)
        // This is a no-op placeholder for interface compliance
    }

    /// @inheritdoc IVotingModule
    function getVotingPower(address account) external view override returns (uint256) {
        return _getTotalVotingPower(account);
    }

    /// @inheritdoc IVotingModule
    function getCurrentVotingDistribution() external view override returns (uint256[] memory) {
        return currentDistribution;
    }

    /// @inheritdoc IVotingModule
    function setMaxPoints(uint256 _maxPoints) external override onlyOwner {
        if (_maxPoints == 0) revert InvalidMaxPoints();
        uint256 oldMax = maxPoints;
        maxPoints = _maxPoints;
        emit MaxPointsUpdated(oldMax, _maxPoints);
    }

    /// @inheritdoc IVotingModule
    function validateVotePoints(uint256[] calldata points) external view override returns (bool) {
        return _validatePoints(points);
    }

    /// @inheritdoc IVotingModule
    function validateSignature(address voter, uint256[] calldata points, uint256 nonce, bytes calldata signature)
        external
        view
        override
        returns (bool)
    {
        bytes32 structHash = keccak256(abi.encode(VOTE_TYPEHASH, voter, keccak256(abi.encodePacked(points)), nonce));
        bytes32 hash = _hashTypedDataV4(structHash);
        address signer = hash.recover(signature);
        return signer == voter && !usedNonces[voter][nonce];
    }

    /// @inheritdoc IVotingModule
    function DOMAIN_SEPARATOR() external view override returns (bytes32) {
        return _domainSeparatorV4();
    }

    /// @inheritdoc IVotingModule
    function isNonceUsed(address voter, uint256 nonce) external view override returns (bool) {
        return usedNonces[voter][nonce];
    }

    /// @inheritdoc IVotingModule
    function getVotingPowerStrategies() external view override returns (IVotingPowerStrategy[] memory) {
        return votingPowerStrategies;
    }

    /// @notice Update the number of recipients
    /// @param _recipientCount New recipient count
    function setRecipientCount(uint256 _recipientCount) external onlyOwner {
        uint256 oldCount = recipientCount;
        recipientCount = _recipientCount;
        currentDistribution = new uint256[](_recipientCount);
        emit RecipientCountUpdated(oldCount, _recipientCount);
    }

    /// @notice Set voting power strategies
    /// @param _strategies New array of strategy addresses
    function setVotingPowerStrategies(IVotingPowerStrategy[] memory _strategies) external onlyOwner {
        if (_strategies.length == 0) revert NoStrategies();
        delete votingPowerStrategies;
        for (uint256 i = 0; i < _strategies.length; i++) {
            votingPowerStrategies.push(_strategies[i]);
        }
        emit VotingPowerStrategiesUpdated(_strategies.length);
    }

    /// @notice Cast a vote with additional bytes data for downstream implementations (issue #62)
    /// @param points Array of points allocated to each project
    /// @param additionalData Arbitrary data for downstream processing
    function voteWithParams(uint256[] calldata points, bytes calldata additionalData) external {
        _processAdditionalData(msg.sender, additionalData);
        _vote(msg.sender, points);
    }

    /// @notice Cast a vote with signature and additional bytes data (issue #62)
    /// @param voter The voter address
    /// @param points Array of points allocated to each project
    /// @param nonce Replay protection nonce
    /// @param signature EIP-712 signature
    /// @param additionalData Arbitrary data for downstream processing
    function castVoteWithSignatureAndParams(
        address voter,
        uint256[] calldata points,
        uint256 nonce,
        bytes calldata signature,
        bytes calldata additionalData
    ) external {
        _verifySignature(voter, points, nonce, signature);
        _processAdditionalData(voter, additionalData);
        _vote(voter, points);
    }

    /// @notice Internal hook for processing additional vote data
    /// @dev Override in derived contracts to handle protocol-specific data
    /// @param voter The voter
    /// @param additionalData The additional data
    function _processAdditionalData(address voter, bytes calldata additionalData) internal virtual {
        // Default: no-op. Override in derived contracts for custom behavior.
    }

    /// @notice Reset the cycle (clear all votes)
    /// @dev Called by distribution module at end of cycle
    function resetCycle() external onlyOwner {
        uint256 votes = totalVotesCast;
        totalVotesCast = 0;
        currentDistribution = new uint256[](recipientCount);
        emit CycleReset(votes);
    }

    // ============ Internal Functions ============

    function _vote(address voter, uint256[] calldata points) internal {
        if (!_validatePoints(points)) revert InvalidPointsLength();

        uint256 votingPower = _getTotalVotingPower(voter);
        if (votingPower == 0) revert ZeroVotingPower();

        // Check total points > 0
        uint256 totalPoints = 0;
        for (uint256 i = 0; i < points.length; i++) {
            totalPoints += points[i];
        }
        if (totalPoints == 0) revert ZeroPoints();
        if (totalPoints > maxPoints) revert PointsExceedMax();

        // If recasting, subtract old distribution
        if (hasVotedInCycle[voter]) {
            uint256[] memory oldPoints = voterDistributions[voter];
            uint256 oldTotal = 0;
            for (uint256 i = 0; i < oldPoints.length; i++) {
                oldTotal += oldPoints[i];
            }
            // Remove old weighted votes
            for (uint256 i = 0; i < oldPoints.length; i++) {
                currentDistribution[i] -= (oldPoints[i] * votingPower) / oldTotal;
            }
            totalVotesCast--;

            emit VoteRecast(voter, oldPoints, points);
        }

        // Apply new weighted votes
        for (uint256 i = 0; i < points.length; i++) {
            currentDistribution[i] += (points[i] * votingPower) / totalPoints;
        }

        // Store voter's distribution
        voterDistributions[voter] = points;
        hasVotedInCycle[voter] = true;
        totalVotesCast++;

        emit VoteCast(voter, points, votingPower);
    }

    function _verifySignature(address voter, uint256[] calldata points, uint256 nonce, bytes calldata signature)
        internal
    {
        if (usedNonces[voter][nonce]) revert NonceAlreadyUsed();

        bytes32 structHash = keccak256(abi.encode(VOTE_TYPEHASH, voter, keccak256(abi.encodePacked(points)), nonce));
        bytes32 hash = _hashTypedDataV4(structHash);
        address signer = hash.recover(signature);

        if (signer != voter) revert InvalidSignature();

        usedNonces[voter][nonce] = true;
    }

    function _validatePoints(uint256[] calldata points) internal view returns (bool) {
        return points.length == recipientCount;
    }

    function _getTotalVotingPower(address account) internal view returns (uint256 totalPower) {
        for (uint256 i = 0; i < votingPowerStrategies.length; i++) {
            totalPower += votingPowerStrategies[i].getCurrentVotingPower(account);
        }
    }
}
