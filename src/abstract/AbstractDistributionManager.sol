// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IDistributionManager} from "../interfaces/IDistributionManager.sol";
import {IYieldModule} from "../interfaces/IYieldModule.sol";
import {IVotingModule} from "../interfaces/IVotingModule.sol";
import {IRecipientRegistry} from "../interfaces/IRecipientRegistry.sol";
import {ICycleModule} from "../interfaces/ICycleModule.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title AbstractDistributionManager
/// @notice Abstract contract that manages yield claiming and distribution to strategies
/// @dev Claims yield from base token and distributes to the base strategy when conditions are met
abstract contract AbstractDistributionManager is Initializable, OwnableUpgradeable, IDistributionManager {
    using SafeERC20 for IERC20;

    // ============ EIP-7201 Namespaced Storage ============

    /// @custom:storage-location erc7201:crowdstake.storage.AbstractDistributionManager
    struct AbstractDistributionManagerStorage {
        /// @notice Module that exposes yield accrual on the base token
        IYieldModule yieldModule;
        /// @notice Module that tracks voting power and distribution weights
        IVotingModule votingModule;
        /// @notice Registry of eligible distribution recipients
        IRecipientRegistry recipientRegistry;
        /// @notice Cycle module that governs distribution timing
        ICycleModule cycleManager;
        /// @notice ERC-20 token from which yield is claimed and distributed
        IERC20 baseToken;
    }

    // keccak256(abi.encode(uint256(keccak256("crowdstake.storage.AbstractDistributionManager")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ABSTRACT_DISTRIBUTION_MANAGER_STORAGE =
        0xc2850815a6e927da2b1ca8295fc9771026b76fea1a2c1c5ac7766e070eed3b00;

    function _getAbstractDistributionManagerStorage()
        internal
        pure
        returns (AbstractDistributionManagerStorage storage $)
    {
        assembly {
            $.slot := ABSTRACT_DISTRIBUTION_MANAGER_STORAGE
        }
    }

    // ============ Public Getters ============

    /// @notice Module that exposes yield accrual on the base token
    function yieldModule() public view returns (IYieldModule) {
        return _getAbstractDistributionManagerStorage().yieldModule;
    }

    /// @notice Module that tracks voting power and distribution weights
    function votingModule() public view returns (IVotingModule) {
        return _getAbstractDistributionManagerStorage().votingModule;
    }

    /// @notice Registry of eligible distribution recipients
    function recipientRegistry() public view returns (IRecipientRegistry) {
        return _getAbstractDistributionManagerStorage().recipientRegistry;
    }

    /// @notice Cycle module that governs distribution timing
    function cycleManager() public view returns (ICycleModule) {
        return _getAbstractDistributionManagerStorage().cycleManager;
    }

    /// @notice ERC-20 token from which yield is claimed and distributed
    function baseToken() public view returns (IERC20) {
        return _getAbstractDistributionManagerStorage().baseToken;
    }

    // ============ Initialization ============

    /// @dev Initializes the distribution manager
    /// @param _cycleManager Address of the cycle manager
    /// @param _recipientRegistry Address of the recipient registry
    /// @param _baseToken Address of the base token with yield
    /// @param _votingModule Address of the voting module
    function __AbstractDistributionManager_init(
        address _cycleManager,
        address _recipientRegistry,
        address _baseToken,
        address _votingModule
    ) internal onlyInitializing {
        __Ownable_init(msg.sender);
        __AbstractDistributionManager_init_unchained(_cycleManager, _recipientRegistry, _baseToken, _votingModule);
    }

    function __AbstractDistributionManager_init_unchained(
        address _cycleManager,
        address _recipientRegistry,
        address _baseToken,
        address _votingModule
    ) internal onlyInitializing {
        if (_cycleManager == address(0)) revert ZeroAddress();
        if (_recipientRegistry == address(0)) revert ZeroAddress();
        if (_baseToken == address(0)) revert ZeroAddress();
        if (_votingModule == address(0)) revert ZeroAddress();

        AbstractDistributionManagerStorage storage $ = _getAbstractDistributionManagerStorage();
        $.cycleManager = ICycleModule(_cycleManager);
        $.recipientRegistry = IRecipientRegistry(_recipientRegistry);
        $.baseToken = IERC20(_baseToken);
        $.votingModule = IVotingModule(_votingModule);

        // Assume base token implements IYieldModule
        $.yieldModule = IYieldModule(_baseToken);
    }

    /// @notice Checks if distribution is ready
    /// @dev Must be implemented by child contracts with their own readiness criteria
    function isDistributionReady() public view virtual override returns (bool ready);

    /// @notice Claims yield from the base token and distributes
    /// @dev Must be implemented by child contracts
    function claimAndDistribute() external virtual;

    /// @notice Gets the total current voting power from voting module
    /// @dev This should sum up all active votes or return total voting power
    /// @return totalPower The total voting power currently active
    function getTotalCurrentVotingPower() public view virtual returns (uint256 totalPower) {
        // Get current voting distribution and sum it up
        uint256[] memory distribution =
            _getAbstractDistributionManagerStorage().votingModule.getCurrentVotingDistribution();
        for (uint256 i = 0; i < distribution.length; i++) {
            totalPower += distribution[i];
        }
    }
}
