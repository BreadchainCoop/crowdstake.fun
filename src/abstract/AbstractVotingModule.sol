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
    /// @dev Used in vote weight calculations to maintain precision
    uint256 public constant PRECISION = 1e18;

    /// @notice Maximum number of votes that can be cast in a single batch transaction
    /// @dev Prevents gas limit issues and potential DOS attacks
    uint256 public constant MAX_BATCH_SIZE = 200;

    /// @notice EIP-712 typehash for vote signature verification
    /// @dev Keccak256 hash of the Vote type structure for EIP-712 signing
    /// @dev keccak256("Vote(address voter,bytes32 pointsHash,uint256 nonce)") = 0x75bc59ee506a0b0e949fb3a7df4ed9c67afe07055fed85f523f130ba4f0bfaea
    bytes32 public constant VOTE_TYPEHASH = keccak256("Vote(address voter,bytes32 pointsHash,uint256 nonce)");

    // ============ EIP-7201 Namespaced Storage ============

    /// @custom:storage-location erc7201:crowdstake.storage.AbstractVotingModule
    struct AbstractVotingModuleStorage {
        /// @notice Array of voting power calculation strategies
        /// @dev Multiple strategies can be used to calculate combined voting power
        IVotingPowerStrategy[] votingPowerStrategies;
        /// @notice Tracks used nonces for each voter to prevent replay attacks
        /// @dev voter => nonce => used
        mapping(address => mapping(uint256 => bool)) usedNonces;
        /// @notice Tracks the block number when an account last voted
        /// @dev voter => block number
        mapping(address => uint256) accountLastVotedBlock;
        /// @notice Total voting power used in each cycle
        /// @dev cycle => total voting power
        mapping(uint256 => uint256) totalCycleVotingPower;
        /// @notice Reference to the distribution module for yield allocation
        /// @dev Handles the actual distribution of rewards based on voting results
        IDistributionModule distributionModule;
        /// @notice Reference to the recipient registry for validation
        /// @dev Maintains the list of valid recipients that can receive votes
        IRecipientRegistry recipientRegistry;
        /// @notice Reference to the cycle module for cycle management
        /// @dev Manages voting cycles and transitions between periods
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

    /// @notice Returns the voting power strategy at the given index
    /// @param index The index in the strategies array
    function votingPowerStrategies(uint256 index) public view returns (IVotingPowerStrategy) {
        return _getAbstractVotingModuleStorage().votingPowerStrategies[index];
    }

    /// @notice Returns whether a nonce has been used by a voter
    /// @param voter The voter address
    /// @param nonce The nonce to check
    function usedNonces(address voter, uint256 nonce) public view returns (bool) {
        return _getAbstractVotingModuleStorage().usedNonces[voter][nonce];
    }

    /// @notice Returns the block number when the account last voted
    /// @param voter The voter address
    function accountLastVotedBlock(address voter) public view returns (uint256) {
        return _getAbstractVotingModuleStorage().accountLastVotedBlock[voter];
    }

    /// @notice Returns the total voting power used in a given cycle
    /// @param cycle The cycle number
    function totalCycleVotingPower(uint256 cycle) public view returns (uint256) {
        return _getAbstractVotingModuleStorage().totalCycleVotingPower[cycle];
    }

    /// @notice Returns the distribution module reference
    /// @dev Handles the actual distribution of rewards based on voting results
    function distributionModule() public view returns (IDistributionModule) {
        return _getAbstractVotingModuleStorage().distributionModule;
    }

    /// @notice Returns the recipient registry reference
    /// @dev Maintains the list of valid recipients that can receive votes
    function recipientRegistry() public view returns (IRecipientRegistry) {
        return _getAbstractVotingModuleStorage().recipientRegistry;
    }

    /// @notice Returns the cycle module reference
    /// @dev Manages voting cycles and transitions between periods
    function cycleModule() public view returns (ICycleModule) {
        return _getAbstractVotingModuleStorage().cycleModule;
    }

    // ============ Initialization ============

    /// @notice Initializes the abstract voting module
    /// @dev Sets up EIP-712 domain, ownership, and core parameters.
    ///      Must be called by inheriting contract's initializer.
    /// @param _strategies Array of voting power strategy contracts
    /// @param _distributionModule Address of the distribution module
    /// @param _recipientRegistry Address of the recipient registry
    /// @param _cycleModule Address of the cycle module
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

        if (_distributionModule == address(0)) revert ZeroAddress();
        if (_recipientRegistry == address(0)) revert ZeroAddress();
        if (_cycleModule == address(0)) revert ZeroAddress();

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
    /// @dev Queries the configured voting strategies for the account's power
    /// @param account The address to check voting power for
    /// @return The total voting power from all strategies
    function getVotingPower(address account) external view virtual returns (uint256) {
        return _calculateTotalVotingPower(account);
    }

    /// @notice Returns the EIP-712 domain separator for signature verification
    /// @dev Used by external contracts to verify signatures
    /// @return The domain separator hash
    function DOMAIN_SEPARATOR() external view virtual returns (bytes32) {
        return _domainSeparatorV4();
    }

    /// @notice Checks if a nonce has been used for a voter
    /// @dev Used to prevent replay attacks
    /// @param voter The voter's address
    /// @param nonce The nonce to check
    /// @return True if the nonce has been used, false otherwise
    function isNonceUsed(address voter, uint256 nonce) public view virtual returns (bool) {
        return _getAbstractVotingModuleStorage().usedNonces[voter][nonce];
    }

    /// @notice Gets all configured voting power strategies
    /// @dev Returns the array of strategy contracts
    /// @return Array of voting power strategy contracts
    function getVotingPowerStrategies() external view virtual returns (IVotingPowerStrategy[] memory) {
        return _getAbstractVotingModuleStorage().votingPowerStrategies;
    }

    /// @notice Gets the expected number of vote points based on active recipients
    /// @dev Used to validate vote arrays have correct length
    /// @return The number of active recipients
    function getExpectedPointsLength() external view returns (uint256) {
        AbstractVotingModuleStorage storage $ = _getAbstractVotingModuleStorage();
        if (address($.recipientRegistry) == address(0)) revert RecipientRegistryNotSet();
        return $.recipientRegistry.getRecipientCount();
    }

    // ============ Getter Functions ============

    /// @notice Gets the precision factor used in calculations
    /// @dev Returns the constant PRECISION value for external contracts
    /// @return The precision factor (1e18)
    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    /// @notice Gets the maximum batch size for batch voting
    /// @dev Returns the constant MAX_BATCH_SIZE value
    /// @return The maximum number of votes in a batch (200)
    function getMaxBatchSize() external pure returns (uint256) {
        return MAX_BATCH_SIZE;
    }

    /// @notice Gets the EIP-712 typehash for vote signatures
    /// @dev Returns the constant VOTE_TYPEHASH for external verification
    /// @return The keccak256 hash of the Vote type structure
    function getVoteTypehash() external pure returns (bytes32) {
        return VOTE_TYPEHASH;
    }

    // ============ View Functions ============

    /// @notice Checks if a voter has already voted in the current cycle
    /// @dev Used to determine if a vote would be a recast
    /// @param voter The address to check
    /// @return True if the voter has voted in the current cycle
    function hasVotedInCurrentCycle(address voter) public view returns (bool) {
        AbstractVotingModuleStorage storage $ = _getAbstractVotingModuleStorage();
        uint256 cycleStartBlock = $.cycleModule.lastCycleStartBlock();
        return $.accountLastVotedBlock[voter] >= cycleStartBlock;
    }

    /// @notice Gets the total voting power used in a specific cycle
    /// @dev Useful for calculating voting participation and weight
    /// @param cycle The cycle number to check
    /// @return The total voting power used in that cycle
    function getTotalCycleVotingPower(uint256 cycle) external view returns (uint256) {
        return _getAbstractVotingModuleStorage().totalCycleVotingPower[cycle];
    }

    // ============ Internal Functions ============

    /// @notice Processes a single vote with signature verification
    /// @dev Validates signature, nonce, and voting power before processing
    /// @param voter Address of the voter
    /// @param points Array of points to allocate to each recipient
    /// @param nonce Unique nonce for replay protection
    /// @param signature EIP-712 signature from the voter
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
    /// @dev Queries each configured voting strategy for the account's power
    /// @param account Address to get voting power for
    /// @return totalPower Total voting power from all strategies
    function _calculateTotalVotingPower(address account) internal view returns (uint256) {
        AbstractVotingModuleStorage storage $ = _getAbstractVotingModuleStorage();
        uint256 totalPower = 0;

        for (uint256 i = 0; i < $.votingPowerStrategies.length; i++) {
            totalPower += $.votingPowerStrategies[i].getCurrentVotingPower(account);
        }

        return totalPower;
    }

    /// @notice Processes and records a vote
    /// @dev Updates project distributions and cycle voting power. Handles vote recasting.
    /// @param voter Address of the voter
    /// @param points Array of points allocated to each recipient
    /// @param votingPower Total voting power of the voter
    function _processVote(address voter, uint256[] calldata points, uint256 votingPower) internal virtual;

    /// @notice Validates vote points distribution
    /// @dev Checks if points array is valid according to module rules
    /// @param points Array of points to validate
    /// @return True if points are valid, false otherwise
    function _validateVotePoints(uint256[] calldata points) internal view virtual returns (bool);

    /// @notice Validates a vote signature
    /// @dev Verifies that a signature is valid for the given vote parameters
    /// @param voter The address of the voter
    /// @param points Array of points allocated to each project
    /// @param nonce The nonce for replay protection
    /// @param signature The signature to validate
    /// @return True if signature is valid, false otherwise
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
