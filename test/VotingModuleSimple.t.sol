// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {BasisPointsVotingModule} from "../src/base/BasisPointsVotingModule.sol";
import {IVotingModule} from "../src/interfaces/IVotingModule.sol";
import {TokenBasedVotingPower} from "../src/implementation/strategies/TokenBasedVotingPower.sol";
import {IVotingPowerStrategy} from "../src/interfaces/IVotingPowerStrategy.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {MockRecipientRegistry} from "./mocks/MockRecipientRegistry.sol";
import {CycleModule} from "../src/implementation/CycleModule.sol";
import {MockDistributionModule} from "./mocks/MockDistributionModule.sol";

// Simple mock token for testing (non-upgradeable)
contract MockToken is IVotes {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => address) private _delegates;
    mapping(address => uint256) private _votingPower;

    uint256 private _totalSupply;
    string public name = "Mock Token";
    string public symbol = "MOCK";
    uint8 public decimals = 18;

    function mint(address receiver, uint256 amount) external {
        _mint(receiver, amount);
    }

    function _mint(address account, uint256 amount) internal {
        _totalSupply += amount;
        _balances[account] += amount;
        _votingPower[account] += amount;
        if (_delegates[account] == address(0)) {
            _delegates[account] = account;
        }
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        return true;
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        _allowances[from][msg.sender] -= amount;
        _balances[from] -= amount;
        _balances[to] += amount;
        return true;
    }

    function delegates(address account) external view override returns (address) {
        return _delegates[account] == address(0) ? account : _delegates[account];
    }

    function delegate(address delegatee) external override {
        _delegates[msg.sender] = delegatee;
    }

    function delegateBySig(address, uint256, uint256, uint8, bytes32, bytes32) external override {
        // Mock implementation - not needed for tests
    }

    function getVotes(address account) external view override returns (uint256) {
        return _votingPower[account];
    }

    function getPastVotes(address account, uint256) external view override returns (uint256) {
        return _votingPower[account];
    }

    function getPastTotalSupply(uint256) external view override returns (uint256) {
        return _totalSupply;
    }
}

