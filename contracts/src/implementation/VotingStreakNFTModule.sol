// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BasisPointsVotingModule} from "../base/BasisPointsVotingModule.sol";
import {IVotingPowerStrategy} from "../interfaces/IVotingPowerStrategy.sol";
import {ICrowdstakeNFT} from "../interfaces/ICrowdstakeNFT.sol";

/// @title VotingStreakNFTModule
/// @notice Extends BasisPointsVotingModule with voting streak tracking and NFT rewards on voting activity
/// @dev Tracks consecutive voting activity per voter and mints a Crowdstake NFT upon reaching a 10-vote streak.
///      Uses the Decorator/Inheritance pattern to augment voting module behavior without modifying core protocol files.
///      This correctly models voting streaks as voter-based activity rather than distribution-based.
contract VotingStreakNFTModule is BasisPointsVotingModule {
    // ============ EIP-7201 Namespaced Storage ============

    /// @notice User voting activity state for streak tracking
    /// @param streak Current consecutive voting streak count
    /// @param lastVoteCycle Last cycle in which the user successfully voted
    struct UserActivity {
        uint256 streak;
        uint256 lastVoteCycle;
    }

    /// @custom:storage-location erc7201:crowdstake.storage.VotingStreakNFTModule
    struct VotingStreakNFTModuleStorage {
        /// @notice Crowdstake NFT contract used for streak rewards
        ICrowdstakeNFT nftContract;
        /// @notice Per-user streak tracking and state
        mapping(address => UserActivity) userActivity;
    }

    // keccak256(abi.encode(uint256(keccak256("crowdstake.storage.VotingStreakNFTModule")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant VOTING_STREAK_NFT_MODULE_STORAGE =
        0xa65dee7b045e43a11600ba41b419f3aad18025b3c1b3b7c19daa6c12d6462c00;

    function _getVotingStreakNFTModuleStorage() internal pure returns (VotingStreakNFTModuleStorage storage $) {
        assembly {
            $.slot := VOTING_STREAK_NFT_MODULE_STORAGE
        }
    }

    // ============ Events ============

    /// @notice Emitted when the NFT contract is updated
    /// @param oldAddress Previous NFT contract address
    /// @param newAddress New NFT contract address
    event NFTContractUpdated(address indexed oldAddress, address indexed newAddress);

    /// @notice Emitted when a user's voting streak is updated
    /// @param user User whose streak was updated
    /// @param newStreak The new streak count after this vote
    /// @param cycle The cycle in which the vote occurred
    event StreakUpdated(address indexed user, uint256 newStreak, uint256 cycle);

    // ============ Views (ABI-compatible getters) ============

    /// @notice Gets the NFT contract address
    /// @return The ICrowdstakeNFT interface instance
    function nftContract() external view returns (ICrowdstakeNFT) {
        return _getVotingStreakNFTModuleStorage().nftContract;
    }

    /// @notice Gets a user's voting activity status
    /// @param user The user address to query
    /// @return streak Current consecutive voting streak
    /// @return lastVoteCycle Last cycle in which the user successfully voted
    function userActivity(address user) external view returns (uint256 streak, uint256 lastVoteCycle) {
        VotingStreakNFTModuleStorage storage $ = _getVotingStreakNFTModuleStorage();
        UserActivity storage activity = $.userActivity[user];
        return (activity.streak, activity.lastVoteCycle);
    }

    // ============ Initialization ============

    /// @notice Initializes the voting streak NFT module
    /// @dev Sets up the module with voting power strategies, distribution settings, and NFT contract.
    ///      Can only be called once due to initializer modifier.
    /// @param _maxPoints Maximum basis points that can be allocated per recipient (e.g., 100 for percentage-based)
    /// @param _strategies Array of voting power strategy contracts for power calculation
    /// @param _distributionModule Address of the distribution module (recipientRegistry and cycleModule are derived from it)
    /// @param _owner Address that will own this contract (receives onlyOwner privileges)
    /// @param _nftContract Crowdstake NFT contract address for streak rewards
    function initialize(
        uint256 _maxPoints,
        IVotingPowerStrategy[] calldata _strategies,
        address _distributionModule,
        address _owner,
        address _nftContract
    ) external initializer {
        if (_nftContract == address(0)) revert ZeroAddress();

        // Initialize parent classes through internal init functions
        __AbstractVotingModule_init(_strategies, _distributionModule, _owner);

        // Set up BasisPointsVotingModule storage
        BasisPointsVotingModuleStorage storage basisPoints = _getBasisPointsVotingModuleStorage();
        basisPoints.maxPoints = _maxPoints;

        // Set up NFT contract for this module
        VotingStreakNFTModuleStorage storage $ = _getVotingStreakNFTModuleStorage();
        $.nftContract = ICrowdstakeNFT(_nftContract);
        emit NFTContractUpdated(address(0), _nftContract);
    }

    // ============ Admin Functions ============

    /// @notice Updates the NFT contract address
    /// @dev Only callable by owner. Allows migration to a different NFT contract if needed.
    /// @param _nftContract New NFT contract address
    function setNFTContract(address _nftContract) external onlyOwner {
        if (_nftContract == address(0)) revert ZeroAddress();

        VotingStreakNFTModuleStorage storage $ = _getVotingStreakNFTModuleStorage();
        address oldAddress = address($.nftContract);
        $.nftContract = ICrowdstakeNFT(_nftContract);

        emit NFTContractUpdated(oldAddress, _nftContract);
    }

    // ============ Internal Overrides ============

    /// @notice Overrides _processVote to include voting streak tracking after standard voting logic
    /// @dev Execution flow:
    ///      1. Calls parent _processVote to execute standard BasisPoints voting math
    ///      2. Fetches current cycle from cycle module
    ///      3. Updates voting streak for the voter
    /// @param voter Address of the voter
    /// @param points Array of basis points for allocation across recipients
    /// @param votingPower Total voting power of the voter
    function _processVote(address voter, uint256[] calldata points, uint256 votingPower) internal override {
        // Step 1: Execute standard voting math via parent
        super._processVote(voter, points, votingPower);

        // Step 2: Fetch current cycle
        uint256 currentCycle = cycleModule().getCurrentCycle();

        // Step 3: Update voting streak
        _updateVotingStreak(voter, currentCycle);
    }

    // ============ Internal Streak Logic ============

    /// @dev Updates a user's voting streak and mints an NFT when streak reaches 10
    /// @param user The user whose streak should be updated
    /// @param currentCycle The current cycle number
    function _updateVotingStreak(address user, uint256 currentCycle) internal {
        VotingStreakNFTModuleStorage storage $ = _getVotingStreakNFTModuleStorage();
        UserActivity storage activity = $.userActivity[user];

        // Re-cast Protection:
        // BasisPointsVotingModule allows users to vote multiple times in the same cycle.
        // If user already voted in this cycle, do not increment streak again.
        if (activity.lastVoteCycle == currentCycle) {
            return;
        }

        // Streak Continuation Logic:
        if (activity.lastVoteCycle + 1 == currentCycle) {
            // Consecutive vote - increment the streak
            unchecked {
                ++activity.streak;
            }
        } else {
            // Streak broken (gap of 1 or more cycles) - reset to 1
            activity.streak = 1;
        }

        // Record this cycle as the last voted cycle
        activity.lastVoteCycle = currentCycle;

        emit StreakUpdated(user, activity.streak, currentCycle);

        // NFT Minting: Mint an NFT when streak reaches exactly 10 (and multiples thereafter)
        if (activity.streak == 10) {
            $.nftContract.mint(user);
        }
    }
}

