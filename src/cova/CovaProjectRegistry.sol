// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AbstractRecipientRegistry} from "../abstract/AbstractRecipientRegistry.sol";
import {IRecipientRegistry} from "../interfaces/IRecipientRegistry.sol";
import {ICovaProjectRegistry} from "./interfaces/ICovaProjectRegistry.sol";

/// @title CovaProjectRegistry
/// @author COVA Artist Cooperative
/// @notice Crowdstake {AbstractRecipientRegistry} whose recipients are art
///         project payout addresses, carrying the Full / Minimum Viable budget
///         and title/summary the governance front end and Art Fund strategy
///         use. The queued add/remove + `processQueue` cycle semantics of the
///         base registry apply (changes land at the cycle boundary).
contract CovaProjectRegistry is AbstractRecipientRegistry, ICovaProjectRegistry {
    /// @custom:storage-location erc7201:crowdstake.storage.CovaProjectRegistry
    struct CovaProjectRegistryStorage {
        mapping(address => Project) projects;
    }

    // keccak256(abi.encode(uint256(keccak256("crowdstake.storage.CovaProjectRegistry")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant COVA_PROJECT_REGISTRY_STORAGE =
        0x40158e0c30681448860e7656741f5024cc68fd0700aeb4619f38e9d097d8f700;

    function _s() private pure returns (CovaProjectRegistryStorage storage $) {
        assembly {
            $.slot := COVA_PROJECT_REGISTRY_STORAGE
        }
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes with the cooperative coordinator as admin.
    function initialize(address coordinator) external initializer {
        __Ownable_init(coordinator);
    }

    /// @notice Registers a project and queues it for addition at the next cycle.
    function registerProject(
        address project_,
        uint256 fullBudget,
        uint256 minViableBudget,
        string calldata title,
        string calldata summary
    ) external onlyOwner {
        if (project_ == address(0)) revert InvalidRecipient();
        if (minViableBudget == 0 || fullBudget == 0 || minViableBudget > fullBudget) revert InvalidBudget();
        _s().projects[project_] = Project({
            fullBudget: fullBudget, minViableBudget: minViableBudget, title: title, summary: summary, exists: true
        });
        _queueForAddition(project_);
        emit ProjectRegistered(project_, fullBudget, minViableBudget, title);
    }

    /// @inheritdoc IRecipientRegistry
    function queueRecipientAddition(address recipient) external onlyOwner {
        if (!_s().projects[recipient].exists) revert BudgetNotSet();
        _queueForAddition(recipient);
    }

    /// @inheritdoc IRecipientRegistry
    function queueRecipientRemoval(address recipient) external onlyOwner {
        _queueForRemoval(recipient);
    }

    // ---- metadata views ----

    /// @inheritdoc ICovaProjectRegistry
    function project(address project_) external view returns (Project memory) {
        return _s().projects[project_];
    }

    /// @inheritdoc ICovaProjectRegistry
    function fullBudgetOf(address project_) external view returns (uint256) {
        return _s().projects[project_].fullBudget;
    }

    /// @inheritdoc ICovaProjectRegistry
    function minViableBudgetOf(address project_) external view returns (uint256) {
        return _s().projects[project_].minViableBudget;
    }
}
