// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Minimal mintable ERC20 for fuzz tests (no fork).
contract MockERC20 is ERC20 {
    constructor() ERC20("MockYield", "MYLD") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
