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

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the equal distribution strategy
    /// @dev Sets up the strategy with yield token and distribution manager.
    ///      Derives recipientRegistry from the distribution manager.
    /// @param _yieldToken Address of the yield token to distribute
    /// @param _distributionManager Address of the distribution manager
    /// @param _owner Address that will own this contract (receives onlyOwner privileges)
    function initialize(address _yieldToken, address _distributionManager, address _owner) external initializer {
        __AbstractDistributionStrategy_init(_yieldToken, _distributionManager, _owner);
    }

    /// @notice Distributes yield equally among all recipients
    /// @dev Distributes the full amount with no dust left in the contract. The last
    ///      recipient absorbs any rounding remainder (up to N-1 wei where N is recipient count).
    /// @param amount The total amount of yield to distribute
    function distribute(uint256 amount) external override onlyDistributionManager nonReentrant {
        if (amount == 0) revert ZeroAmount();

        address[] memory recipients = recipientRegistry().getRecipients();
        if (recipients.length == 0) revert NoRecipients();
        if (amount < recipients.length) revert InsufficientYieldForRecipients();

        uint256 amountPerRecipient = amount / recipients.length;

        IERC20 yieldToken_ = yieldToken();
        uint256 remainder = amount;
        for (uint256 i = 0; i < recipients.length - 1; i++) {
            yieldToken_.safeTransfer(recipients[i], amountPerRecipient);
            emit Distributed(recipients[i], amountPerRecipient);
            remainder -= amountPerRecipient;
        }
        // Last recipient absorbs any rounding dust
        if (remainder > 0) {
            yieldToken_.safeTransfer(recipients[recipients.length - 1], remainder);
            emit Distributed(recipients[recipients.length - 1], remainder);
        }

        AbstractDistributionStrategyStorage storage $ = _getAbstractDistributionStrategyStorage();
        $.distributionId++;
        emit DistributionExecuted($.distributionId);
    }
}
