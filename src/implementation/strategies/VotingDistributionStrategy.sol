// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AbstractDistributionStrategy} from "../../abstract/AbstractDistributionStrategy.sol";
import {IDistributionManager} from "../../interfaces/IDistributionManager.sol";
import {IVotingModule} from "../../interfaces/IVotingModule.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title VotingDistributionStrategy
/// @notice Distributes yield based on voting results
/// @dev Implements proportional distribution based on vote counts using recipient registry.
///      The voting module is read dynamically from the distribution manager so that updates
///      to the manager's voting module are automatically reflected here.
contract VotingDistributionStrategy is AbstractDistributionStrategy {
    using SafeERC20 for IERC20;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ============ Public Getters ============

    /// @notice Returns the voting module from the distribution manager
    /// @dev Read dynamically so changes to the manager's voting module are always reflected
    function votingModule() public view returns (IVotingModule) {
        return IDistributionManager(distributionManager()).votingModule();
    }

    // ============ Errors ============

    /// @notice Thrown when the voting distribution array length doesn't match the recipient count
    error InvalidVotesLength();
    /// @notice Thrown when attempting to distribute while no votes have been cast
    error NoVotes();

    // ============ Initialization ============

    /// @notice Initializes the voting distribution strategy
    /// @dev Sets up the strategy with yield token and distribution manager.
    ///      Derives recipientRegistry from the distribution manager.
    ///      The voting module is read dynamically from the distribution manager at point of use.
    /// @param _yieldToken Address of the yield token to distribute
    /// @param _distributionManager Address of the distribution manager
    /// @param _owner Address that will own this contract (receives onlyOwner privileges)
    function initialize(address _yieldToken, address _distributionManager, address _owner) external initializer {
        __AbstractDistributionStrategy_init(_yieldToken, _distributionManager, _owner);
    }

    /// @notice Distributes yield proportionally based on voting weights
    /// @dev Recipients with zero votes receive nothing; dust from rounding is left in the contract
    /// @param amount The total amount of yield to distribute
    function distribute(uint256 amount) external override onlyDistributionManager {
        if (amount == 0) revert ZeroAmount();

        address[] memory recipients = recipientRegistry().getRecipients();
        if (recipients.length == 0) revert NoRecipients();
        if (amount < recipients.length) revert InsufficientYieldForRecipients();

        uint256[] memory currentVotes = votingModule().getCurrentVotingDistribution();
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
}
