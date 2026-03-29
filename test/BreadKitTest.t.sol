// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TestWrapper} from "./TestWrapper.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {CrowdStakeFactory} from "../src/CrowdStakeFactory.sol";
import {SexyDaiYield} from "../src/implementation/token/SexyDaiYield.sol";
import {IToken} from "../src/interfaces/IToken.sol";
import {IWXDAI} from "../src/interfaces/IWXDAI.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AbstractToken} from "../src/abstract/AbstractToken.sol";

contract BreadKitTest is TestWrapper {
    address constant WX_DAI = 0xe91D153E0b41518A2Ce8Dd3D7944Fa863463a97d;
    address constant SX_DAI = 0xaf204776c7245bF4147c2612BF6e5972Ee483701;
    CrowdStakeFactory public factory;
    IToken public token;
    address public constant RANDOM_HOLDER = 0x23b4f73FB31e89B27De17f9c5DE2660cc1FB0CdF; // random multisig
    address public constant RANDOM_EOA = 0x000000000000000000000000000000000000dEaD;

    function setUp() public {
        factory = new CrowdStakeFactory(address(this));

        /// @dev this is how we deploy and whitelist a new token type
        address impl = address(new SexyDaiYield(WX_DAI, SX_DAI));
        address beacon = address(new UpgradeableBeacon(impl, address(this)));
        address[] memory beacons = new address[](1);
        beacons[0] = beacon;
        factory.whitelistBeacons(beacons);

        /// @dev this is how we deploy a new token

        // encode initialization payload for given token type
        bytes memory payload = abi.encodeWithSelector(SexyDaiYield.initialize.selector, "TOKEN", "T", address(this));

        // deploy token
        token = IToken(factory.createToken(address(beacon), payload, keccak256("random salt")));

        // deploy yield claimer
        address[] memory recipients = new address[](1);
        address claimer =
            factory.createDefaultYieldClaimer(address(token), recipients, 0, address(this), keccak256("random salt"));

        // set yield claimer
        token.setYieldClaimer(claimer);

        // burn 1 wei
        token.mint{value: 1}(0x0000000000000000000000000000000000000009);
    }

    function test_mint() public {
        uint256 supplyBefore = token.totalSupply();
        uint256 balBefore = token.balanceOf(address(this));
        uint256 contractBalBefore = IERC20(SX_DAI).balanceOf(address(token));

        assertEq(supplyBefore, 1);
        assertEq(balBefore, 0);
        assertEq(contractBalBefore, 0);

        token.mint{value: 1 ether}(address(this));

        uint256 supplyAfter = token.totalSupply();
        uint256 balAfter = token.balanceOf(address(this));
        uint256 contractBalAfter = IERC20(SX_DAI).balanceOf(address(token));

        assertEq(supplyAfter, supplyBefore + 1 ether);
        assertEq(balAfter, balBefore + 1 ether);
        assertGt(contractBalAfter, contractBalBefore);
        assertLt(contractBalAfter, supplyBefore + 1 ether);

        uint256 yieldBefore = token.yieldAccrued();
        assertEq(yieldBefore, 0);

        assertTrue(token.transfer(RANDOM_EOA, 0.5 ether));
        assertEq(token.balanceOf(address(this)), 0.5 ether);
        assertEq(token.balanceOf(RANDOM_EOA), 0.5 ether);

        IWXDAI(WX_DAI).deposit{value: 1 ether}();

        IERC20(WX_DAI).approve(address(token), 1 ether);
        token.mint(address(this), 1 ether);

        assertEq(token.balanceOf(address(this)), 1.5 ether);
    }

    function test_finalizeNewYieldClaimer_revertsBeforeTimelock() public {
        address newClaimer = address(0xCAFE);

        token.prepareNewYieldClaimer(newClaimer);

        // Warp forward less than 14 days
        vm.warp(block.timestamp + 13 days);

        vm.expectRevert(AbstractToken.TimelockNotElapsed.selector);
        token.finalizeNewYieldClaimer();
    }

    function test_finalizeNewYieldClaimer_succeedsAfterTimelock() public {
        address newClaimer = address(0xCAFE);

        token.prepareNewYieldClaimer(newClaimer);

        // Warp forward past 14 days
        vm.warp(block.timestamp + 14 days + 1);

        token.finalizeNewYieldClaimer();

        assertEq(AbstractToken(address(token)).yieldClaimer(), newClaimer);
    }

    function test_finalizeNewYieldClaimer_clearsPendingState() public {
        address newClaimer = address(0xCAFE);

        token.prepareNewYieldClaimer(newClaimer);

        // Verify pending state is set
        assertEq(AbstractToken(address(token)).pendingYieldClaimer(), newClaimer);
        assertGt(AbstractToken(address(token)).pendingFinishedAt(), 0);

        // Warp forward past 14 days
        vm.warp(block.timestamp + 14 days + 1);

        token.finalizeNewYieldClaimer();

        // Verify pending state is cleared
        assertEq(AbstractToken(address(token)).pendingYieldClaimer(), address(0));
        assertEq(AbstractToken(address(token)).pendingFinishedAt(), 0);
    }
}
