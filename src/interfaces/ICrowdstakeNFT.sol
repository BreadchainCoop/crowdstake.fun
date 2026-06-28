// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @title Interface for the Crowdstake NFT contract
/// @dev Extends IERC721 by adding mint functionality used by the Crowdstake voting module and other external consumers.
interface ICrowdstakeNFT is IERC721 {
    /// @notice Mints a new NFT to the specified address.
    /// @param to The address that will receive the NFT.
    /// @return tokenId The unique ID of the newly minted NFT.
    function mint(address to) external returns (uint256);
}
