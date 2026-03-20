// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IVotingModule} from "../interfaces/IVotingModule.sol";
import {IVotingPowerStrategy} from "../interfaces/IVotingPowerStrategy.sol";
import {IRecipientRegistry} from "../interfaces/IRecipientRegistry.sol";
import {IDistributionModule} from "../interfaces/IDistributionModule.sol";
import {ICycleModule} from "../interfaces/ICycleModule.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title AbstractVotingModule
/// @author BreadKit
/// @notice Abstract base contract for voting modules with signature-based voting
/// @dev Provides core voting functionality including vote processing, signature verification,
///      and integration with voting power strategies, cycle management, and recipient registries.
///      Inheriting contracts must implement specific voting logic.
abstract contract AbstractVotingModule is IVotingModule, Initializable, EIP712Upgradeable, OwnableUpgradeable {
    using ECDSA for bytes32;

    // ============ Constants ============

    /// @notice EIP-712 domain name for signature verification
    string private constant EIP712_NAME = "CrowdstakingVoting";

    /// @notice EIP-712 domain version for signature verification
    string private constant EIP712_VERSION = "1";

    /// @notice Precision factor for calculations to avoid rounding errors
    uint256 public constant PRECISION = 1e18;

    /// @notice Maximum number of votes that can be cast in a single batch transaction
    uint256 public constant MAX_BATCH_SIZE = 200;

    /// @notice EIP-712 typehash for vote signature verification
    bytes32 public constant VOTE_TYPEHASH = keccak256("Vote(address voter,bytes32 pointsHash,uint256 nonce)");

    // ============ EIP-7201 Namespaced Storage ============

    /// @custom:storage-location erc7201:crowdstake.storage.AbstractVotingModule
    struct AbstractVotingModuleStorage {
        /// @notice Array of voting power calculation strategies
        IVotingPowerStrategy[] votingPowerStrategies;
        /// @notice Tracks used nonces for each voter to prevent replay attacks
        mapping(address => mapping(uint256 => bool)) usedNonces;
        /// @notice Tracks the block number when an account last voted
        mapping(address => uint256) accountLastVotedBlock;
        /// @notice Total voting power used in each cycle
        mapping(uint256 => uint256) totalCycleVotingPower;
        /// @notice Reference to the distribution module for yield allocation
        IDistributionModule distributionModule;
        /// @notice Reference to the recipient registry for validation
        IRecipientRegistry recipientRegistry;
        /// @notice Reference to the cycle module for cycle management
        ICycleModule cycleModule;
    }

    // keccak256(abi.encode(uint256(keccak256("crowdstake.storage.AbstractVotingModule")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ABSTRACT_VOTING_MODULE_STORAGE =
        0x80af4feaa640a1d15105fb4b22fd2349e615c43c355f33de80a45defe9253b00;

    function _getAbstractVotingModuleStorage() internal pure returns (AbstractVotingModuleStorage storage $) {
        assembly {
            $.slot := ABSTRACT_VOTING_MODULE_STORAGE
        }
    }

    // ============ Public Getters ============

    function votingPowerStrategies(uint256 index) public view returns (IVotingPowerStrategy) {
        return _getAbstractVotingModuleStorage().votingPowerStrategies[index];
    }

    function usedNonces(address voter, uint256 nonce) public view returns (bool) {
        return _getAbstractVotingModuleStorage().usedNonces[voter][nonce];
    }

    function accountLastVotedBlock(address voter) public view returns (uint256) {
        return _getAbstractVotingModuleStorage().accountLastVotedBlock[voter];
    }

    function totalCycleVotingPower(uint256 cycle) public view returns (uint256) {
        return _getAbstractVotingModuleStorage().totalCycleVotingPower[cycle];
    }

    function distributionModule() public view returns (IDistributionModule) {
        return _getAbstractVotingModuleStorage().distributionModule;
    }

    function recipientRegistry() public view returns (IRecipientRegistry) {
        return _getAbstractVotingModuleStorage().recipientRegistry;
    }

    function cycleModule() public view returns (ICycleModule) {
        return _getAbstractVotingModuleStorage().cycleModule;
    }

    // ============ Initialization ============

    /// @notice Initializes the abstract voting module
    // solhint-disable-next-line func-name-mixedcase
    function __AbstractVotingModule_init(
        IVotingPowerStrategy[] calldata _strategies,
        address _distributionModule,
        address _recipientRegistry,
        address _cycleModule
    ) internal onlyInitializing {
        if (_strategies.length == 0) revert NoStrategiesProvided();

        __EIP712_init(EIP712_NAME, EIP712_VERSION);
        __Ownable_init(msg.sender);

        AbstractVotingModuleStorage storage $ = _getAbstractVotingModuleStorage();
        $.distributionModule = IDistributionModule(_distributionModule);
        $.recipientRegistry = IRecipientRegistry(_recipientRegistry);
        $.cycleModule = ICycleModule(_cycleModule);

        for (uint256 i = 0; i < _strategies.length; i++) {
            if (address(_strategies[i]) == address(0)) revert InvalidStrategy();
            $.votingPowerStrategies.push(_strategies[i]);
        }

        emit VotingModuleInitialized(_strategies);
        emit DistributionModuleSet(_distributionModule);
        emit RecipientRegistrySet(_recipientRegistry);
        emit CycleModuleSet(_cycleModule);
    }

    // ============ External Functions ============

    /// @notice Gets the voting power of an account from the voting strategies
    function getVotingPower(address account) external view virtual returns (uint256) {
        return _calculateTotalVotingPower(account);
    }

    /// @notice Returns the EIP-712 domain separator for signature verification
    function DOMAIN_SEPARATOR() external view virtual returns (bytes32) {
        return _domainSeparatorV4();
    }

    /// @notice Checks if a nonce has been used for a voter
    function isNonceUsed(address voter, uint256 nonce) public view virtual returns (bool) {
        return _getAbstractVotingModuleStorage().usedNonces[voter][nonce];
    }

    /// @notice Gets all configured voting power strategies
    function getVotingPowerStrategies() external view virtual returns (IVotingPowerStrategy[] memory) {
        return _getAbstractVotingModuleStorage().votingPowerStrategies;
    }

    /// @notice Gets the expected number of vote points based on active recipients
    function getExpectedPointsLength() external view returns (uint256) {
        AbstractVotingModuleStorage storage $ = _getAbstractVotingModuleStorage();
        if (address($.recipientRegistry) == address(0)) revert RecipientRegistryNotSet();
        return $.recipientRegistry.getRecipientCount();
    }

    // ============ Getter Functions ============

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getMaxBatchSize() external pure returns (uint256) {
        return MAX_BATCH_SIZE;
    }

    function getVoteTypehash() external pure returns (bytes32) {
        return VOTE_TYPEHASH;
    }

    // ============ View Functions ============

    /// @notice Checks if a voter has already voted in the current cycle
    function hasVotedInCurrentCycle(address voter) public view returns (bool) {
        AbstractVotingModuleStorage storage $ = _getAbstractVotingModuleStorage();
        uint256 cycleStartBlock = $.cycleModule.lastCycleStartBlock();
        return $.accountLastVotedBlock[voter] >= cycleStartBlock;
    }

    /// @notice Gets the total voting power used in a specific cycle
    function getTotalCycleVotingPower(uint256 cycle) external view returns (uint256) {
        return _getAbstractVotingModuleStorage().totalCycleVotingPower[cycle];
    }

    // ============ Internal Functions ============

    /// @notice Processes a single vote with signature verification
    function _castSingleVote(address voter, uint256[] calldata points, uint256 nonce, bytes calldata signature)
        internal
    {
        AbstractVotingModuleStorage storage $ = _getAbstractVotingModuleStorage();

        // Check nonce hasn't been used
        if (isNonceUsed(voter, nonce)) revert NonceAlreadyUsed();

        // Validate points early to fail fast before expensive signature recovery
        if (!_validateVotePoints(points)) revert InvalidPointsDistribution();

        // Verify signature
        if (!validateSignature(voter, points, nonce, signature)) revert InvalidSignature();

        // Mark nonce as used after validation
        $.usedNonces[voter][nonce] = true;

        // Get voting power from the voting strategy
        uint256 votingPower = _calculateTotalVotingPower(voter);

        // Process vote
        _processVote(voter, points, votingPower);

        emit VoteCast(voter, points, votingPower, nonce, signature);
    }

    /// @notice Gets voting power directly from the voting strategies
    function _calculateTotalVotingPower(address account) internal view returns (uint256) {
        AbstractVotingModuleStorage storage $ = _getAbstractVotingModuleStorage();
        uint256 totalPower = 0;

        for (uint256 i = 0; i < $.votingPowerStrategies.length; i++) {
            totalPower += $.votingPowerStrategies[i].getCurrentVotingPower(account);
        }

        return totalPower;
    }

    /// @notice Processes and records a vote
    function _processVote(address voter, uint256[] calldata points, uint256 votingPower) internal virtual;

    /// @notice Validates vote points distribution
    function _validateVotePoints(uint256[] calldata points) internal view virtual returns (bool);

    /// @notice Validates a vote signature
    function validateSignature(address voter, uint256[] calldata points, uint256 nonce, bytes calldata signature)
        public
        view
        virtual
        override
        returns (bool)
    {
        bytes32 typeHash = VOTE_TYPEHASH;
        bytes32 structHash;
        assembly {
            let ptr := mload(0x40)

            // Copy points calldata to memory and hash it
            let pointsSize := mul(points.length, 0x20)
            calldatacopy(ptr, points.offset, pointsSize)
            let pointsHash := keccak256(ptr, pointsSize)

            // Encode and hash: (VOTE_TYPEHASH, voter, pointsHash, nonce) = 4 x 32 bytes
            mstore(ptr, typeHash)
            mstore(add(ptr, 0x20), voter)
            mstore(add(ptr, 0x40), pointsHash)
            mstore(add(ptr, 0x60), nonce)
            structHash := keccak256(ptr, 0x80)
        }
        bytes32 hash = _hashTypedDataV4(structHash);
        address signer = hash.recover(signature);
        return signer == voter;
    }
}
