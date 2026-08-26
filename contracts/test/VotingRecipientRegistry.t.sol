// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TestWrapper} from "./TestWrapper.sol";
import {VotingRecipientRegistry} from "../src/implementation/registries/VotingRecipientRegistry.sol";
import {IRecipientRegistry} from "../src/interfaces/IRecipientRegistry.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract VotingRecipientRegistryTest is TestWrapper {
    VotingRecipientRegistry public registry;

    address public constant ADMIN = address(0xAD);
    address public constant RECIPIENT_1 = address(0x1);
    address public constant RECIPIENT_2 = address(0x2);
    address public constant RECIPIENT_3 = address(0x3);
    address public constant NEW_RECIPIENT = address(0x4);
    address public constant NON_RECIPIENT = address(0xdead);

    event ProposalCreated(uint256 indexed proposalId, address indexed candidate, bool isAddition);
    event VoteCast(uint256 indexed proposalId, address indexed voter);
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalExpiryUpdated(uint256 oldExpiry, uint256 newExpiry);
    event AtomicExecutionUpdated(bool atomicExecutionEnabled);

    function setUp() public {
        VotingRecipientRegistry impl = new VotingRecipientRegistry();

        // Initialize with 3 recipients
        address[] memory initial = new address[](3);
        initial[0] = RECIPIENT_1;
        initial[1] = RECIPIENT_2;
        initial[2] = RECIPIENT_3;

        bytes memory initData =
            abi.encodeWithSignature("initialize(address,address[],uint256)", ADMIN, initial, uint256(7 days));
        registry = VotingRecipientRegistry(address(new ERC1967Proxy(address(impl), initData)));
    }

    function test_WhenInitializing() external view {
        // it should set admin recipients and expiry
        assertEq(registry.owner(), ADMIN);
        assertEq(registry.getRecipientCount(), 3);
        assertTrue(registry.isRecipient(RECIPIENT_1));
        assertTrue(registry.isRecipient(RECIPIENT_2));
        assertTrue(registry.isRecipient(RECIPIENT_3));
    }

    function test_WhenProposingAnAddition() external {
        // it should create proposal with auto-vote from proposer
        // it should snapshot required votes at creation
        vm.prank(RECIPIENT_1);
        uint256 proposalId = registry.proposeAddition(NEW_RECIPIENT);

        (
            address candidate,
            bool isAddition,
            uint256 voteCount,
            uint256 requiredVotes,
            bool executed,
            uint256 createdAt
        ) = registry.getProposal(proposalId);

        assertEq(candidate, NEW_RECIPIENT);
        assertTrue(isAddition);
        assertEq(voteCount, 1); // Proposer auto-votes
        assertEq(requiredVotes, 3); // Snapshotted at creation: 3 recipients for addition
        assertFalse(executed);
        assertEq(createdAt, block.timestamp);

        assertTrue(registry.hasVoted(proposalId, RECIPIENT_1));
    }

    function test_WhenVotingOnAProposal() external {
        // it should increment vote count
        vm.prank(RECIPIENT_1);
        uint256 proposalId = registry.proposeAddition(NEW_RECIPIENT);

        vm.prank(RECIPIENT_2);
        vm.expectEmit(true, true, false, false);
        emit VoteCast(proposalId, RECIPIENT_2);
        registry.vote(proposalId);

        (,, uint256 voteCount,,,) = registry.getProposal(proposalId);
        assertEq(voteCount, 2);
        assertTrue(registry.hasVoted(proposalId, RECIPIENT_2));
    }

    function test_WhenUnanimousVoteIsReached() external {
        // it should auto-execute and immediately add the recipient (atomic by default)
        vm.prank(RECIPIENT_1);
        uint256 proposalId = registry.proposeAddition(NEW_RECIPIENT);

        vm.prank(RECIPIENT_2);
        registry.vote(proposalId);

        // Third vote triggers automatic execution AND queue processing in the same tx
        vm.prank(RECIPIENT_3);
        vm.expectEmit(true, false, false, false);
        emit ProposalExecuted(proposalId);
        registry.vote(proposalId);

        (,,,, bool executed,) = registry.getProposal(proposalId);
        assertTrue(executed);
        assertTrue(registry.isRecipient(NEW_RECIPIENT)); // Already active, no processQueue() needed
        assertFalse(registry.isQueuedForAddition(NEW_RECIPIENT));
        assertEq(registry.getRecipientCount(), 4);
    }

    function test_WhenManuallyExecutingAProposal() external {
        // it should activate the recipient immediately (atomic by default);
        // a manual processQueue() afterwards is a harmless no-op
        vm.prank(RECIPIENT_1);
        uint256 addProposal = registry.proposeAddition(NEW_RECIPIENT);
        vm.prank(RECIPIENT_2);
        registry.vote(addProposal);
        vm.prank(RECIPIENT_3);
        registry.vote(addProposal);

        assertTrue(registry.isRecipient(NEW_RECIPIENT));
        registry.processQueue(); // no-op, queue already empty

        // Now we have 4 recipients, create an addition proposal
        vm.prank(RECIPIENT_1);
        uint256 proposalId = registry.proposeAddition(address(0x99));

        vm.prank(RECIPIENT_2);
        registry.vote(proposalId);

        vm.prank(RECIPIENT_3);
        registry.vote(proposalId);

        // The 4th vote auto-executes AND processes the queue in the same tx
        vm.prank(NEW_RECIPIENT);
        registry.vote(proposalId);

        (,,,, bool executed,) = registry.getProposal(proposalId);
        assertTrue(executed);
        assertTrue(registry.isRecipient(address(0x99)));
        registry.processQueue(); // no-op, queue already empty
    }

    function test_WhenProposingARemoval() external {
        // it should create removal proposal
        // it should require fewer votes than addition
        vm.prank(RECIPIENT_1);
        uint256 proposalId = registry.proposeRemoval(RECIPIENT_3);

        (address candidate, bool isAddition, uint256 voteCount, uint256 requiredVotes,,) =
            registry.getProposal(proposalId);

        assertEq(candidate, RECIPIENT_3);
        assertFalse(isAddition);
        assertEq(voteCount, 1);
        assertEq(requiredVotes, 2); // Snapshotted at creation: 3 - 1 for removal
    }

    function test_WhenRemovalReachesThreshold() external {
        // it should auto-execute and immediately remove the recipient (atomic by default)
        vm.prank(RECIPIENT_1);
        uint256 proposalId = registry.proposeRemoval(RECIPIENT_3);

        // Only need 2 votes (all except the one being removed)
        assertEq(registry.getRequiredVotes(proposalId), 2);

        vm.prank(RECIPIENT_2);
        registry.vote(proposalId);

        // Auto-executes AND processes the queue in the same tx
        (,,,, bool executed,) = registry.getProposal(proposalId);
        assertTrue(executed);
        assertFalse(registry.isRecipient(RECIPIENT_3));
        assertFalse(registry.isQueuedForRemoval(RECIPIENT_3));
        assertEq(registry.getRecipientCount(), 2);
    }

    function test_WhenAtomicExecutionIsDefaultEnabled() external view {
        // it should read as atomic on an instance that never touched the flag
        assertTrue(registry.atomicExecutionEnabled());
    }

    function test_WhenAdminSetsAtomicExecution() external {
        // it should switch modes and emit the event
        vm.prank(ADMIN);
        vm.expectEmit(true, false, false, false);
        emit AtomicExecutionUpdated(false);
        registry.setAtomicExecution(false);
        assertFalse(registry.atomicExecutionEnabled());

        vm.prank(ADMIN);
        vm.expectEmit(true, false, false, false);
        emit AtomicExecutionUpdated(true);
        registry.setAtomicExecution(true);
        assertTrue(registry.atomicExecutionEnabled());
    }

    function test_RevertWhen_NonAdminSetsAtomicExecution() external {
        // it should only allow admin to set atomic execution
        vm.prank(RECIPIENT_1);
        vm.expectRevert();
        registry.setAtomicExecution(false);
    }

    function test_WhenVoidableModeLeavesQueueOpen() external {
        // it reproduces the exact problem this flag exists to close: the admin
        // can cancel a vote every recipient just agreed on unanimously
        vm.prank(ADMIN);
        registry.setAtomicExecution(false);

        vm.prank(RECIPIENT_1);
        uint256 proposalId = registry.proposeAddition(NEW_RECIPIENT);
        vm.prank(RECIPIENT_2);
        registry.vote(proposalId);
        vm.prank(RECIPIENT_3);
        registry.vote(proposalId);

        (,,,, bool executed,) = registry.getProposal(proposalId);
        assertTrue(executed);
        assertTrue(registry.isQueuedForAddition(NEW_RECIPIENT));
        assertFalse(registry.isRecipient(NEW_RECIPIENT));

        vm.prank(ADMIN);
        registry.clearAdditionQueue();
        assertFalse(registry.isQueuedForAddition(NEW_RECIPIENT));
        assertFalse(registry.isRecipient(NEW_RECIPIENT)); // Cancelled, never added
    }

    function test_WhenAtomicModeDrainsPreExistingQueue() external {
        // it should process entries left over from voidable mode once atomic returns
        vm.prank(ADMIN);
        registry.setAtomicExecution(false);

        vm.prank(RECIPIENT_1);
        uint256 firstProposal = registry.proposeAddition(address(0x50));
        vm.prank(RECIPIENT_2);
        registry.vote(firstProposal);
        vm.prank(RECIPIENT_3);
        registry.vote(firstProposal);
        assertTrue(registry.isQueuedForAddition(address(0x50)));

        vm.prank(ADMIN);
        registry.setAtomicExecution(true);

        vm.prank(RECIPIENT_1);
        uint256 secondProposal = registry.proposeAddition(address(0x60)); // > 0x50, ascending order holds
        vm.prank(RECIPIENT_2);
        registry.vote(secondProposal);
        vm.prank(RECIPIENT_3);
        registry.vote(secondProposal);

        assertTrue(registry.isRecipient(address(0x50)));
        assertTrue(registry.isRecipient(address(0x60)));
    }

    function test_RevertWhen_VoidableQueueOrderBreaksOnSecondExecution() external {
        // it should revert with QueueNotSorted — already possible today, independent
        // of this flag — and recover once the queue is processed
        vm.prank(ADMIN);
        registry.setAtomicExecution(false);

        vm.prank(RECIPIENT_1);
        uint256 firstProposal = registry.proposeAddition(address(0x99));
        vm.prank(RECIPIENT_2);
        registry.vote(firstProposal);
        vm.prank(RECIPIENT_3);
        registry.vote(firstProposal); // queues 0x99

        vm.prank(RECIPIENT_1);
        uint256 secondProposal = registry.proposeAddition(address(0x11)); // < 0x99
        vm.prank(RECIPIENT_2);
        registry.vote(secondProposal);
        vm.prank(RECIPIENT_3);
        vm.expectRevert(IRecipientRegistry.QueueNotSorted.selector);
        registry.vote(secondProposal);

        // Recovery: no vote is lost, the queue just needs to clear before retrying.
        // Still voidable mode — the recast queues 0x11 but a second processQueue()
        // is needed to actually activate it (queue is empty again, so this one succeeds).
        registry.processQueue();
        vm.prank(RECIPIENT_3);
        registry.vote(secondProposal);
        registry.processQueue();
        assertTrue(registry.isRecipient(address(0x11)));
    }

    function test_WhenAProposalExpires() external {
        // it should reject votes on expired proposals
        // it should reject execution of expired proposals
        vm.prank(RECIPIENT_1);
        uint256 proposalId = registry.proposeAddition(NEW_RECIPIENT);

        // Fast forward past expiry
        vm.warp(block.timestamp + 8 days);

        assertTrue(registry.isProposalExpired(proposalId));

        // Cannot vote on expired proposal
        vm.prank(RECIPIENT_2);
        vm.expectRevert(VotingRecipientRegistry.ProposalExpired.selector);
        registry.vote(proposalId);

        // Cannot execute expired proposal
        vm.expectRevert(VotingRecipientRegistry.ProposalExpired.selector);
        registry.executeProposal(proposalId);
    }

    function test_WhenANonRecipientProposes() external {
        // it should revert with NotARecipient
        vm.prank(NON_RECIPIENT);
        vm.expectRevert(VotingRecipientRegistry.NotARecipient.selector);
        registry.proposeAddition(NEW_RECIPIENT);
    }

    function test_WhenANonRecipientVotes() external {
        // it should revert with NotEligibleVoter
        vm.prank(RECIPIENT_1);
        uint256 proposalId = registry.proposeAddition(NEW_RECIPIENT);

        vm.prank(NON_RECIPIENT);
        vm.expectRevert(VotingRecipientRegistry.NotEligibleVoter.selector);
        registry.vote(proposalId);
    }

    function test_WhenDoubleVoting() external {
        // it should revert with AlreadyVoted
        vm.prank(RECIPIENT_1);
        uint256 proposalId = registry.proposeAddition(NEW_RECIPIENT);

        vm.prank(RECIPIENT_1);
        vm.expectRevert(VotingRecipientRegistry.AlreadyVoted.selector);
        registry.vote(proposalId);
    }

    function test_WhenVotingOnInvalidProposal() external {
        // it should revert with ProposalNotFound
        vm.prank(RECIPIENT_1);
        vm.expectRevert(VotingRecipientRegistry.ProposalNotFound.selector);
        registry.vote(999);
    }

    function test_WhenVotingOnExecutedProposal() external {
        // it should revert with ProposalAlreadyExecuted
        // Create and execute a proposal
        vm.prank(RECIPIENT_1);
        uint256 proposalId = registry.proposeAddition(NEW_RECIPIENT);

        vm.prank(RECIPIENT_2);
        registry.vote(proposalId);

        vm.prank(RECIPIENT_3);
        registry.vote(proposalId);

        // Try to vote on executed proposal
        vm.prank(RECIPIENT_1);
        vm.expectRevert(VotingRecipientRegistry.ProposalAlreadyExecuted.selector);
        registry.vote(proposalId);
    }

    function test_WhenProposingExistingRecipient() external {
        // it should revert with RecipientAlreadyExists
        vm.prank(RECIPIENT_1);
        vm.expectRevert(IRecipientRegistry.RecipientAlreadyExists.selector);
        registry.proposeAddition(RECIPIENT_2);
    }

    function test_WhenRemovingNonExistentRecipient() external {
        // it should revert with RecipientNotFound
        vm.prank(RECIPIENT_1);
        vm.expectRevert(IRecipientRegistry.RecipientNotFound.selector);
        registry.proposeRemoval(NEW_RECIPIENT);
    }

    function test_WhenExecutingWithoutEnoughVotes() external {
        // it should revert with NotEnoughVotes
        vm.prank(RECIPIENT_1);
        uint256 proposalId = registry.proposeAddition(NEW_RECIPIENT);

        vm.prank(RECIPIENT_2);
        registry.vote(proposalId);

        // Only 2 out of 3 votes
        vm.expectRevert(VotingRecipientRegistry.NotEnoughVotes.selector);
        registry.executeProposal(proposalId);
    }

    function test_WhenNewRecipientVotesAfterBeingAdded() external {
        // it should allow new recipient to participate
        // Add new recipient
        vm.prank(RECIPIENT_1);
        uint256 proposalId = registry.proposeAddition(NEW_RECIPIENT);

        vm.prank(RECIPIENT_2);
        registry.vote(proposalId);

        vm.prank(RECIPIENT_3);
        registry.vote(proposalId);

        // Process the queue to actually add the new recipient
        registry.processQueue();

        assertTrue(registry.isRecipient(NEW_RECIPIENT));

        // New recipient can now propose
        vm.prank(NEW_RECIPIENT);
        uint256 newProposalId = registry.proposeAddition(address(0x99));

        // Now need 4 votes (including new recipient)
        assertEq(registry.getRequiredVotes(newProposalId), 4);
    }

    function test_WhenInitializingWithEmptyRecipients() external {
        // it should revert with NoRecipients
        VotingRecipientRegistry impl = new VotingRecipientRegistry();
        address[] memory empty = new address[](0);
        bytes memory initData =
            abi.encodeWithSignature("initialize(address,address[],uint256)", ADMIN, empty, uint256(7 days));

        vm.expectRevert(VotingRecipientRegistry.NoRecipients.selector);
        new ERC1967Proxy(address(impl), initData);
    }

    function test_WhenConfiguringProposalExpiry_ShouldReturnConfiguredExpiry() external view {
        // it should return configured expiry
        assertEq(registry.proposalExpiry(), 7 days);
    }

    function test_WhenConfiguringProposalExpiry_ShouldAllowAdminToUpdateExpiry() external {
        // it should allow admin to update expiry
        uint256 newExpiry = 3 days;

        vm.prank(ADMIN);
        vm.expectEmit(true, true, false, false);
        emit ProposalExpiryUpdated(7 days, newExpiry);
        registry.setProposalExpiry(newExpiry);

        assertEq(registry.proposalExpiry(), newExpiry);
    }

    function test_RevertWhen_ConfiguringProposalExpiry_ZeroExpiryInInitialize() external {
        // it should revert on zero expiry in initialize
        VotingRecipientRegistry impl = new VotingRecipientRegistry();
        address[] memory initial = new address[](1);
        initial[0] = RECIPIENT_1;
        bytes memory initData =
            abi.encodeWithSignature("initialize(address,address[],uint256)", ADMIN, initial, uint256(0));

        vm.expectRevert(VotingRecipientRegistry.InvalidProposalExpiry.selector);
        new ERC1967Proxy(address(impl), initData);
    }

    function test_RevertWhen_ConfiguringProposalExpiry_ZeroExpiryInUpdate() external {
        // it should revert on zero expiry in update
        vm.prank(ADMIN);
        vm.expectRevert(VotingRecipientRegistry.InvalidProposalExpiry.selector);
        registry.setProposalExpiry(0);
    }

    function test_RevertWhen_ConfiguringProposalExpiry_NonAdminSetsExpiry() external {
        // it should only allow admin to set expiry
        vm.prank(RECIPIENT_1);
        vm.expectRevert();
        registry.setProposalExpiry(3 days);
    }

    function test_WhenRequiredVotesAreSnapshotted() external {
        // it should not change after recipient set changes
        // Create an addition proposal while there are 3 recipients (requires 3 votes)
        vm.prank(RECIPIENT_1);
        uint256 proposalId = registry.proposeAddition(NEW_RECIPIENT);
        assertEq(registry.getRequiredVotes(proposalId), 3);

        // Add a 4th recipient via a separate proposal
        vm.prank(RECIPIENT_1);
        uint256 addProposal = registry.proposeAddition(address(0x55));
        vm.prank(RECIPIENT_2);
        registry.vote(addProposal);
        vm.prank(RECIPIENT_3);
        registry.vote(addProposal);
        registry.processQueue();
        assertEq(registry.getRecipientCount(), 4);

        // Original proposal still requires only 3 votes (snapshotted at creation)
        assertEq(registry.getRequiredVotes(proposalId), 3);

        // New recipient is NOT eligible to vote on the pre-existing proposal
        assertFalse(registry.isEligibleVoter(proposalId, address(0x55)));
        vm.prank(address(0x55));
        vm.expectRevert(VotingRecipientRegistry.NotEligibleVoter.selector);
        registry.vote(proposalId);

        // Original recipients can still vote and execute
        vm.prank(RECIPIENT_2);
        registry.vote(proposalId);
        vm.prank(RECIPIENT_3);
        registry.vote(proposalId);

        (,,,, bool executed,) = registry.getProposal(proposalId);
        assertTrue(executed);
    }
}
