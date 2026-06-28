// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ICrowdstakeNFT} from "../../src/interfaces/ICrowdstakeNFT.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract MockCrowdstakeNFT is ERC721, ICrowdstakeNFT {
    uint256 private _nextTokenId = 1;

    constructor() ERC721("Mock Crowdstake NFT", "MCNFT") {}

    function mint(address to) external override returns (uint256 tokenId) {
        tokenId = _nextTokenId;
        unchecked {
            ++_nextTokenId;
        }

        _safeMint(to, tokenId);
        return tokenId;
    }
}
