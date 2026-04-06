// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ICycleModule} from "../interfaces/ICycleModule.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title AbstractCycleModule
/// @notice Abstract contract providing core cycle functionality with fixed cycle implementation
/// @dev All cycle utilities merged into a single abstract module
abstract contract AbstractCycleModule is ICycleModule, OwnableUpgradeable {
    uint256 private constant PERCENTAGE_SCALE = 100;

    // ============ EIP-7201 Namespaced Storage ============

    /// @custom:storage-location erc7201:crowdstake.storage.AbstractCycleModule
    struct AbstractCycleModuleStorage {
        /// @notice The length of each cycle in blocks
        uint256 cycleLength;
        /// @notice The current cycle number
        uint256 currentCycle;
        /// @notice The block number when the current cycle started
        uint256 lastCycleStartBlock;
    }

    // keccak256(abi.encode(uint256(keccak256("crowdstake.storage.AbstractCycleModule")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ABSTRACT_CYCLE_MODULE_STORAGE =
        0x9c8b48e7932311e94122d6adb2ad4f3b3618192da290ca37b1af1f4f2fb82200;

    function _getAbstractCycleModuleStorage() internal pure returns (AbstractCycleModuleStorage storage $) {
        assembly {
            $.slot := ABSTRACT_CYCLE_MODULE_STORAGE
        }
    }

    // ============ Public Getters ============

    /// @notice The length of each cycle in blocks
    function cycleLength() public view returns (uint256) {
        return _getAbstractCycleModuleStorage().cycleLength;
    }

    /// @notice The current cycle number
    function currentCycle() public view returns (uint256) {
        return _getAbstractCycleModuleStorage().currentCycle;
    }

    /// @notice The block number when the current cycle started
    function lastCycleStartBlock() public view returns (uint256) {
        return _getAbstractCycleModuleStorage().lastCycleStartBlock;
    }

    // ============ Errors ============

    /// @notice Error thrown when cycle length is invalid
    error InvalidCycleLength();

    /// @notice Error thrown when cycle transition is invalid
    error InvalidCycleTransition();

    /// @notice Error thrown when module is not initialized
    error NotInitialized();

    // ============ Events ============

    /// @notice Emitted when a new cycle starts
    /// @param cycleNumber The number of the new cycle
    /// @param startBlock The block number when the cycle started
    /// @param endBlock The block number when the cycle will end
    event CycleStarted(uint256 indexed cycleNumber, uint256 startBlock, uint256 endBlock);

    /// @notice Emitted when a cycle transition is validated
    /// @param cycleNumber The number of the validated cycle
    event CycleTransitionValidated(uint256 indexed cycleNumber);

    /// @notice Emitted when the cycle length is updated
    /// @param oldLength The previous cycle length
    /// @param newLength The new cycle length
    event CycleLengthUpdated(uint256 oldLength, uint256 newLength);

    /// @notice Emitted when the module is initialized
    /// @param cycleLength The cycle length in blocks
    /// @param startBlock The starting block number
    event ModuleInitialized(uint256 cycleLength, uint256 startBlock);

    // ============ Modifiers ============

    /// @notice Modifier to ensure module is initialized
    modifier onlyInitialized() {
        if (_getInitializedVersion() == 0) {
            revert NotInitialized();
        }
        _;
    }

    /// @notice Initializes the cycle module with fixed cycle parameters
    /// @dev Can only be called once. Sets the caller as the owner.
    /// @param _cycleLength The length of each cycle in blocks
    /// @param _owner The address that will own this contract
    function initialize(uint256 _cycleLength, address _owner) external initializer {
        if (_cycleLength == 0) {
            revert InvalidCycleLength();
        }

        __Ownable_init(_owner);

        AbstractCycleModuleStorage storage $ = _getAbstractCycleModuleStorage();
        $.cycleLength = _cycleLength;
        $.lastCycleStartBlock = block.number;
        $.currentCycle = 1;

        emit ModuleInitialized(_cycleLength, block.number);
    }

    /// @notice Gets the current cycle number
    /// @return The current cycle number
    function getCurrentCycle() external view virtual onlyInitialized returns (uint256) {
        return _getAbstractCycleModuleStorage().currentCycle;
    }

    /// @notice Checks if the cycle timing allows for distribution
    /// @return Whether the current cycle has completed
    function isCycleComplete() public view virtual onlyInitialized returns (bool) {
        AbstractCycleModuleStorage storage $ = _getAbstractCycleModuleStorage();
        return block.number >= $.lastCycleStartBlock + $.cycleLength;
    }

    /// @notice Starts a new cycle
    /// @dev Only callable by the owner when cycle is complete
    function startNewCycle() external virtual onlyInitialized onlyOwner {
        if (!isCycleComplete()) {
            revert InvalidCycleTransition();
        }

        AbstractCycleModuleStorage storage $ = _getAbstractCycleModuleStorage();
        $.currentCycle++;
        $.lastCycleStartBlock = block.number;

        uint256 endBlock = $.lastCycleStartBlock + $.cycleLength;
        emit CycleStarted($.currentCycle, $.lastCycleStartBlock, endBlock);
        emit CycleTransitionValidated($.currentCycle);
    }

    /// @notice Gets the number of blocks until the next cycle
    /// @return The number of blocks remaining in the current cycle
    function getBlocksUntilNextCycle() external view virtual onlyInitialized returns (uint256) {
        AbstractCycleModuleStorage storage $ = _getAbstractCycleModuleStorage();
        uint256 endBlock = $.lastCycleStartBlock + $.cycleLength;
        if (block.number >= endBlock) {
            return 0;
        }
        return endBlock - block.number;
    }

    /// @notice Gets the progress of the current cycle as a percentage
    /// @return The cycle progress (0-100)
    function getCycleProgress() external view virtual onlyInitialized returns (uint256) {
        AbstractCycleModuleStorage storage $ = _getAbstractCycleModuleStorage();
        uint256 blocksElapsed = block.number - $.lastCycleStartBlock;
        if (blocksElapsed >= $.cycleLength) {
            return PERCENTAGE_SCALE;
        }
        return (blocksElapsed * PERCENTAGE_SCALE) / $.cycleLength;
    }

    /// @notice Updates the cycle length for future cycles
    /// @param newCycleLength The new cycle length in blocks
    function updateCycleLength(uint256 newCycleLength) external virtual onlyInitialized onlyOwner {
        if (newCycleLength == 0) {
            revert InvalidCycleLength();
        }

        AbstractCycleModuleStorage storage $ = _getAbstractCycleModuleStorage();
        uint256 oldLength = $.cycleLength;
        $.cycleLength = newCycleLength;

        emit CycleLengthUpdated(oldLength, newCycleLength);
    }
}
