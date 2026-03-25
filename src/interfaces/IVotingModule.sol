// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IVotingPowerStrategy} from "./IVotingPowerStrategy.sol";

/// @title IVotingModule
/// @author BreadKit
/// @notice Interface for voting modules with signature-based voting
/// @dev Defines the standard interface for all voting module implementations
interface IVotingModule {
    // ============ Errors ============

    /// @notice Thrown when an invalid signature is provided
    error InvalidSignature();

    /// @notice Thrown when a nonce has already been used
    error NonceAlreadyUsed();

    /// @notice Thrown when points distribution is invalid
    error InvalidPointsDistribution();

    /// @notice Thrown when points exceed the maximum allowed
    error ExceedsMaxPoints();

    /// @notice Thrown when zero vote points are submitted
    error ZeroVotePoints();

    /// @notice Thrown when array lengths don't match in batch operations
    error ArrayLengthMismatch();

    /// @notice Thrown when batch size exceeds maximum allowed
    error BatchTooLarge();

    /// @notice Thrown when no strategies are provided during initialization
    error NoStrategiesProvided();

    /// @notice Thrown when an invalid strategy address is provided
    error InvalidStrategy();

    /// @notice Thrown when the number of recipients doesn't match expected
    error IncorrectNumberOfRecipients();

    /// @notice Thrown when recipient registry is not set
    error RecipientRegistryNotSet();

    /// @notice Thrown when a zero address is provided
    error ZeroAddress();

    // ============ Events ============

    /// @notice Emitted when a vote is cast with a signature
    /// @param voter The address of the voter
    /// @param points Array of points allocated to each recipient
    /// @param votingPower The total voting power used
    /// @param nonce The nonce used for replay protection
    /// @param signature The EIP-712 signature
    event VoteCast(address indexed voter, uint256[] points, uint256 votingPower, uint256 nonce, bytes signature);

    /// @notice Emitted when multiple votes are cast in a batch
    /// @param voters Array of voter addresses
    /// @param nonces Array of nonces used
    event BatchVotesCast(address[] voters, uint256[] nonces);

    /// @notice Emitted when the voting module is initialized
    /// @param strategies Array of voting power strategies
    event VotingModuleInitialized(IVotingPowerStrategy[] strategies);

    /// @notice Emitted when the distribution module is set
    /// @param distributionModule Address of the distribution module
    event DistributionModuleSet(address distributionModule);

    /// @notice Emitted when the recipient registry is set
    /// @param recipientRegistry Address of the recipient registry
    event RecipientRegistrySet(address recipientRegistry);

    /// @notice Emitted when the cycle module is set
    /// @param cycleModule Address of the cycle module
    event CycleModuleSet(address cycleModule);

    /// @notice Emitted when max points is updated
    /// @param maxPoints New maximum points value
    event MaxPointsSet(uint256 maxPoints);

    // ============ External Functions ============

    /// @notice Gets the voting power of an account
    /// @dev Queries the configured voting strategies for the account's power
    /// @param account The address to check voting power for
    /// @return The total voting power from all strategies
    function getVotingPower(address account) external view returns (uint256);

    /// @notice Gets the current voting distribution for the active cycle
    /// @dev Returns the array of weighted votes for each project in the current cycle
    /// @return Array of vote weights for each project
    function getCurrentVotingDistribution() external view returns (uint256[] memory);

    /// @notice Returns the EIP-712 domain separator for signature verification
    /// @dev Used by external contracts to verify signatures
    /// @return The domain separator hash
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    /// @notice Checks if a nonce has been used for a voter
    /// @dev Used to prevent replay attacks
    /// @param voter The voter's address
    /// @param nonce The nonce to check
    /// @return True if the nonce has been used, false otherwise
    function isNonceUsed(address voter, uint256 nonce) external view returns (bool);

    /// @notice Gets all configured voting power strategies
    /// @dev Returns the array of strategy contracts
    /// @return Array of voting power strategy contracts
    function getVotingPowerStrategies() external view returns (IVotingPowerStrategy[] memory);

    /// @notice Validates a vote signature
    /// @dev Verifies that a signature is valid for the given vote parameters
    /// @param voter The address of the voter
    /// @param points Array of points allocated to each project
    /// @param nonce The nonce for replay protection
    /// @param signature The signature to validate
    /// @return True if signature is valid, false otherwise
    function validateSignature(address voter, uint256[] calldata points, uint256 nonce, bytes calldata signature)
        external
        view
        returns (bool);
}
