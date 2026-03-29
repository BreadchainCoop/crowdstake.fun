// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AbstractDistributionStrategy} from "../../abstract/AbstractDistributionStrategy.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title EqualDistributionStrategy
/// @notice Distributes yield equally among all recipients from registry
/// @dev Implements equal distribution logic using recipient registry
contract EqualDistributionStrategy is AbstractDistributionStrategy {
    using SafeERC20 for IERC20;

    /// @notice Initializes the equal distribution strategy
    /// @dev Sets up the strategy with yield token, recipient registry, and distribution manager
    /// @param _yieldToken Address of the yield token to distribute
    /// @param _recipientRegistry Address of the recipient registry
    /// @param _distributionManager Address of the distribution manager
    function initialize(address _yieldToken, address _recipientRegistry, address _distributionManager)
        external
        initializer
    {
        __AbstractDistributionStrategy_init(_yieldToken, _recipientRegistry, _distributionManager);
    }

    /// @notice Distributes yield equally among all recipients
    /// @dev Dust from integer division is left in the contract
    /// @param amount The total amount of yield to distribute
    function distribute(uint256 amount) external override onlyDistributionManager {
        if (amount == 0) revert ZeroAmount();

        address[] memory recipients = recipientRegistry().getRecipients();
        if (recipients.length == 0) revert NoRecipients();
        if (amount < recipients.length) revert InsufficientYieldForRecipients();

        uint256 amountPerRecipient = amount / recipients.length;

        IERC20 yieldToken_ = yieldToken();
        for (uint256 i = 0; i < recipients.length; i++) {
            yieldToken_.safeTransfer(recipients[i], amountPerRecipient);
            emit Distributed(recipients[i], amountPerRecipient);
        }

        AbstractDistributionStrategyStorage storage $ = _getAbstractDistributionStrategyStorage();
        $.distributionId++;
        emit DistributionExecuted($.distributionId);
    }
}
