// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IBreadKitToken is IERC20 {
    function mint(address receiver) external payable;
    function mint(address receiver, uint256 amount) external;
    function burn(uint256 amount, address receiver) external;
    function claimYield(uint256 amount, address receiver) external;
    function prepareNewYieldClaimer(address yieldClaimer) external;
    function finalizeNewYieldClaimer() external;
    function setYieldClaimer(address yieldClaimer) external;
    function yieldAccrued() external view returns (uint256);
}
