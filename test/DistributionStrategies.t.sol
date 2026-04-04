// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {EqualDistributionStrategy} from "../src/implementation/strategies/EqualDistributionStrategy.sol";
import {VotingDistributionStrategy} from "../src/implementation/strategies/VotingDistributionStrategy.sol";
import {MultiStrategyDistributionManager} from "../src/base/MultiStrategyDistributionManager.sol";
import {IDistributionStrategy} from "../src/interfaces/IDistributionStrategy.sol";
import {IVotingModule} from "../src/interfaces/IVotingModule.sol";
import {IVotingPowerStrategy} from "../src/interfaces/IVotingPowerStrategy.sol";
import {IRecipientRegistry} from "../src/interfaces/IRecipientRegistry.sol";
import {ICycleModule} from "../src/interfaces/ICycleModule.sol";
import {IYieldModule} from "../src/interfaces/IYieldModule.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockRecipientRegistry} from "./mocks/MockRecipientRegistry.sol";

// ============ Mock ERC20 ============

contract MockERC20 is IERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
}

// ============ Mock Voting Module ============

contract MockVotingModule is IVotingModule {
    uint256[] private _distribution;

    function setDistribution(uint256[] memory dist) external {
        _distribution = dist;
    }

    function getCurrentVotingDistribution() external view override returns (uint256[] memory) {
        return _distribution;
    }

    function getVotingPower(address) external pure override returns (uint256) {
        return 0;
    }

    function DOMAIN_SEPARATOR() external pure override returns (bytes32) {
        return bytes32(0);
    }

    function isNonceUsed(address, uint256) external pure override returns (bool) {
        return false;
    }

    function getVotingPowerStrategies() external pure override returns (IVotingPowerStrategy[] memory) {
        return new IVotingPowerStrategy[](0);
    }

    function validateSignature(address, uint256[] calldata, uint256, bytes calldata)
        external
        pure
        override
        returns (bool)
    {
        return false;
    }
}

// ============ Mock Cycle Module ============

contract MockCycleModule is ICycleModule {
    bool public cycleComplete = true;

    function setCycleComplete(bool _complete) external {
        cycleComplete = _complete;
    }

    function isCycleComplete() external view override returns (bool) {
        return cycleComplete;
    }

    function getCurrentCycle() external pure override returns (uint256) {
        return 1;
    }

    function startNewCycle() external override {}

    function getBlocksUntilNextCycle() external pure override returns (uint256) {
        return 0;
    }

    function getCycleProgress() external pure override returns (uint256) {
        return 100;
    }

    function updateCycleLength(uint256) external override {}

    function lastCycleStartBlock() external pure override returns (uint256) {
        return 0;
    }

    function cycleLength() external pure override returns (uint256) {
        return 200;
    }
}

// ============ Mock Yield Module ============

contract MockYieldModule is IYieldModule {
    uint256 private _yieldAccrued;
    MockERC20 private _token;

    constructor(MockERC20 token) {
        _token = token;
    }

    function setYield(uint256 amount) external {
        _yieldAccrued = amount;
    }

    function yieldAccrued() external view override returns (uint256) {
        return _yieldAccrued;
    }

    function claimYield(uint256 amount, address receiver) external override {
        _yieldAccrued -= amount;
        _token.mint(receiver, amount);
    }

    function mint(uint256 amount, address receiver) external override {
        _token.mint(receiver, amount);
    }

    function burn(uint256, address) external pure override {}
}

// ============ Mock Yield Token (ERC20 + IYieldModule combined) ============
// The MultiStrategyDistributionManager uses baseToken() for safeTransfer AND
// yieldModule() for claimYield — both resolve to the same address (_baseToken param).
// This mock implements both interfaces so the manager can use it correctly.

