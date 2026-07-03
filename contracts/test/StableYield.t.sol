// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {StableYield} from "../src/implementation/token/StableYield.sol";

/// 6-decimal stablecoin (like USDC).
contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mintTo(address to, uint256 amt) external {
        _mint(to, amt);
    }
}

/// ERC-4626-ish vault with 18-decimal shares over a 6-decimal asset (like MetaMorpho USDC),
/// with a bumpable rate to simulate appreciation. Assets are in the asset's 6 decimals.
contract MockStableVault is ERC20 {
    address public immutable underlying;
    uint256 public rateBps = 10_000;

    constructor(address asset_) ERC20("Vault USDC", "vUSDC") {
        underlying = asset_;
    }

    function asset() external view returns (address) {
        return underlying;
    }

    function setRateBps(uint256 r) external {
        rateBps = r;
    }

    // 18-dec shares for a 6-dec asset: scale by 1e12, apply rate.
    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        IERC20(underlying).transferFrom(msg.sender, address(this), assets);
        shares = (assets * 1e12 * 10_000) / rateBps;
        _mint(receiver, shares);
    }

    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares) {
        shares = (assets * 1e12 * 10_000) / rateBps;
        _burn(owner, shares);
        IERC20(underlying).transfer(receiver, assets);
    }

    function convertToAssets(uint256 shares) external view returns (uint256) {
        return (shares * rateBps) / (10_000 * 1e12);
    }
}

contract StableYieldTest is Test {
    MockUSDC usdc;
    MockStableVault vault;
    StableYield token;
    address user = address(0xBEEF);

    uint256 constant ONE = 1e6; // 1 USDC

    function setUp() public {
        usdc = new MockUSDC();
        vault = new MockStableVault(address(usdc));
        StableYield impl = new StableYield(address(usdc), address(vault));
        bytes memory data = abi.encodeWithSelector(StableYield.initialize.selector, "Stake", "STK", address(this));
        token = StableYield(payable(address(new ERC1967Proxy(address(impl), data))));
        usdc.mintTo(user, 1_000 * ONE);
        vm.deal(user, 10 ether);
    }

    function test_DecimalsMirrorUnderlying() public view {
        assertEq(token.decimals(), 6, "token decimals == USDC decimals");
    }

    function test_ConstructorRevertsOnAssetMismatch() public {
        MockUSDC other = new MockUSDC();
        MockStableVault wrong = new MockStableVault(address(other));
        vm.expectRevert(StableYield.VaultAssetMismatch.selector);
        new StableYield(address(usdc), address(wrong));
    }

    function test_DepositStable_Mints1to1() public {
        vm.startPrank(user);
        usdc.approve(address(token), 100 * ONE);
        token.mint(user, 100 * ONE);
        vm.stopPrank();
        assertEq(token.balanceOf(user), 100 * ONE, "1:1 mint in 6dp");
        assertEq(token.totalSupply(), 100 * ONE, "supply");
        assertEq(usdc.balanceOf(address(vault)), 100 * ONE, "vault holds USDC");
        assertEq(token.yieldAccrued(), 0, "no yield yet");
    }

    function test_NativeDepositReverts() public {
        vm.prank(user);
        vm.expectRevert(StableYield.NativeNotSupported.selector);
        token.mint{value: 1 ether}(user);
    }

    function test_YieldAccrues_WithDecimalOffset() public {
        vm.startPrank(user);
        usdc.approve(address(token), 100 * ONE);
        token.mint(user, 100 * ONE);
        vm.stopPrank();
        vault.setRateBps(10_500); // +5% appreciation
        // 100 USDC backing grows to 105 → 5 USDC (5e6) of yield, in 6dp.
        assertEq(token.yieldAccrued(), 5 * ONE, "5% of 100 = 5 USDC");
    }

    function test_Burn_RedeemsStable() public {
        vm.startPrank(user);
        usdc.approve(address(token), 100 * ONE);
        token.mint(user, 100 * ONE);
        uint256 before = usdc.balanceOf(user);
        token.burn(40 * ONE, user);
        vm.stopPrank();
        assertEq(token.balanceOf(user), 60 * ONE, "burned");
        assertEq(usdc.balanceOf(user) - before, 40 * ONE, "USDC returned 1:1");
    }
}
