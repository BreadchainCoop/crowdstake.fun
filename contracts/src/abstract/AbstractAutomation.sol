// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IDistributionManager} from "../interfaces/IDistributionManager.sol";

/// @title AbstractAutomation
/// @notice Abstract base contract for automation providers
/// @dev Inherit this contract to create provider-specific automation implementations
abstract contract AbstractAutomation {
    IDistributionManager public immutable DISTRIBUTION_MANAGER;

    event AutomationExecuted(address indexed executor, uint256 blockNumber);

    error NotResolved();

    constructor(address _distributionManager) {
        require(_distributionManager != address(0), "Invalid distribution manager");
        DISTRIBUTION_MANAGER = IDistributionManager(_distributionManager);
    }

    /// @notice Checks if distribution is ready
    /// @dev Delegates to DistributionManager for condition checking
    /// @return ready Whether the distribution conditions are met
    function isDistributionReady() public view virtual returns (bool ready) {
        return DISTRIBUTION_MANAGER.isDistributionReady();
    }

    /// @notice Gets the automation data for execution
    /// @dev Returns encoded function call data for automation providers
    /// @return execPayload The encoded function call data
    function getAutomationData() public view virtual returns (bytes memory execPayload) {
        // Default implementation: return encoded call to executeDistribution
        if (isDistributionReady()) {
            return abi.encodeWithSelector(this.executeDistribution.selector);
        }
        return new bytes(0);
    }

    /// @notice Executes the distribution
    /// @dev Delegates to DistributionManager for execution
    function executeDistribution() public virtual {
        if (!DISTRIBUTION_MANAGER.isDistributionReady()) revert NotResolved();

        DISTRIBUTION_MANAGER.claimAndDistribute();

        emit AutomationExecuted(msg.sender, block.number);
    }
}
