// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MultiplierVotingModule, IMultiplier} from "../src/implementation/MultiplierVotingModule.sol";
import {VotingStreakMultiplier} from "../src/implementation/multipliers/VotingStreakMultiplier.sol";
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

contract MockToken3 is ERC20, ERC20Votes, ERC20Permit {
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

contract MultiplierVotingModuleTest is Test {
    uint256 constant MAX_POINTS = 100;
    uint256 constant CYCLE_LENGTH = 100;

    MultiplierVotingModule public votingModule;
    VotingStreakMultiplier public streakMultiplier;
    TokenBasedVotingPower public tokenStrategy;
    MockToken3 public token;
    MockRecipientRegistry public recipientRegistry;
    CycleModule public cycleModule;

    address public voter1;
    uint256 public voter1PrivateKey;
    uint256 nextNonce = 1;

    function setUp() public {
        voter1PrivateKey = 0x1;
        voter1 = vm.addr(voter1PrivateKey);

        token = new MockToken3();
        token.mint(voter1, 10 ether);
        vm.prank(voter1);
        token.delegate(voter1);

        address[] memory recipients = new address[](3);
        recipients[0] = address(0x111);
        recipients[1] = address(0x222);
        recipients[2] = address(0x333);
        recipientRegistry = new MockRecipientRegistry(recipients);

        tokenStrategy = new TokenBasedVotingPower(IVotes(address(token)));

        cycleModule = new CycleModule();
        cycleModule.initialize(CYCLE_LENGTH);

        votingModule = new MultiplierVotingModule();
        streakMultiplier = new VotingStreakMultiplier(address(votingModule));

        IVotingPowerStrategy[] memory strategies = new IVotingPowerStrategy[](1);
        strategies[0] = IVotingPowerStrategy(address(tokenStrategy));

        address[] memory mults = new address[](1);
        mults[0] = address(streakMultiplier);

        votingModule.initialize(
            MAX_POINTS, strategies, address(0), address(recipientRegistry), address(cycleModule), mults
        );
    }

    // ============ Helpers ============

    function _points() internal pure returns (uint256[] memory) {
        uint256[] memory p = new uint256[](3);
        p[0] = 50;
        p[1] = 30;
        p[2] = 20;
        return p;
    }

    function _sign(uint256 pk, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _voteDigest(address voter, uint256[] memory pts, uint256 n) internal view returns (bytes32) {
        bytes32 th = keccak256("Vote(address voter,bytes32 pointsHash,uint256 nonce)");
        bytes32 sh = keccak256(abi.encode(th, voter, keccak256(abi.encodePacked(pts)), n));
        return keccak256(abi.encodePacked("\x19\x01", votingModule.DOMAIN_SEPARATOR(), sh));
    }

    function _paramsDigest(address voter, uint256[] memory pts, uint256 n, bytes memory params)
        internal
        view
        returns (bytes32)
    {
        bytes32 th = keccak256("VoteWithParams(address voter,bytes32 pointsHash,uint256 nonce,bytes32 paramsHash)");
        bytes32 sh = keccak256(abi.encode(th, voter, keccak256(abi.encodePacked(pts)), n, keccak256(params)));
        return keccak256(abi.encodePacked("\x19\x01", votingModule.DOMAIN_SEPARATOR(), sh));
    }

    function _streakParams() internal pure returns (bytes memory) {
        uint256[] memory idx = new uint256[](1);
        idx[0] = 0;
        return abi.encode(idx);
    }

    function _voteWithMultiplier() internal {
        uint256[] memory pts = _points();
        bytes memory params = _streakParams();
        bytes memory sig = _sign(voter1PrivateKey, _paramsDigest(voter1, pts, nextNonce, params));
        votingModule.castVoteWithSignatureAndParams(voter1, pts, nextNonce, sig, params);
        nextNonce++;
    }

    function _voteNormal() internal {
        uint256[] memory pts = _points();
        bytes memory sig = _sign(voter1PrivateKey, _voteDigest(voter1, pts, nextNonce));
        votingModule.castVoteWithSignature(voter1, pts, nextNonce, sig);
        nextNonce++;
    }

    function _advanceCycle() internal {
        vm.roll(block.number + CYCLE_LENGTH);
        cycleModule.startNewCycle();
    }

    // ============ Streak Tests ============

    function testFirstVoteStartsStreak() public {
        _voteWithMultiplier();

        assertEq(votingModule.votingStreak(voter1), 1);
        // 1 streak → 1.1x → 10e18 * 1.1 = 11e18
        assertEq(streakMultiplier.getMultiplier(voter1), 1.1e18);
        assertEq(votingModule.totalCycleVotingPower(cycleModule.getCurrentCycle()), 11e18);
    }

    function testStreakBuildsOverCycles() public {
        for (uint256 i = 0; i < 5; i++) {
            _voteWithMultiplier();
            if (i < 4) _advanceCycle();
        }

        assertEq(votingModule.votingStreak(voter1), 5);
        assertEq(streakMultiplier.getMultiplier(voter1), 1.5e18);
        // 10e18 * 1.5 = 15e18
        assertEq(votingModule.totalCycleVotingPower(cycleModule.getCurrentCycle()), 15e18);
    }

    function testStreakCapsAt10() public {
        for (uint256 i = 0; i < 12; i++) {
            _voteWithMultiplier();
            if (i < 11) _advanceCycle();
        }

        assertEq(votingModule.votingStreak(voter1), 10);
        assertEq(streakMultiplier.getMultiplier(voter1), 2e18);
        // 10e18 * 2 = 20e18
        assertEq(votingModule.totalCycleVotingPower(cycleModule.getCurrentCycle()), 20e18);
    }

    function testStreakResetsOnMissedCycle() public {
        for (uint256 i = 0; i < 5; i++) {
            _voteWithMultiplier();
            _advanceCycle();
        }
        assertEq(votingModule.votingStreak(voter1), 5);

        // Skip a cycle
        _advanceCycle();

        _voteWithMultiplier();
        assertEq(votingModule.votingStreak(voter1), 1);
    }

    function testRecastDoesntDoubleStreak() public {
        _voteWithMultiplier();
        assertEq(votingModule.votingStreak(voter1), 1);

        vm.roll(block.number + 1);
        _voteWithMultiplier();
        assertEq(votingModule.votingStreak(voter1), 1);
    }

    // ============ Normal Vote Tests ============

    function testNormalVoteStillUpdatesStreak() public {
        // Even without multiplier params, streak should update
        _voteNormal();
        assertEq(votingModule.votingStreak(voter1), 1);

        // But power is base (no multiplier applied)
        assertEq(votingModule.totalCycleVotingPower(cycleModule.getCurrentCycle()), 10e18);
    }

    function testNormalVoteNoMultiplierApplied() public {
        _voteNormal();
        assertEq(votingModule.totalCycleVotingPower(cycleModule.getCurrentCycle()), 10e18);
    }

    // ============ Recast Tests ============

    function testRecastFromMultipliedToNormal() public {
        _voteWithMultiplier();
        assertEq(votingModule.totalCycleVotingPower(cycleModule.getCurrentCycle()), 11e18);

        vm.roll(block.number + 1);
        _voteNormal();
        assertEq(votingModule.totalCycleVotingPower(cycleModule.getCurrentCycle()), 10e18);
    }

    function testRecastFromNormalToMultiplied() public {
        _voteNormal();
        assertEq(votingModule.totalCycleVotingPower(cycleModule.getCurrentCycle()), 10e18);

        vm.roll(block.number + 1);
        _voteWithMultiplier();
        // streak is 1 → 1.1x
        assertEq(votingModule.totalCycleVotingPower(cycleModule.getCurrentCycle()), 11e18);
    }

    // ============ Signature Tests ============

    function testTamperedParamsRejected() public {
        uint256[] memory pts = _points();
        bytes memory params = _streakParams();
        bytes memory sig = _sign(voter1PrivateKey, _paramsDigest(voter1, pts, nextNonce, params));

        bytes memory bad = abi.encode(new uint256[](0));
        vm.expectRevert(IVotingModule.InvalidSignature.selector);
        votingModule.castVoteWithSignatureAndParams(voter1, pts, nextNonce, sig, bad);
    }

    function testInvalidMultiplierIndexReverts() public {
        uint256[] memory pts = _points();
        uint256[] memory idx = new uint256[](1);
        idx[0] = 99;
        bytes memory params = abi.encode(idx);
        bytes memory sig = _sign(voter1PrivateKey, _paramsDigest(voter1, pts, nextNonce, params));

        vm.expectRevert(MultiplierVotingModule.InvalidMultiplierIndex.selector);
        votingModule.castVoteWithSignatureAndParams(voter1, pts, nextNonce, sig, params);
    }

    // ============ Admin Tests ============

    function testAddRemoveMultiplier() public {
        VotingStreakMultiplier m2 = new VotingStreakMultiplier(address(votingModule));
        votingModule.addMultiplier(address(m2));
        assertEq(votingModule.getMultipliers().length, 2);

        votingModule.removeMultiplier(1);
        assertEq(votingModule.getMultipliers().length, 1);
    }

    function testOnlyOwnerCanManageMultipliers() public {
        vm.prank(voter1);
        vm.expectRevert();
        votingModule.addMultiplier(address(0xdead));

        vm.prank(voter1);
        vm.expectRevert();
        votingModule.removeMultiplier(0);
    }
}
