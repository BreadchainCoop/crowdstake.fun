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
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";

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
        /// @notice Off-chain URI (ipfs/https/data) for this instance's token image
        string tokenImageURI;
        /// @notice Off-chain URI (ipfs/https/data) for this instance's header/banner image
        string bannerImageURI;
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

    // ============ Instance Metadata (ERC-7572) ============

    /// @notice Off-chain URI for this instance's token image
    function tokenImageURI() public view returns (string memory) {
        return _getAbstractDistributionManagerStorage().tokenImageURI;
    }

    /// @notice Off-chain URI for this instance's header/banner image
    function bannerImageURI() public view returns (string memory) {
        return _getAbstractDistributionManagerStorage().bannerImageURI;
    }

    /// @notice ERC-7572 contract-level metadata: a data URI JSON pointing at the
    ///         instance's two image URIs (the distribution manager is the app's
    ///         canonical per-instance key; the token pulls this via its claimer).
    function contractURI() external view returns (string memory) {
        AbstractDistributionManagerStorage storage $ = _getAbstractDistributionManagerStorage();
        string memory json =
            string(abi.encodePacked('{"image":"', $.tokenImageURI, '","banner_image":"', $.bannerImageURI, '"}'));
        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(bytes(json))));
    }

    // ============ Events ============

    /// @notice Emitted when the voting module is set or changed
    event VotingModuleSet(address indexed votingModule);

    /// @notice Emitted when the instance image metadata changes
    event InstanceMetadataSet(string tokenImageURI, string bannerImageURI);

    /// @notice ERC-7572: signals indexers/wallets to refresh contract metadata
    event ContractURIUpdated();

    // ============ Admin ============

    /// @notice Sets the voting module reference
    /// @param _votingModule Address of the voting module
    function setVotingModule(address _votingModule) external onlyOwner {
        if (_votingModule == address(0)) revert ZeroAddress();
        _getAbstractDistributionManagerStorage().votingModule = IVotingModule(_votingModule);
        emit VotingModuleSet(_votingModule);
    }

    /// @notice Set the instance's token + banner image URIs (owner only). The
    ///         deployer seeds these at deploy; the instance owner can update later.
    function setInstanceMetadata(string calldata tokenImageURI_, string calldata bannerImageURI_) external onlyOwner {
        AbstractDistributionManagerStorage storage $ = _getAbstractDistributionManagerStorage();
        $.tokenImageURI = tokenImageURI_;
        $.bannerImageURI = bannerImageURI_;
        emit InstanceMetadataSet(tokenImageURI_, bannerImageURI_);
        emit ContractURIUpdated();
    }

    // ============ Initialization ============

    /// @dev Initializes the distribution manager
    /// @param _cycleManager Address of the cycle manager
    /// @param _recipientRegistry Address of the recipient registry
    /// @param _baseToken Address of the base token with yield
    /// @param _votingModule Address of the voting module
    /// @param _owner Address that will own this contract (receives onlyOwner privileges)
    function __AbstractDistributionManager_init(
        address _cycleManager,
        address _recipientRegistry,
        address _baseToken,
        address _votingModule,
        address _owner
    ) internal onlyInitializing {
        __Ownable_init(_owner);
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
