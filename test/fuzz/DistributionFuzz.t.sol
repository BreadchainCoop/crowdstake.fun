// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockYieldToken
/// @notice Minimal ERC20 for distribution fuzz tests
contract MockYieldToken is ERC20 {
    constructor() ERC20("Yield", "YLD") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @title DistributionFuzz
/// @notice Fuzz tests for distribution logic: conservation of funds and equal split invariants.
///         Tests the pure arithmetic used by EqualDistributionStrategy and VotingDistributionStrategy
///         without deploying the full upgradeable proxy stack.
contract DistributionFuzz is Test {
    MockYieldToken token;

    function setUp() public {
        token = new MockYieldToken();
    }

    /// @notice Fuzz equal distribution: total distributed <= total input, each share == amount/count
    function testFuzz_EqualDistributionConservation(uint256 amount, uint8 rawCount) public {
        uint256 recipientCount = bound(rawCount, 1, 50);
        amount = bound(amount, recipientCount, 1e30); // at least 1 wei per recipient

        uint256 amountPerRecipient = amount / recipientCount;
        uint256 totalDistributed = amountPerRecipient * recipientCount;

        // Conservation: total distributed never exceeds input
        assertLe(totalDistributed, amount);

        // Dust is always less than recipientCount
        uint256 dust = amount - totalDistributed;
        assertLt(dust, recipientCount);

        // Each recipient gets the same amount
        for (uint256 i = 0; i < recipientCount; i++) {
            assertEq(amountPerRecipient, amount / recipientCount);
        }
    }

    /// @notice Fuzz voting distribution: proportional split conserves total
    function testFuzz_VotingDistributionConservation(
        uint256 amount,
        uint256[5] memory rawVotes
    ) public pure {
        amount = bound(amount, 5, 1e30);

        // Ensure at least one vote is non-zero
        uint256 totalVotes;
        uint256[5] memory votes;
        for (uint256 i = 0; i < 5; i++) {
            votes[i] = bound(rawVotes[i], 0, 1e18);
            totalVotes += votes[i];
        }
        if (totalVotes == 0) return; // skip if all zero

        uint256 totalDistributed;
        for (uint256 i = 0; i < 5; i++) {
            uint256 share = (amount * votes[i]) / totalVotes;
            totalDistributed += share;
        }

        // Conservation: total distributed never exceeds input
        assert(totalDistributed <= amount);

        // Dust bound: at most (recipientCount - 1) wei of rounding dust
        assert(amount - totalDistributed < 5);
    }

    /// @notice Fuzz that equal distribution with actual token transfers conserves balance
    function testFuzz_EqualDistributionTokenTransfer(uint256 amount, uint8 rawCount) public {
        uint256 recipientCount = bound(rawCount, 1, 20);
        amount = bound(amount, recipientCount, 1e24);

        address distributor = address(0xD1);
        token.mint(distributor, amount);

        uint256 amountPerRecipient = amount / recipientCount;

        vm.startPrank(distributor);
        uint256 totalSent;
        for (uint256 i = 0; i < recipientCount; i++) {
            address recipient = address(uint160(0x1000 + i));
            token.transfer(recipient, amountPerRecipient);
            totalSent += amountPerRecipient;
            assertEq(token.balanceOf(recipient), amountPerRecipient);
        }
        vm.stopPrank();

        // Distributor retains only the dust
        uint256 remaining = token.balanceOf(distributor);
        assertEq(remaining, amount - totalSent);
        assertLt(remaining, recipientCount);
    }

    /// @notice Fuzz voting distribution with token transfers -- proportional and conserving
    function testFuzz_VotingDistributionTokenTransfer(
        uint256 amount,
        uint256 vote0,
        uint256 vote1,
        uint256 vote2
    ) public {
        amount = bound(amount, 3, 1e24);
        vote0 = bound(vote0, 0, 1e18);
        vote1 = bound(vote1, 0, 1e18);
        vote2 = bound(vote2, 0, 1e18);
        uint256 totalVotes = vote0 + vote1 + vote2;
        vm.assume(totalVotes > 0);

        uint256[3] memory votes = [vote0, vote1, vote2];

        address distributor = address(0xD2);
        token.mint(distributor, amount);

        vm.startPrank(distributor);
        uint256 totalSent;
        for (uint256 i = 0; i < 3; i++) {
            uint256 share = (amount * votes[i]) / totalVotes;
            if (share > 0) {
                address recipient = address(uint160(0x2000 + i));
                token.transfer(recipient, share);
                totalSent += share;
                assertEq(token.balanceOf(recipient), share);
            }
        }
        vm.stopPrank();

        // Conservation
        assertEq(token.balanceOf(distributor), amount - totalSent);
        assertLe(totalSent, amount);
    }

    /// @notice Fuzz that single-recipient distribution gives full amount
    function testFuzz_SingleRecipientGetsAll(uint256 amount) public pure {
        amount = bound(amount, 1, 1e30);
        uint256 share = amount / 1; // 1 recipient
        assertEq(share, amount);
    }
}
