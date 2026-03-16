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

    /// @notice Module that provides the current vote distribution weights
    IVotingModule public votingModule;

    /// @notice Thrown when the voting distribution array length doesn't match the recipient count
    error InvalidVotesLength();
    /// @notice Thrown when attempting to distribute while no votes have been cast
    error NoVotes();

    /// @dev Initializes the voting distribution strategy
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
        votingModule = IVotingModule(_votingModule);
    }

    /// @dev Distributes amount based on voting weights
    function distribute(uint256 amount) external override onlyDistributionManager {
        if (amount == 0) revert ZeroAmount();

        address[] memory recipients = recipientRegistry.getRecipients();
        if (recipients.length == 0) revert NoRecipients();
        if (amount < recipients.length) revert InsufficientYieldForRecipients();

        uint256[] memory currentVotes = votingModule.getCurrentVotingDistribution();
        if (currentVotes.length != recipients.length) revert InvalidVotesLength();

        uint256 totalVotes = 0;
        for (uint256 i = 0; i < currentVotes.length; i++) {
            totalVotes += currentVotes[i];
        }

        if (totalVotes == 0) revert NoVotes();

        for (uint256 i = 0; i < recipients.length; i++) {
            uint256 recipientShare = (amount * currentVotes[i]) / totalVotes;
            if (recipientShare > 0) {
                yieldToken.safeTransfer(recipients[i], recipientShare);
                emit Distributed(recipients[i], recipientShare);
            }
        }
    }

    /// @notice Updates the voting module
    /// @param _votingModule Address of the voting module
    function setVotingModule(address _votingModule) external onlyOwner {
        if (_votingModule == address(0)) revert ZeroAddress();
        votingModule = IVotingModule(_votingModule);
    }
}
