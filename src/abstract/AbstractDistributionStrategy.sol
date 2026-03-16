// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IDistributionStrategy} from "../interfaces/IDistributionStrategy.sol";
import {IRecipientRegistry} from "../interfaces/IRecipientRegistry.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title AbstractDistributionStrategy
/// @notice Abstract base for distribution strategies that split yield among registry recipients
/// @dev Concrete strategies implement `distribute` to define how yield is allocated
abstract contract AbstractDistributionStrategy is Initializable, IDistributionStrategy, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    /// @notice Thrown when a zero address is supplied where a valid address is required
    error ZeroAddress();
    /// @notice Thrown when a distribution is attempted with a zero amount
    error ZeroAmount();
    /// @notice Thrown when the recipient registry returns an empty list
    error NoRecipients();
    /// @notice Thrown when the yield amount is too small to distribute at least 1 wei per recipient
    error InsufficientYieldForRecipients();
    /// @notice Thrown when caller is not the distribution manager
    error OnlyDistributionManager();

    /// @notice ERC-20 token being distributed as yield
    IERC20 public yieldToken;
    /// @notice Registry that supplies the list of eligible recipients
    IRecipientRegistry public recipientRegistry;
    /// @notice The distribution manager authorized to call distribute
    address public distributionManager;

    /// @dev Restricts access to the distribution manager
    modifier onlyDistributionManager() {
        if (msg.sender != distributionManager) revert OnlyDistributionManager();
        _;
    }

    /// @dev Initializes the base distribution strategy
    /// @param _yieldToken Address of the yield token to distribute
    /// @param _recipientRegistry Address of the recipient registry
    /// @param _distributionManager Address of the distribution manager authorized to call distribute
    function __AbstractDistributionStrategy_init(
        address _yieldToken,
        address _recipientRegistry,
        address _distributionManager
    ) internal onlyInitializing {
        __Ownable_init(msg.sender);
        __AbstractDistributionStrategy_init_unchained(_yieldToken, _recipientRegistry, _distributionManager);
    }

    function __AbstractDistributionStrategy_init_unchained(
        address _yieldToken,
        address _recipientRegistry,
        address _distributionManager
    ) internal onlyInitializing {
        if (_yieldToken == address(0)) revert ZeroAddress();
        if (_recipientRegistry == address(0)) revert ZeroAddress();
        if (_distributionManager == address(0)) revert ZeroAddress();
        yieldToken = IERC20(_yieldToken);
        recipientRegistry = IRecipientRegistry(_recipientRegistry);
        distributionManager = _distributionManager;
    }

    /// @inheritdoc IDistributionStrategy
    function distribute(uint256 amount) external virtual override;
}