contract VotingModuleSimpleTest is Test {
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
    uint256 public voter1PrivateKey;
    uint256 public voter2PrivateKey;

    // Events
    event VoteCast(address indexed voter, uint256[] points, uint256 votingPower, uint256 nonce, bytes signature);

    function setUp() public {
        // Setup test accounts
        owner = address(this);
        voter1PrivateKey = 0x1;
        voter2PrivateKey = 0x2;
        voter1 = vm.addr(voter1PrivateKey);
        voter2 = vm.addr(voter2PrivateKey);

        // Deploy mock token
        token = new MockToken();

        // Mint tokens to test accounts
        token.mint(voter1, 5 ether);
        token.mint(voter2, 3 ether);

        // Deploy voting power strategy
        tokenStrategy = new TokenBasedVotingPower(IVotes(address(token)));

        // Deploy mock recipient registry with 3 recipients
        address[] memory recipients = new address[](3);
        recipients[0] = address(0x1111);
        recipients[1] = address(0x2222);
        recipients[2] = address(0x3333);
        recipientRegistry = new MockRecipientRegistry(recipients);

        // Deploy and initialize voting module
        votingModule = new BasisPointsVotingModule();
        IVotingPowerStrategy[] memory strategies = new IVotingPowerStrategy[](1);
        strategies[0] = IVotingPowerStrategy(address(tokenStrategy));

        // Deploy mock distribution module
        distributionModule = new MockDistributionModule();

        // Deploy and initialize cycle module
        cycleModule = new CycleModule();
        cycleModule.initialize(1000); // 1000 blocks per cycle

        votingModule.initialize(
            MAX_POINTS, strategies, address(distributionModule), address(recipientRegistry), address(cycleModule)
        );
    }

    function testInitialization() public view {
        assertEq(votingModule.maxPoints(), MAX_POINTS);
        assertEq(cycleModule.getCurrentCycle(), 1);

        IVotingPowerStrategy[] memory strategies = votingModule.getVotingPowerStrategies();
        assertEq(strategies.length, 1);
        assertEq(address(strategies[0]), address(tokenStrategy));
    }

    function testDirectVoting() public {
        uint256[] memory points = new uint256[](3);
        points[0] = 50;
        points[1] = 30;
        points[2] = 20;

        // Create signature for voting
        uint256 nonce = 1;
        bytes32 digest = _createVoteDigest(voter1, points, nonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(voter1PrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        votingModule.castVoteWithSignature(voter1, points, nonce, signature);

        // Verify vote was recorded by checking project distributions
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

        // Verify vote was recorded by checking project distributions
        uint256[] memory projectDist = votingModule.getCurrentVotingDistribution();
        assertEq(projectDist.length, 3);

        // Verify nonce was used
        assertTrue(votingModule.isNonceUsed(voter1, nonce));
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

    function testIncorrectRecipientCount() public {
        // Try to vote with wrong number of points (2 instead of 3)
        uint256[] memory points = new uint256[](2);
        points[0] = 50;
        points[1] = 50;

        // Create signature and expect revert
        uint256 nonce = 1;
        bytes32 digest = _createVoteDigest(voter1, points, nonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(voter1PrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        vm.expectRevert(IVotingModule.InvalidPointsDistribution.selector);
        votingModule.castVoteWithSignature(voter1, points, nonce, signature);

        // Try with 4 points (too many)
        uint256[] memory points2 = new uint256[](4);
        points2[0] = 25;
        points2[1] = 25;
        points2[2] = 25;
        points2[3] = 25;

        // Create signature for second attempt and expect revert
        uint256 nonce2 = 2;
        bytes32 digest2 = _createVoteDigest(voter1, points2, nonce2);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(voter1PrivateKey, digest2);
        bytes memory signature2 = abi.encodePacked(r2, s2, v2);
        vm.expectRevert(IVotingModule.InvalidPointsDistribution.selector);
        votingModule.castVoteWithSignature(voter1, points2, nonce2, signature2);
    }

    function testValidRecipientCount() public {
        // Vote with correct number of points (3 recipients)
        uint256[] memory points = new uint256[](3);
        points[0] = 50;
        points[1] = 30;
        points[2] = 20;

        // Create signature for voting
        uint256 nonce = 1;
        bytes32 digest = _createVoteDigest(voter1, points, nonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(voter1PrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        votingModule.castVoteWithSignature(voter1, points, nonce, signature);

        // Check vote was recorded by checking project distributions
        uint256[] memory projectDist = votingModule.getCurrentVotingDistribution();
        assertEq(projectDist.length, 3);

        // Verify expected points length
        assertEq(votingModule.getExpectedPointsLength(), 3);
    }

    function testRecipientRegistryUpdate() public {
        // Add a new recipient
        address[] memory newRecipients = new address[](4);
        newRecipients[0] = address(0x1111);
        newRecipients[1] = address(0x2222);
        newRecipients[2] = address(0x3333);
        newRecipients[3] = address(0x4444);
        recipientRegistry.setActiveRecipients(newRecipients);

        // Now need 4 points
        uint256[] memory points = new uint256[](4);
        points[0] = 25;
        points[1] = 25;
        points[2] = 25;
        points[3] = 25;

        // Create signature for voting with 4 recipients
        uint256 nonce = 1;
        bytes32 digest = _createVoteDigest(voter1, points, nonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(voter1PrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        votingModule.castVoteWithSignature(voter1, points, nonce, signature);

        // Check vote was recorded with 4 points in project distributions
        uint256[] memory projectDist = votingModule.getCurrentVotingDistribution();
        assertEq(projectDist.length, 4);
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

    // Helper function
    function _createVoteDigest(address voter, uint256[] memory points, uint256 nonce) internal view returns (bytes32) {
        bytes32 voteTypehash = keccak256("Vote(address voter,bytes32 pointsHash,uint256 nonce)");

        bytes32 structHash = keccak256(abi.encode(voteTypehash, voter, keccak256(abi.encodePacked(points)), nonce));

        return keccak256(abi.encodePacked("\x19\x01", votingModule.DOMAIN_SEPARATOR(), structHash));
    }
}
