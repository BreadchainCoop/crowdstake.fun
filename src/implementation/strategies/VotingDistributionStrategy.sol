// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AbstractDistributionStrategy} from "../../abstract/AbstractDistributionStrategy.sol";
import {IVotingModule} from "../../interfaces/IVotingModule.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title VotingDistributionStrategy
/// @notice Distributes yield based on voting results
/// @dev Implements proportional distribution based on vote counts using recipient registry
contract VotingDistributionStrategy is AbstractDistributionStrategy {
    using SafeERC20 for IERC20;

    // ============ EIP-7201 Namespaced Storage ============

    /// @custom:storage-location erc7201:crowdstake.storage.VotingDistributionStrategy
    struct VotingDistributionStrategyStorage {
        /// @notice Module that provides the current vote distribution weights
        IVotingModule votingModule;
    }

    // keccak256(abi.encode(uint256(keccak256("crowdstake.storage.VotingDistributionStrategy")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant VOTING_DISTRIBUTION_STRATEGY_STORAGE =
        0x63ddb3382b8f5a7e8d70aa48cbf62b6ffc6f1c965e8b80cdb62d6e2177817e00;

    function _getVotingDistributionStrategyStorage()
        private
        pure
        returns (VotingDistributionStrategyStorage storage $)
    {
        assembly {
            $.slot := VOTING_DISTRIBUTION_STRATEGY_STORAGE
        }
    }

    // ============ Public Getters ============

    /// @notice Module that provides the current vote distribution weights
    function votingModule() public view returns (IVotingModule) {
        return _getVotingDistributionStrategyStorage().votingModule;
    }

    // ============ Errors ============

    /// @notice Thrown when the voting distribution array length doesn't match the recipient count
    error InvalidVotesLength();
    /// @notice Thrown when attempting to distribute while no votes have been cast
    error NoVotes();

    // ============ Initialization ============

    /// @notice Initializes the voting distribution strategy
    /// @dev Sets up the strategy with yield token, recipient registry, voting module, and distribution manager
    /// @param _yieldToken Address of the yield token to distribute
    /// @param _recipientRegistry Address of the recipient registry
    /// @param _votingModule Address of the voting module
    /// @param _distributionManager Address of the distribution manager
    function initialize(
        address _yieldToken,
        address _recipientRegistry,
        address _votingModule,
        address _distributionManager
    ) external initializer {
        __AbstractDistributionStrategy_init(_yieldToken, _recipientRegistry, _distributionManager);
        if (_votingModule == address(0)) revert ZeroAddress();
        _getVotingDistributionStrategyStorage().votingModule = IVotingModule(_votingModule);
    }

    /// @notice Distributes yield proportionally based on voting weights
    /// @dev Recipients with zero votes receive nothing; dust from rounding is left in the contract
    /// @param amount The total amount of yield to distribute
    function distribute(uint256 amount) external override onlyDistributionManager {
        if (amount == 0) revert ZeroAmount();

        address[] memory recipients = recipientRegistry().getRecipients();
        if (recipients.length == 0) revert NoRecipients();
        if (amount < recipients.length) revert InsufficientYieldForRecipients();

        uint256[] memory currentVotes =
            _getVotingDistributionStrategyStorage().votingModule.getCurrentVotingDistribution();
        if (currentVotes.length != recipients.length) revert InvalidVotesLength();

        uint256 totalVotes = 0;
        for (uint256 i = 0; i < currentVotes.length; i++) {
            totalVotes += currentVotes[i];
        }

        if (totalVotes == 0) revert NoVotes();

        IERC20 yieldToken_ = yieldToken();
        for (uint256 i = 0; i < recipients.length; i++) {
            uint256 recipientShare = (amount * currentVotes[i]) / totalVotes;
            if (recipientShare > 0) {
                yieldToken_.safeTransfer(recipients[i], recipientShare);
                emit Distributed(recipients[i], recipientShare);
            }
        }

        AbstractDistributionStrategyStorage storage $ = _getAbstractDistributionStrategyStorage();
        $.distributionId++;
        emit DistributionExecuted($.distributionId);
    }

    /// @notice Updates the voting module
    /// @param _votingModule Address of the voting module
    function setVotingModule(address _votingModule) external onlyOwner {
        if (_votingModule == address(0)) revert ZeroAddress();
        _getVotingDistributionStrategyStorage().votingModule = IVotingModule(_votingModule);
    }
}