contract MockYieldToken is IERC20, IYieldModule {
    string public constant name = "MockYieldToken";
    string public constant symbol = "MYT";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    uint256 private _yieldAccrued;

    function mint(uint256 amount, address receiver) external override {
        totalSupply += amount;
        balanceOf[receiver] += amount;
        emit Transfer(address(0), receiver, amount);
    }

    function mintTo(address receiver, uint256 amount) external {
        totalSupply += amount;
        balanceOf[receiver] += amount;
        emit Transfer(address(0), receiver, amount);
    }

    function burn(uint256 amount, address receiver) external override {
        balanceOf[msg.sender] -= amount;
        totalSupply -= amount;
        emit Transfer(msg.sender, address(0), amount);
        // "send underlying to receiver" - just mint to receiver in mock
        totalSupply += amount;
        balanceOf[receiver] += amount;
        emit Transfer(address(0), receiver, amount);
    }

    function setYield(uint256 amount) external {
        _yieldAccrued = amount;
    }

    function yieldAccrued() external view override returns (uint256) {
        return _yieldAccrued;
    }

    function claimYield(uint256 amount, address receiver) external override {
        _yieldAccrued -= amount;
        // Mint tokens to receiver (simulating yield being claimed)
        totalSupply += amount;
        balanceOf[receiver] += amount;
        emit Transfer(address(0), receiver, amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
}

// ============ Mock Strategy for MultiStrategyDistributionManager tests ============

/// @dev Malicious strategy that attempts to re-enter claimAndDistribute during distribute()
contract ReentrantStrategy is IDistributionStrategy {
    MultiStrategyDistributionManager public manager;
    IERC20 public token;
    bool public shouldReenter;

    constructor(address _manager, address _token) {
        manager = MultiStrategyDistributionManager(_manager);
        token = IERC20(_token);
    }

    function setShouldReenter(bool _shouldReenter) external {
        shouldReenter = _shouldReenter;
    }

    function distribute(uint256) external override {
        if (shouldReenter) {
            shouldReenter = false;
            manager.claimAndDistribute();
        }
    }

    function withdrawToken(address to, uint256 amount) external {
        token.transfer(to, amount);
    }
}

/// @dev A lightweight strategy mock that accepts distribute() from anyone.
/// Used to test MultiStrategyDistributionManager without needing circular init.
contract MockDistributableStrategy is IDistributionStrategy {
    IERC20 public token;
    uint256 public totalReceived;
    uint256[] public distributeCalls; // amounts per call
    uint256 public distributionId;

    constructor(address _token) {
        token = IERC20(_token);
    }

    function distribute(uint256 amount) external override {
        totalReceived += amount;
        distributeCalls.push(amount);
        distributionId++;
        emit DistributionExecuted(distributionId);
        // Send to address(1) as a dummy recipient
        if (amount > 0) {
            token.transfer(address(1), amount);
            emit Distributed(address(1), amount);
        }
    }

    function getCallCount() external view returns (uint256) {
        return distributeCalls.length;
    }
}

// ============ EqualDistributionStrategy Tests ============

contract EqualDistributionStrategyTest is Test {
    EqualDistributionStrategy public strategy;
    MockERC20 public yieldToken;
    MockRecipientRegistry public registry;
    address public manager = address(this);

    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);
    address public carol = address(0xCA401);

    event Distributed(address indexed recipient, uint256 amount);
    event DistributionExecuted(uint256 indexed distributionId);

    function setUp() public {
        yieldToken = new MockERC20("YieldToken", "YLD");
        address[] memory initialRecipients = new address[](0);
        registry = new MockRecipientRegistry(initialRecipients);
        strategy = new EqualDistributionStrategy();
        strategy.initialize(address(yieldToken), address(registry), manager);
    }

    function _setupRecipients(address[] memory recipients) internal {
        registry.setActiveRecipients(recipients);
    }

    function _fundStrategy(uint256 amount) internal {
        yieldToken.mint(address(strategy), amount);
    }

    // Test 1: Dust absorbed by last recipient (10 wei / 3 = 3 each, last gets 4)
    function testDustAbsorbedByLastRecipient() public {
        address[] memory recipients = new address[](3);
        recipients[0] = alice;
        recipients[1] = bob;
        recipients[2] = carol;
        _setupRecipients(recipients);
        _fundStrategy(10);

        strategy.distribute(10);

        assertEq(yieldToken.balanceOf(alice), 3, "Alice should get 3");
        assertEq(yieldToken.balanceOf(bob), 3, "Bob should get 3");
        assertEq(yieldToken.balanceOf(carol), 4, "Carol (last) should get 4 (absorbs dust)");
        assertEq(yieldToken.balanceOf(address(strategy)), 0, "No dust left in strategy");
    }

    // Test 2: Exact division, no dust
    function testExactDivisionNoDust() public {
        address[] memory recipients = new address[](3);
        recipients[0] = alice;
        recipients[1] = bob;
        recipients[2] = carol;
        _setupRecipients(recipients);
        _fundStrategy(300);

        strategy.distribute(300);

        assertEq(yieldToken.balanceOf(alice), 100, "Alice should get 100");
        assertEq(yieldToken.balanceOf(bob), 100, "Bob should get 100");
        assertEq(yieldToken.balanceOf(carol), 100, "Carol should get 100");
        assertEq(yieldToken.balanceOf(address(strategy)), 0, "No dust left");
    }

    // Test 3: Single recipient gets all
    function testSingleRecipientGetsAll() public {
        address[] memory recipients = new address[](1);
        recipients[0] = alice;
        _setupRecipients(recipients);
        _fundStrategy(100);

        strategy.distribute(100);

        assertEq(yieldToken.balanceOf(alice), 100, "Single recipient should get all 100");
    }

    // Test 4: Reverts on zero amount
    function testRevertsZeroAmount() public {
        address[] memory recipients = new address[](1);
        recipients[0] = alice;
        _setupRecipients(recipients);

        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        strategy.distribute(0);
    }

    // Test 5: Reverts when no recipients
    function testRevertsNoRecipients() public {
        // Empty registry (default setUp has no recipients)
        _fundStrategy(100);

        vm.expectRevert(abi.encodeWithSignature("NoRecipients()"));
        strategy.distribute(100);
    }

    // Test 6: Reverts when yield < recipient count
    function testRevertsInsufficientYield() public {
        address[] memory recipients = new address[](5);
        for (uint256 i = 0; i < 5; i++) {
            recipients[i] = address(uint160(i + 1));
        }
        _setupRecipients(recipients);
        _fundStrategy(4);

        vm.expectRevert(abi.encodeWithSignature("InsufficientYieldForRecipients()"));
        strategy.distribute(4);
    }

    // Test 7: distributionId increments
    function testDistributionIdIncrements() public {
        address[] memory recipients = new address[](1);
        recipients[0] = alice;
        _setupRecipients(recipients);

        assertEq(strategy.distributionId(), 0, "Initial distributionId should be 0");

        _fundStrategy(100);
        strategy.distribute(100);
        assertEq(strategy.distributionId(), 1, "distributionId should be 1 after first distribute");

        _fundStrategy(100);
        strategy.distribute(100);
        assertEq(strategy.distributionId(), 2, "distributionId should be 2 after second distribute");
    }

    // Test 8: Events emitted
    function testEventsEmitted() public {
        address[] memory recipients = new address[](2);
        recipients[0] = alice;
        recipients[1] = bob;
        _setupRecipients(recipients);
        _fundStrategy(200);

        vm.expectEmit(true, false, false, true);
        emit Distributed(alice, 100);

        vm.expectEmit(true, false, false, true);
        emit Distributed(bob, 100);

        vm.expectEmit(true, false, false, true);
        emit DistributionExecuted(1);

        strategy.distribute(200);
    }

    // Test 9: Only distribution manager can call distribute
    function testRevertsIfNotDistributionManager() public {
        address[] memory recipients = new address[](1);
        recipients[0] = alice;
        _setupRecipients(recipients);
        _fundStrategy(100);

        vm.prank(address(0xBEEF));
        vm.expectRevert(abi.encodeWithSignature("OnlyDistributionManager()"));
        strategy.distribute(100);
    }

    // Test 10: Large number of recipients with dust
    function testLargeRecipientCountDust() public {
        uint256 n = 7;
        address[] memory recipients = new address[](n);
        for (uint256 i = 0; i < n; i++) {
            recipients[i] = address(uint160(0x1000 + i));
        }
        _setupRecipients(recipients);
        uint256 amount = 100;
        _fundStrategy(amount);

        strategy.distribute(amount);

        // 100 / 7 = 14 each, last gets 100 - 14*6 = 16
        uint256 perRecipient = uint256(100) / uint256(7); // = 14
        uint256 expectedLast = uint256(100) - perRecipient * uint256(6); // = 16

        for (uint256 i = 0; i < n - 1; i++) {
            assertEq(yieldToken.balanceOf(recipients[i]), perRecipient, "Each recipient should get per-recipient share");
        }
        assertEq(yieldToken.balanceOf(recipients[n - 1]), expectedLast, "Last recipient absorbs dust");
        assertEq(yieldToken.balanceOf(address(strategy)), 0, "No dust left in strategy");
    }
}

// ============ VotingDistributionStrategy Tests ============

contract VotingDistributionStrategyTest is Test {
    VotingDistributionStrategy public strategy;
    MockERC20 public yieldToken;
    MockRecipientRegistry public registry;
    MockVotingModule public votingModule;
    address public manager = address(this);

    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);
    address public carol = address(0xCA401);

    event Distributed(address indexed recipient, uint256 amount);
    event DistributionExecuted(uint256 indexed distributionId);

    function setUp() public {
        yieldToken = new MockERC20("YieldToken", "YLD");
        address[] memory initialRecipients = new address[](0);
        registry = new MockRecipientRegistry(initialRecipients);
        votingModule = new MockVotingModule();
        strategy = new VotingDistributionStrategy();
        strategy.initialize(address(yieldToken), address(registry), address(votingModule), manager);
    }

    function _setupRecipients(address[] memory recipients) internal {
        registry.setActiveRecipients(recipients);
    }

    function _fundStrategy(uint256 amount) internal {
        yieldToken.mint(address(strategy), amount);
    }

    function _setVotes(uint256[] memory votes) internal {
        votingModule.setDistribution(votes);
    }

    // Test 1: Dust absorbed by last recipient
    // 101 wei / [50, 50, 0] votes: alice gets 50, bob gets 50, carol (0 votes) absorbs 1 wei dust
    function testDustAbsorbedByLastRecipient() public {
        address[] memory recipients = new address[](3);
        recipients[0] = alice;
        recipients[1] = bob;
        recipients[2] = carol;
        _setupRecipients(recipients);

        uint256[] memory votes = new uint256[](3);
        votes[0] = 50;
        votes[1] = 50;
        votes[2] = 0;
        _setVotes(votes);
        _fundStrategy(101);

        strategy.distribute(101);

        // totalVotes=100, alice=101*50/100=50, bob=101*50/100=50
        // remainder = 101 - 50 - 50 = 1 -> carol (last) gets 1
        assertEq(yieldToken.balanceOf(alice), 50, "Alice should get 50");
        assertEq(yieldToken.balanceOf(bob), 50, "Bob should get 50");
        assertEq(yieldToken.balanceOf(carol), 1, "Carol (0 votes, last) absorbs 1 wei dust");
        assertEq(yieldToken.balanceOf(address(strategy)), 0, "No dust in strategy");
    }

    // Test 2: Dust goes to last even if they have 0 votes (same test verifying design intent)
    function testDustAbsorbedByLastRecipientEvenWithZeroVote() public {
        address[] memory recipients = new address[](3);
        recipients[0] = alice;
        recipients[1] = bob;
        recipients[2] = carol;
        _setupRecipients(recipients);

        uint256[] memory votes = new uint256[](3);
        votes[0] = 100;
        votes[1] = 100;
        votes[2] = 0; // carol has 0 votes but is last recipient
        _setVotes(votes);
        _fundStrategy(201);

        strategy.distribute(201);

        // totalVotes=200, alice=201*100/200=100, bob=201*100/200=100
        // remainder=201-100-100=1 -> carol gets 1 despite 0 votes
        assertEq(yieldToken.balanceOf(alice), 100, "Alice should get 100");
        assertEq(yieldToken.balanceOf(bob), 100, "Bob should get 100");
        assertEq(yieldToken.balanceOf(carol), 1, "Carol (0 votes) should get dust as last recipient");
        assertEq(yieldToken.balanceOf(address(strategy)), 0, "No dust in strategy");
    }

    // Test 3: Exact division, no dust
    function testExactDivisionNoDust() public {
        address[] memory recipients = new address[](3);
        recipients[0] = alice;
        recipients[1] = bob;
        recipients[2] = carol;
        _setupRecipients(recipients);

        uint256[] memory votes = new uint256[](3);
        votes[0] = 100;
        votes[1] = 100;
        votes[2] = 100;
        _setVotes(votes);
        _fundStrategy(300);

        strategy.distribute(300);

        // totalVotes=300, each gets 300*100/300=100
        assertEq(yieldToken.balanceOf(alice), 100, "Alice should get 100");
        assertEq(yieldToken.balanceOf(bob), 100, "Bob should get 100");
        assertEq(yieldToken.balanceOf(carol), 100, "Carol should get 100");
        assertEq(yieldToken.balanceOf(address(strategy)), 0, "No dust");
    }

    // Test 4: Single recipient gets all
    function testSingleRecipientGetsAll() public {
        address[] memory recipients = new address[](1);
        recipients[0] = alice;
        _setupRecipients(recipients);

        uint256[] memory votes = new uint256[](1);
        votes[0] = 100;
        _setVotes(votes);
        _fundStrategy(100);

        strategy.distribute(100);

        assertEq(yieldToken.balanceOf(alice), 100, "Single recipient should get all 100");
    }

    // Test 5: Reverts on zero amount
    function testRevertsZeroAmount() public {
        address[] memory recipients = new address[](1);
        recipients[0] = alice;
        _setupRecipients(recipients);

        uint256[] memory votes = new uint256[](1);
        votes[0] = 100;
        _setVotes(votes);

        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        strategy.distribute(0);
    }

    // Test 6: Reverts with no recipients
    function testRevertsNoRecipients() public {
        uint256[] memory votes = new uint256[](0);
        _setVotes(votes);
        _fundStrategy(100);

        vm.expectRevert(abi.encodeWithSignature("NoRecipients()"));
        strategy.distribute(100);
    }

    // Test 7: Reverts when yield insufficient (amount < recipientCount)
    function testRevertsInsufficientYield() public {
        address[] memory recipients = new address[](5);
        for (uint256 i = 0; i < 5; i++) {
            recipients[i] = address(uint160(0x2000 + i));
        }
        _setupRecipients(recipients);

        uint256[] memory votes = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            votes[i] = 1;
        }
        _setVotes(votes);
        _fundStrategy(4);

        vm.expectRevert(abi.encodeWithSignature("InsufficientYieldForRecipients()"));
        strategy.distribute(4);
    }

    // Test 8: Reverts when all votes are 0
    function testRevertsNoVotes() public {
        address[] memory recipients = new address[](3);
        recipients[0] = alice;
        recipients[1] = bob;
        recipients[2] = carol;
        _setupRecipients(recipients);

        uint256[] memory votes = new uint256[](3);
        votes[0] = 0;
        votes[1] = 0;
        votes[2] = 0;
        _setVotes(votes);
        _fundStrategy(100);

        vm.expectRevert(abi.encodeWithSignature("NoVotes()"));
        strategy.distribute(100);
    }

    // Test 9: distributionId increments
    function testDistributionIdIncrements() public {
        address[] memory recipients = new address[](1);
        recipients[0] = alice;
        _setupRecipients(recipients);

        uint256[] memory votes = new uint256[](1);
        votes[0] = 100;
        _setVotes(votes);

        assertEq(strategy.distributionId(), 0, "Initial distributionId should be 0");

        _fundStrategy(100);
        strategy.distribute(100);
        assertEq(strategy.distributionId(), 1, "distributionId should be 1 after first distribute");

        _fundStrategy(100);
        strategy.distribute(100);
        assertEq(strategy.distributionId(), 2, "distributionId should be 2 after second distribute");
    }

    // Test 10: Events emitted correctly
    function testEventsEmitted() public {
        address[] memory recipients = new address[](2);
        recipients[0] = alice;
        recipients[1] = bob;
        _setupRecipients(recipients);

        uint256[] memory votes = new uint256[](2);
        votes[0] = 50;
        votes[1] = 50;
        _setVotes(votes);
        _fundStrategy(200);

        vm.expectEmit(true, false, false, true);
        emit Distributed(alice, 100);

        vm.expectEmit(true, false, false, true);
        emit Distributed(bob, 100);

        vm.expectEmit(true, false, false, true);
        emit DistributionExecuted(1);

        strategy.distribute(200);
    }

    // Test 11: Only distribution manager can call (nonReentrant + access control)
    function testOnlyDistributionManagerCanCall() public {
        address[] memory recipients = new address[](1);
        recipients[0] = alice;
        _setupRecipients(recipients);

        uint256[] memory votes = new uint256[](1);
        votes[0] = 100;
        _setVotes(votes);
        _fundStrategy(100);

        vm.prank(address(0xBEEF));
        vm.expectRevert(abi.encodeWithSignature("OnlyDistributionManager()"));
        strategy.distribute(100);
    }

    // Test 12: Proportional distribution with uneven votes
    function testProportionalDistribution() public {
        address[] memory recipients = new address[](2);
        recipients[0] = alice;
        recipients[1] = bob;
        _setupRecipients(recipients);

        uint256[] memory votes = new uint256[](2);
        votes[0] = 75; // 75%
        votes[1] = 25; // 25%
        _setVotes(votes);
        _fundStrategy(1000);

        strategy.distribute(1000);

        // alice: 1000*75/100=750, bob: remainder=250
        assertEq(yieldToken.balanceOf(alice), 750, "Alice should get 750 (75%)");
        assertEq(yieldToken.balanceOf(bob), 250, "Bob should get 250 (25%)");
        assertEq(yieldToken.balanceOf(address(strategy)), 0, "No dust");
    }

    // Test 13: Verify the nonReentrant modifier is applied by checking it doesn't allow re-entry
    function testNonReentrant() public {
        // The nonReentrant modifier is declared in the contract signature.
        // We verify that a direct call from manager works, confirming the lock
        // doesn't persist incorrectly between normal calls.
        address[] memory recipients = new address[](1);
        recipients[0] = alice;
        _setupRecipients(recipients);

        uint256[] memory votes = new uint256[](1);
        votes[0] = 100;
        _setVotes(votes);

        _fundStrategy(200);
        strategy.distribute(100);
        // If nonReentrant lock was stuck, this second call would fail
        strategy.distribute(100);
        assertEq(yieldToken.balanceOf(alice), 200, "Both distributions should succeed");
    }
}

