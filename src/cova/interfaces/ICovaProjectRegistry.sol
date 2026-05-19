// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IRecipientRegistry} from "../../interfaces/IRecipientRegistry.sol";

/// @title ICovaProjectRegistry
/// @notice {IRecipientRegistry} extended with the COVA project metadata the
///         front end shows and the Art Fund strategy needs (Full Budget,
///         Minimum Viable Budget, title, summary).
interface ICovaProjectRegistry is IRecipientRegistry {
    struct Project {
        uint256 fullBudget;
        uint256 minViableBudget;
        string title;
        string summary;
        bool exists;
    }

    event ProjectRegistered(address indexed project, uint256 fullBudget, uint256 minViableBudget, string title);

    error InvalidBudget();
    error BudgetNotSet();

    function project(address project_) external view returns (Project memory);
    function fullBudgetOf(address project_) external view returns (uint256);
    function minViableBudgetOf(address project_) external view returns (uint256);
}
