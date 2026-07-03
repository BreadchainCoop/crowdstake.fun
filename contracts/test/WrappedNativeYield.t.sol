// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {WrappedNativeYield} from "../src/implementation/token/WrappedNativeYield.sol";

/// Minimal WETH9-shaped wrapped native.
contract MockWrappedNative is ERC20 {
    constructor() ERC20("Wrapped Native", "WNAT") {}

    function deposit() external payable {
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external {
        _burn(msg.sender, amount);
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "native xfer");
    }

    receive() external payable {
        _mint(msg.sender, msg.value);
    }
}

/// Minimal ERC-4626-ish vault whose exchange rate can be bumped to simulate yield.
contract MockVault is ERC20 {
    IERC20 public immutable underlying;
    uint256 public rateBps = 10_000; // assets = shares * rate / 10_000

    constructor(address asset_) ERC20("Vault", "vWNAT") {
        underlying = IERC20(asset_);
    }

    function asset() external view returns (address) {
        return address(underlying);
    }

    function setRateBps(uint256 r) external {
        rateBps = r;
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        underlying.transferFrom(msg.sender, address(this), assets);
        shares = (assets * 10_000) / rateBps; // shares for the assets at current rate
        _mint(receiver, shares);
    }

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares) {
        shares = (assets * 10_000) / rateBps;
        _burn(owner, shares);
        underlying.transfer(receiver, assets);
    }

    function convertToAssets(uint256 shares) external view returns (uint256) {
        return (shares * rateBps) / 10_000;
    }
}

contract WrappedNativeYieldTest is Test {
    MockWrappedNative wnat;
    MockVault vault;
    WrappedNativeYield token;
    address user = address(0xBEEF);

    function setUp() public {
        wnat = new MockWrappedNative();
        vault = new MockVault(address(wnat));
        WrappedNativeYield impl = new WrappedNativeYield(address(wnat), address(vault));
        bytes memory data =
            abi.encodeWithSelector(WrappedNativeYield.initialize.selector, "Stake", "STK", address(this));
        token = WrappedNativeYield(payable(address(new ERC1967Proxy(address(impl), data))));
        vm.deal(user, 100 ether);
    }

    function test_ConstructorRevertsOnAssetMismatch() public {
        MockVault wrong = new MockVault(address(0xDEAD)); // asset() != wnat
        vm.expectRevert(WrappedNativeYield.VaultAssetMismatch.selector);
        new WrappedNativeYield(address(wnat), address(wrong));
    }

    function test_DepositNative_Mints1to1_AndVaultHoldsAssets() public {
        vm.prank(user);
        token.mint{value: 10 ether}(user);
        assertEq(token.balanceOf(user), 10 ether, "1:1 mint");
        assertEq(token.totalSupply(), 10 ether, "supply");
        // Vault now custodies 10 units of wrapped native for the token.
        assertEq(wnat.balanceOf(address(vault)), 10 ether, "vault holds wnat");
        assertEq(token.yieldAccrued(), 0, "no yield yet");
    }

    function test_YieldAccrues_WhenVaultAppreciates() public {
        vm.prank(user);
        token.mint{value: 10 ether}(user);
        vault.setRateBps(11_000); // +10% appreciation
        // assets backing the shares now exceed supply → 1 ether of yield.
        assertEq(token.yieldAccrued(), 1 ether, "10% of 10 = 1");
    }

    function test_Burn_RedeemsNative() public {
        vm.prank(user);
        token.mint{value: 10 ether}(user);
        uint256 before = user.balance;
        vm.prank(user);
        token.burn(4 ether, user);
        assertEq(token.balanceOf(user), 6 ether, "burned");
        assertEq(user.balance - before, 4 ether, "native returned 1:1");
    }
}