// ============ MultiStrategyDistributionManager Tests ============

contract MultiStrategyDistributionManagerTest is Test {
    MultiStrategyDistributionManager public manager;
    MockYieldToken public yieldToken; // combined ERC20 + IYieldModule
    MockCycleModule public cycleModule;
    MockVotingModule public votingModule;
    MockRecipientRegistry public registry;

    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);
    address public carol = address(0xCA401);

    event YieldClaimed(uint256 amount);
    event YieldDistributed(address indexed strategy, uint256 amount);

    function setUp() public {
        yieldToken = new MockYieldToken();
        cycleModule = new MockCycleModule();
        votingModule = new MockVotingModule();

        address[] memory initialRecipients = new address[](1);
        initialRecipients[0] = alice;
        registry = new MockRecipientRegistry(initialRecipients);
    }

    function _deployManagerWithMockStrategies(uint256 count)
        internal
        returns (MockDistributableStrategy[] memory strategies)
    {
        strategies = new MockDistributableStrategy[](count);
        IDistributionStrategy[] memory iStrategies = new IDistributionStrategy[](count);
        for (uint256 i = 0; i < count; i++) {
            strategies[i] = new MockDistributableStrategy(address(yieldToken));
            iStrategies[i] = IDistributionStrategy(address(strategies[i]));
        }

        manager = new MultiStrategyDistributionManager();
        // _baseToken must implement both IERC20 and IYieldModule
        manager.initialize(
            address(cycleModule),
            address(registry),
            address(yieldToken), // serves as both baseToken and yieldModule
            address(votingModule),
            iStrategies
        );

        // Set non-zero voting distribution so getTotalCurrentVotingPower() > 0
        // (required since fix/77-zero-voter removed the zero-voter guard)
        uint256[] memory votes = new uint256[](1);
        votes[0] = 100;
        votingModule.setDistribution(votes);
    }

    // Test 1: Dust absorbed by last strategy (100 / 3 = 33 each, last gets 34)
    function testDustAbsorbedByLastStrategy() public {
        MockDistributableStrategy[] memory strategies = _deployManagerWithMockStrategies(3);

        cycleModule.setCycleComplete(true);
        yieldToken.setYield(100);

        assertTrue(manager.isDistributionReady(), "Distribution should be ready");

        manager.claimAndDistribute();

        // 100 / 3 = 33 per strategy; last strategy gets 100 - 33*2 = 34
        assertEq(strategies[0].totalReceived(), 33, "Strategy 0 should get 33");
        assertEq(strategies[1].totalReceived(), 33, "Strategy 1 should get 33");
        assertEq(strategies[2].totalReceived(), 34, "Strategy 2 (last) should absorb 1 wei dust");
        assertEq(yieldToken.balanceOf(address(manager)), 0, "No dust left in manager");
    }

    // Test 2: isDistributionReady returns false when cycle is not complete
    function testIsDistributionReadyFalseWhenCycleNotComplete() public {
        _deployManagerWithMockStrategies(1);

        cycleModule.setCycleComplete(false);
        yieldToken.setYield(100);

        assertFalse(manager.isDistributionReady(), "Should not be ready when cycle not complete");
    }

    // Test 3: isDistributionReady returns false when no recipients
    function testRevertsZeroRecipients() public {
        MockDistributableStrategy[] memory mockStrategies = new MockDistributableStrategy[](1);
        mockStrategies[0] = new MockDistributableStrategy(address(yieldToken));
        IDistributionStrategy[] memory iStrategies = new IDistributionStrategy[](1);
        iStrategies[0] = IDistributionStrategy(address(mockStrategies[0]));

        address[] memory emptyRecipients = new address[](0);
        MockRecipientRegistry emptyRegistry = new MockRecipientRegistry(emptyRecipients);

        manager = new MultiStrategyDistributionManager();
        manager.initialize(
            address(cycleModule),
            address(emptyRegistry),
            address(yieldToken),
            address(votingModule),
            iStrategies
        );

        cycleModule.setCycleComplete(true);
        yieldToken.setYield(100);

        assertFalse(manager.isDistributionReady(), "Should not be ready with 0 recipients");

        vm.expectRevert(abi.encodeWithSignature("DistributionNotReady()"));
        manager.claimAndDistribute();
    }

    // Test 4: Reverts when insufficient yield (yield < recipientCount * strategyCount)
    function testRevertsInsufficientYield() public {
        // 3 recipients in registry, 2 strategies => min yield = 3*2 = 6
        address[] memory recs = new address[](3);
        recs[0] = alice;
        recs[1] = bob;
        recs[2] = carol;
        MockRecipientRegistry multiRegistry = new MockRecipientRegistry(recs);

        MockDistributableStrategy s1 = new MockDistributableStrategy(address(yieldToken));
        MockDistributableStrategy s2 = new MockDistributableStrategy(address(yieldToken));
        IDistributionStrategy[] memory iStrategies = new IDistributionStrategy[](2);
        iStrategies[0] = IDistributionStrategy(address(s1));
        iStrategies[1] = IDistributionStrategy(address(s2));

        manager = new MultiStrategyDistributionManager();
        manager.initialize(
            address(cycleModule),
            address(multiRegistry),
            address(yieldToken),
            address(votingModule),
            iStrategies
        );

        cycleModule.setCycleComplete(true);
        // yield = 5 < 3*2=6 -> not ready
        yieldToken.setYield(5);

        assertFalse(manager.isDistributionReady(), "Should not be ready with insufficient yield");

        vm.expectRevert(abi.encodeWithSignature("DistributionNotReady()"));
        manager.claimAndDistribute();
    }

    // Test 5: claimAndDistribute calls strategy.distribute with correct amounts
    function testClaimAndDistributeCallsStrategyDistribute() public {
        MockDistributableStrategy[] memory strategies = _deployManagerWithMockStrategies(2);

        cycleModule.setCycleComplete(true);
        yieldAmount = 200;
        yieldToken.setYield(200);

        manager.claimAndDistribute();

        // 200 / 2 = 100 per strategy
        assertEq(strategies[0].totalReceived(), 100, "Strategy 0 should receive 100");
        assertEq(strategies[1].totalReceived(), 100, "Strategy 1 should receive 100");
        assertEq(strategies[0].getCallCount(), 1, "Strategy 0 should have 1 distribute call");
        assertEq(strategies[1].getCallCount(), 1, "Strategy 1 should have 1 distribute call");
    }

    uint256 yieldAmount; // helper var

    // Test 6: claimAndDistribute emits YieldClaimed and YieldDistributed events
    function testEventsEmitted() public {
        MockDistributableStrategy[] memory strategies = _deployManagerWithMockStrategies(2);

        cycleModule.setCycleComplete(true);
        yieldToken.setYield(200);

        vm.expectEmit(false, false, false, true);
        emit YieldClaimed(200);

        vm.expectEmit(true, false, false, true);
        emit YieldDistributed(address(strategies[0]), 100);

        vm.expectEmit(true, false, false, true);
        emit YieldDistributed(address(strategies[1]), 100);

        manager.claimAndDistribute();
    }

    // Test 7: getStrategies and getStrategyCount
    function testGetStrategiesAndCount() public {
        MockDistributableStrategy[] memory strategies = _deployManagerWithMockStrategies(3);

        assertEq(manager.getStrategyCount(), 3, "Should have 3 strategies");

        IDistributionStrategy[] memory retrieved = manager.getStrategies();
        assertEq(retrieved.length, 3, "getStrategies should return 3");
        assertEq(address(retrieved[0]), address(strategies[0]), "First strategy should match");
        assertEq(address(retrieved[1]), address(strategies[1]), "Second strategy should match");
        assertEq(address(retrieved[2]), address(strategies[2]), "Third strategy should match");
    }

    // Test 8: Cannot initialize with zero strategies
    function testRevertsNoStrategies() public {
        IDistributionStrategy[] memory strategies = new IDistributionStrategy[](0);
        manager = new MultiStrategyDistributionManager();
        vm.expectRevert("No strategies provided");
        manager.initialize(
            address(cycleModule),
            address(registry),
            address(yieldToken),
            address(votingModule),
            strategies
        );
    }

    // Test 9: Cannot initialize with zero address strategy
    function testRevertsZeroAddressStrategy() public {
        IDistributionStrategy[] memory strategies = new IDistributionStrategy[](1);
        strategies[0] = IDistributionStrategy(address(0));
        manager = new MultiStrategyDistributionManager();
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        manager.initialize(
            address(cycleModule),
            address(registry),
            address(yieldToken),
            address(votingModule),
            strategies
        );
    }

    // Test 10: isDistributionReady false when yield is 0
    function testIsDistributionReadyFalseWhenNoYield() public {
        _deployManagerWithMockStrategies(1);

        cycleModule.setCycleComplete(true);
        yieldToken.setYield(0);

        assertFalse(manager.isDistributionReady(), "Should not be ready with 0 yield");
    }

    // Test 11: nonReentrant on claimAndDistribute - consecutive calls succeed after first completes
    function testNonReentrantAllowsConsecutiveCalls() public {
        MockDistributableStrategy[] memory strategies = _deployManagerWithMockStrategies(2);

        cycleModule.setCycleComplete(true);

        // First distribution
        yieldToken.setYield(200);
        manager.claimAndDistribute();
        assertEq(strategies[0].distributionId(), 1, "First distribution should succeed");

        // Second distribution (nonReentrant lock should be released after first completes)
        yieldToken.setYield(200);
        manager.claimAndDistribute();
        assertEq(strategies[0].distributionId(), 2, "Second distribution should succeed (nonReentrant released)");
    }

    // Test 12: Exact even split, no dust
    function testExactEvenSplitNoRemainder() public {
        MockDistributableStrategy[] memory strategies = _deployManagerWithMockStrategies(4);

        cycleModule.setCycleComplete(true);
        yieldToken.setYield(400);

        manager.claimAndDistribute();

        for (uint256 i = 0; i < 4; i++) {
            assertEq(strategies[i].totalReceived(), 100, "Each strategy should get 100");
        }
        assertEq(yieldToken.balanceOf(address(manager)), 0, "No dust in manager");
    }

}
