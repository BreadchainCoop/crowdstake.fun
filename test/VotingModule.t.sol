// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {BasisPointsVotingModule} from "../src/base/BasisPointsVotingModule.sol";
import {IVotingModule} from "../src/interfaces/IVotingModule.sol";
import {TokenBasedVotingPower} from "../src/implementation/strategies/TokenBasedVotingPower.sol";
import {IVotingPowerStrategy} from "../src/interfaces/IVotingPowerStrategy.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {MockRecipientRegistry} from "./mocks/MockRecipientRegistry.sol";
import {CycleModule} from "../src/implementation/CycleModule.sol";
import {MockDistributionModule} from "./mocks/MockDistributionModule.sol";

// Mock token implementation for testing
contract MockToken is ERC20, ERC20Votes, ERC20Permit {
    constructor() ERC20("Mock Token", "MOCK") ERC20Permit("Mock Token") {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function _update(address from, address to, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._update(from, to, amount);
    }

    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return ERC20Permit.nonces(owner);
    }
}

contract VotingModuleTest is Test {
    // Constants
    uint256 constant MAX_POINTS = 100;

    // Contracts
    BasisPointsVotingModule public votingModule;
    TokenBasedVotingPower public tokenStrategy;
    MockToken public token;
    MockRecipientRegistry public recipientRegistry;
    CycleModule public cycleModule;
    MockDistributionModule public distributionModule;

    // Test accounts
    address public owner;
    address public voter1;
    address public voter2;
    address public voter3;
    uint256 public voter1PrivateKey;
    uint256 public voter2PrivateKey;
    uint256 public voter3PrivateKey;

    // Events
    event VoteCast(address indexed voter, uint256[] points, uint256 votingPower, uint256 nonce, bytes signature);
    event BatchVotesCast(address[] voters, uint256[] nonces);
    event VotingModuleInitialized(IVotingPowerStrategy[] strategies);

    function setUp() public {
        // Setup test accounts
        owner = address(this);
        voter1PrivateKey = 0x1;
        voter2PrivateKey = 0x2;
        voter3PrivateKey = 0x3;
        voter1 = vm.addr(voter1PrivateKey);
        voter2 = vm.addr(voter2PrivateKey);
        voter3 = vm.addr(voter3PrivateKey);

        // Deploy mock token
        token = new MockToken();

        // Mint tokens to test accounts
        token.mint(voter1, 5 ether);
        token.mint(voter2, 3 ether);
        token.mint(voter3, 2 ether);

        // Delegate voting power to themselves (required for ERC20Votes)
        vm.prank(voter1);
        token.delegate(voter1);

        vm.prank(voter2);
        token.delegate(voter2);

        vm.prank(voter3);
        token.delegate(voter3);

        // Deploy recipient registry mock with 3 recipients
        address[] memory recipients = new address[](3);
        recipients[0] = address(0x111);
        recipients[1] = address(0x222);
        recipients[2] = address(0x333);
        recipientRegistry = new MockRecipientRegistry(recipients);

        // Deploy voting power strategy
        tokenStrategy = new TokenBasedVotingPower(IVotes(address(token)));

        // Deploy utility contracts

        // Deploy and initialize cycle module
        cycleModule = new CycleModule();
        cycleModule.initialize(1000); // 1000 blocks per cycle

        // Deploy mock distribution module
        distributionModule = new MockDistributionModule();

        // Deploy and initialize voting module
        votingModule = new BasisPointsVotingModule();
        IVotingPowerStrategy[] memory strategies = new IVotingPowerStrategy[](1);
        strategies[0] = IVotingPowerStrategy(address(tokenStrategy));

        votingModule.initialize(
            MAX_POINTS, strategies, address(distributionModule), address(recipientRegistry), address(cycleModule)
        );
    }

    // Helper function to create vote signature
    function createVoteSignature(address voter, uint256 privateKey, uint256[] memory points, uint256 nonce)
        internal
        view
        returns (bytes memory)
    {
        bytes32 domainSeparator = votingModule.DOMAIN_SEPARATOR();
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Vote(address voter,bytes32 pointsHash,uint256 nonce)"),
                voter,
                keccak256(abi.encodePacked(points)),
                nonce
            )
        );
        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);
        return abi.encodePacked(r, s, v);
    }

    function testInitialization() public view {
        assertEq(votingModule.maxPoints(), MAX_POINTS);
        assertEq(cycleModule.getCurrentCycle(), 1);

        IVotingPowerStrategy[] memory strategies = votingModule.getVotingPowerStrategies();
        assertEq(strategies.length, 1);
        assertEq(address(strategies[0]), address(tokenStrategy));
        assertEq(address(votingModule.recipientRegistry()), address(recipientRegistry));
    }

    function testDirectVoting() public {
        uint256[] memory points = new uint256[](3);
        points[0] = 50;
        points[1] = 30;
        points[2] = 20;

        uint256 nonce = 1;
        bytes memory signature = createVoteSignature(voter1, voter1PrivateKey, points, nonce);
        votingModule.castVoteWithSignature(voter1, points, nonce, signature);

        // Verify vote was recorded by checking that the voter has voted
        assertTrue(votingModule.hasVotedInCurrentCycle(voter1), "Voter1 should have voted in current cycle");

        uint256[] memory projectDist = votingModule.getCurrentVotingDistribution();
        assertEq(projectDist.length, 3);
    }

    function testSignatureVoting() public {
        uint256[] memory points = new uint256[](3);
        points[0] = 40;
        points[1] = 35;
        points[2] = 25;

        uint256 nonce = 1;

        // Create signature
        bytes32 digest = _createVoteDigest(voter1, points, nonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(voter1PrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Cast vote with signature
        vm.expectEmit(true, false, false, true);
        emit VoteCast(voter1, points, votingModule.getVotingPower(voter1), nonce, signature);

        votingModule.castVoteWithSignature(voter1, points, nonce, signature);

        // Verify vote was recorded
        assertTrue(votingModule.hasVotedInCurrentCycle(voter1), "Voter1 should have voted in current cycle");

        // Verify nonce was used
        assertTrue(votingModule.isNonceUsed(voter1, nonce));
    }

    function testBatchVoting() public {
        address[] memory voters = new address[](2);
        voters[0] = voter1;
        voters[1] = voter2;

        uint256[][] memory pointsArray = new uint256[][](2);
        pointsArray[0] = new uint256[](3);
        pointsArray[0][0] = 50;
        pointsArray[0][1] = 30;
        pointsArray[0][2] = 20;

        pointsArray[1] = new uint256[](3);
        pointsArray[1][0] = 60;
        pointsArray[1][1] = 25;
        pointsArray[1][2] = 15;

        uint256[] memory nonces = new uint256[](2);
        nonces[0] = 1;
        nonces[1] = 1;

        bytes[] memory signatures = new bytes[](2);

        // Create signatures
        bytes32 digest1 = _createVoteDigest(voter1, pointsArray[0], nonces[0]);
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(voter1PrivateKey, digest1);
        signatures[0] = abi.encodePacked(r1, s1, v1);

        bytes32 digest2 = _createVoteDigest(voter2, pointsArray[1], nonces[1]);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(voter2PrivateKey, digest2);
        signatures[1] = abi.encodePacked(r2, s2, v2);

        // Cast batch votes
        vm.expectEmit(false, false, false, true);
        emit BatchVotesCast(voters, nonces);

        votingModule.castBatchVotesWithSignature(voters, pointsArray, nonces, signatures);

        // Verify both votes were recorded
        assertTrue(votingModule.hasVotedInCurrentCycle(voter1), "Voter1 should have voted in current cycle");
        assertTrue(votingModule.hasVotedInCurrentCycle(voter2), "Voter2 should have voted in current cycle");
    }

    function testVoteRecasting() public {
        uint256[] memory points1 = new uint256[](3);
        points1[0] = 50;
        points1[1] = 30;
        points1[2] = 20;

        // First vote with signature
        uint256 nonce1 = 1;
        bytes memory signature1 = createVoteSignature(voter1, voter1PrivateKey, points1, nonce1);
        votingModule.castVoteWithSignature(voter1, points1, nonce1, signature1);

        // Verify vote was recorded
        assertTrue(votingModule.hasVotedInCurrentCycle(voter1), "Voter1 should have voted in current cycle");

        // Get voting power for calculations
        uint256 votingPower = votingModule.getVotingPower(voter1);

        // Get initial distribution and verify it matches expected values
        uint256[] memory dist1 = votingModule.getCurrentVotingDistribution();
        uint256 totalPoints1 = 100; // 50 + 30 + 20
        assertEq(
            dist1[0], (50 * votingPower * 1e18) / totalPoints1 / 1e18, "First project should have correct allocation"
        );
        assertEq(
            dist1[1], (30 * votingPower * 1e18) / totalPoints1 / 1e18, "Second project should have correct allocation"
        );
        assertEq(
            dist1[2], (20 * votingPower * 1e18) / totalPoints1 / 1e18, "Third project should have correct allocation"
        );

        // Advance block to ensure timestamps differ
        vm.roll(block.number + 1);

        // Cast second vote with different distribution - should succeed and add to existing votes
        uint256[] memory points2 = new uint256[](3);
        points2[0] = 60;
        points2[1] = 25;
        points2[2] = 15;

        // Second vote should succeed since recasting is allowed
        uint256 nonce2 = 2;
        bytes memory signature2 = createVoteSignature(voter1, voter1PrivateKey, points2, nonce2);
        votingModule.castVoteWithSignature(voter1, points2, nonce2, signature2);

        // Verify the vote was replaced, not added (second vote replaces first)
        uint256[] memory dist2 = votingModule.getCurrentVotingDistribution();
        uint256 totalPoints2 = 100; // 60 + 25 + 15
        assertEq(dist2[0], (60 * votingPower * 1e18) / totalPoints2 / 1e18, "First project should have new allocation");
        assertEq(dist2[1], (25 * votingPower * 1e18) / totalPoints2 / 1e18, "Second project should have new allocation");
        assertEq(dist2[2], (15 * votingPower * 1e18) / totalPoints2 / 1e18, "Third project should have new allocation");
    }

    function testNonceReplayProtection() public {
        uint256[] memory points = new uint256[](3);
        points[0] = 50;
        points[1] = 30;
        points[2] = 20;

        uint256 nonce = 1;

        // Create signature
        bytes32 digest = _createVoteDigest(voter1, points, nonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(voter1PrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // First vote should succeed
        votingModule.castVoteWithSignature(voter1, points, nonce, signature);

        // Second vote with same nonce should fail
        vm.expectRevert(IVotingModule.NonceAlreadyUsed.selector);
        votingModule.castVoteWithSignature(voter1, points, nonce, signature);
    }

    function testInvalidSignature() public {
        uint256[] memory points = new uint256[](3);
        points[0] = 50;
        points[1] = 30;
        points[2] = 20;

        uint256 nonce = 1;

        // Create signature with wrong private key
        bytes32 digest = _createVoteDigest(voter1, points, nonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(voter2PrivateKey, digest); // Wrong key
        bytes memory signature = abi.encodePacked(r, s, v);

        // Vote should fail
        vm.expectRevert(IVotingModule.InvalidSignature.selector);
        votingModule.castVoteWithSignature(voter1, points, nonce, signature);
    }

    function testZeroVotingPower() public {
        // Create account with no tokens
        uint256 noTokensVoterPrivateKey = 0x999;
        address noTokensVoter = vm.addr(noTokensVoterPrivateKey);

        uint256[] memory points = new uint256[](3);
        points[0] = 50;
        points[1] = 30;
        points[2] = 20;

        // Vote with zero voting power should succeed but have no effect
        uint256 nonce = 1;
        bytes memory signature = createVoteSignature(noTokensVoter, noTokensVoterPrivateKey, points, nonce);
        votingModule.castVoteWithSignature(noTokensVoter, points, nonce, signature);

        // Verify vote was recorded but with zero power
        assertTrue(
            votingModule.hasVotedInCurrentCycle(noTokensVoter), "NoTokensVoter should have voted in current cycle"
        );
    }

    function testExceedsMaxPoints() public {
        uint256[] memory points = new uint256[](3);
        points[0] = MAX_POINTS + 1; // Exceeds max
        points[1] = 50;
        points[2] = 50;

        uint256 nonce = 1;
        bytes memory signature = createVoteSignature(voter1, voter1PrivateKey, points, nonce);
        vm.expectRevert(IVotingModule.ExceedsMaxPoints.selector);
        votingModule.castVoteWithSignature(voter1, points, nonce, signature);
    }

    function testZeroVotePoints() public {
        uint256[] memory points = new uint256[](3);
        points[0] = 0;
        points[1] = 0;
        points[2] = 0;

        uint256 nonce = 1;
        bytes memory signature = createVoteSignature(voter1, voter1PrivateKey, points, nonce);
        vm.expectRevert(IVotingModule.ZeroVotePoints.selector);
        votingModule.castVoteWithSignature(voter1, points, nonce, signature);
    }

    function testValidateSignature() public view {
        uint256[] memory points = new uint256[](3);
        points[0] = 50;
        points[1] = 30;
        points[2] = 20;

        uint256 nonce = 1;

        // Create valid signature
        bytes32 digest = _createVoteDigest(voter1, points, nonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(voter1PrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Should return true for valid signature
        assertTrue(votingModule.validateSignature(voter1, points, nonce, signature));

        // Should return false for wrong voter
        assertFalse(votingModule.validateSignature(voter2, points, nonce, signature));
    }

    function testGetVotingPower() public view {
        uint256 power = votingModule.getVotingPower(voter1);
        assertGt(power, 0);

        // Voter1 should have more power than voter2
        uint256 power2 = votingModule.getVotingPower(voter2);
        assertGt(power, power2);
    }

    function testNewCycle() public {
        // Vote in cycle 1
        uint256[] memory points = new uint256[](3);
        points[0] = 50;
        points[1] = 30;
        points[2] = 20;

        uint256 nonce1 = 1;
        bytes memory signature1 = createVoteSignature(voter1, voter1PrivateKey, points, nonce1);
        votingModule.castVoteWithSignature(voter1, points, nonce1, signature1);

        // Advance blocks to complete the cycle (1000 blocks per cycle)
        vm.roll(block.number + 1000);

        // Start new cycle
        cycleModule.startNewCycle();
        assertEq(cycleModule.getCurrentCycle(), 2);

        // Vote in cycle 2 with signature
        uint256 nonce2 = 1;
        bytes memory signature2 = createVoteSignature(voter2, voter2PrivateKey, points, nonce2);
        votingModule.castVoteWithSignature(voter2, points, nonce2, signature2);

        // Check that votes are recorded properly - voter1 voted in cycle 1, voter2 in cycle 2
        // Since we're now in cycle 2, voter1 should not be in current cycle but voter2 should be
        assertFalse(votingModule.hasVotedInCurrentCycle(voter1), "Voter1 should not have voted in current cycle");
        assertTrue(votingModule.hasVotedInCurrentCycle(voter2), "Voter2 should have voted in current cycle");
        assertEq(cycleModule.getCurrentCycle(), 2);
    }

    function testNonceSkipping() public {
        uint256[] memory points = new uint256[](3);
        points[0] = 50;
        points[1] = 30;
        points[2] = 20;

        // Use nonce 5 (skipping 1-4)
        uint256 nonce = 5;

        bytes32 digest = _createVoteDigest(voter1, points, nonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(voter1PrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Should succeed even though nonces 1-4 weren't used
        votingModule.castVoteWithSignature(voter1, points, nonce, signature);
        assertTrue(votingModule.isNonceUsed(voter1, nonce));

        // Nonces 1-4 should still be available
        assertFalse(votingModule.isNonceUsed(voter1, 1));
        assertFalse(votingModule.isNonceUsed(voter1, 2));
        assertFalse(votingModule.isNonceUsed(voter1, 3));
        assertFalse(votingModule.isNonceUsed(voter1, 4));
    }

    // Helper functions

    function _createVoteDigest(address voter, uint256[] memory points, uint256 nonce) internal view returns (bytes32) {
        bytes32 voteTypehash = keccak256("Vote(address voter,bytes32 pointsHash,uint256 nonce)");

        bytes32 structHash = keccak256(abi.encode(voteTypehash, voter, keccak256(abi.encodePacked(points)), nonce));

        return keccak256(abi.encodePacked("\x19\x01", votingModule.DOMAIN_SEPARATOR(), structHash));
    }
}
