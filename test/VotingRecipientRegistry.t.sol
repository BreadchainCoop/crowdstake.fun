// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TestWrapper} from "./TestWrapper.sol";
import {VotingRecipientRegistry} from "../src/implementation/registries/VotingRecipientRegistry.sol";
import {IRecipientRegistry} from "../src/interfaces/IRecipientRegistry.sol";

contract VotingRecipientRegistryTest is TestWrapper {
    VotingRecipientRegistry public registry;

    address public constant ADMIN = address(0xAD);
    address public constant RECIPIENT_1 = address(0x1);
    address public constant RECIPIENT_2 = address(0x2);
    address public constant RECIPIENT_3 = address(0x3);
    address public constant NEW_RECIPIENT = address(0x4);
    address public constant NON_RECIPIENT = address(0xdead);

    event RecipientAdded(address indexed recipient);
    event RecipientRemoved(address indexed recipient);
    event ProposalCreated(uint256 indexed proposalId, address indexed candidate, bool isAddition);
    event VoteCast(uint256 indexed proposalId, address indexed voter);
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalExpiryUpdated(uint256 oldExpiry, uint256 newExpiry);

    function setUp() public {
        registry = new VotingRecipientRegistry();

        // Initialize with 3 recipients
        address[] memory initial = new address[](3);
        initial[0] = RECIPIENT_1;
        initial[1] = RECIPIENT_2;
        initial[2] = RECIPIENT_3;

        registry.initialize(ADMIN, initial, 7 days);
    }

    function test_Initialize() public view {
        assertEq(registry.owner(), ADMIN);
        assertEq(registry.getRecipientCount(), 3);
        assertTrue(registry.isRecipient(RECIPIENT_1));
        assertTrue(registry.isRecipient(RECIPIENT_2));
        assertTrue(registry.isRecipient(RECIPIENT_3));
    }

    function test_ProposeAddition() public {
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

    function test_VoteOnProposal() public {
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

    function test_UnanimousVoteExecutesAutomatically() public {
        vm.prank(RECIPIENT_1);
        uint256 proposalId = registry.proposeAddition(NEW_RECIPIENT);

        vm.prank(RECIPIENT_2);
        registry.vote(proposalId);

        // Third vote should trigger automatic execution (proposal only, not queue processing)
        vm.prank(RECIPIENT_3);
        vm.expectEmit(true, false, false, false);
        emit ProposalExecuted(proposalId);
        registry.vote(proposalId);

        // Verify proposal is executed but recipient not yet added (still in queue)
        (,,,, bool executed,) = registry.getProposal(proposalId);
        assertTrue(executed);
        assertFalse(registry.isRecipient(NEW_RECIPIENT)); // Not yet processed
        assertTrue(registry.isQueuedForAddition(NEW_RECIPIENT)); // Still in queue
        assertEq(registry.getRecipientCount(), 3); // Original count

        // Process the queue to actually add the recipient
        vm.expectEmit(true, false, false, false);
        emit RecipientAdded(NEW_RECIPIENT);
        registry.processQueue();

        // Now verify the recipient is actually added
        assertTrue(registry.isRecipient(NEW_RECIPIENT));
        assertEq(registry.getRecipientCount(), 4);
        assertFalse(registry.isQueuedForAddition(NEW_RECIPIENT)); // No longer in queue
    }

    function test_ManualExecuteProposal() public {
        // Add a fourth recipient first so we can test manual execution
        vm.prank(RECIPIENT_1);
        uint256 addProposal = registry.proposeAddition(NEW_RECIPIENT);
        vm.prank(RECIPIENT_2);
        registry.vote(addProposal);
        vm.prank(RECIPIENT_3);
        registry.vote(addProposal);

        // Process the queue to actually add the fourth recipient
        registry.processQueue();

        // Now we have 4 recipients, create an addition proposal
        vm.prank(RECIPIENT_1);
        uint256 proposalId = registry.proposeAddition(address(0x99));

        vm.prank(RECIPIENT_2);
        registry.vote(proposalId);

        vm.prank(RECIPIENT_3);
        registry.vote(proposalId);

        // The 3rd vote should auto-execute the proposal (but not process queue)
        vm.prank(NEW_RECIPIENT);
        registry.vote(proposalId);

        // Verify the proposal was executed but recipient not yet added
        (,,,, bool executed,) = registry.getProposal(proposalId);
        assertTrue(executed);
        assertFalse(registry.isRecipient(address(0x99))); // Not yet processed
        assertTrue(registry.isQueuedForAddition(address(0x99))); // Still in queue

        // Process queue to actually add the recipient
        registry.processQueue();
        assertTrue(registry.isRecipient(address(0x99))); // Now added
    }

    function test_ProposeRemoval() public {
        vm.prank(RECIPIENT_1);
        uint256 proposalId = registry.proposeRemoval(RECIPIENT_3);

        (address candidate, bool isAddition, uint256 voteCount, uint256 requiredVotes,,) =
            registry.getProposal(proposalId);

        assertEq(candidate, RECIPIENT_3);
        assertFalse(isAddition);
        assertEq(voteCount, 1);
        assertEq(requiredVotes, 2); // Snapshotted at creation: 3 - 1 for removal
    }

    function test_RemovalRequiresFewerVotes() public {
        vm.prank(RECIPIENT_1);
        uint256 proposalId = registry.proposeRemoval(RECIPIENT_3);

        // Only need 2 votes (all except the one being removed)
        assertEq(registry.getRequiredVotes(proposalId), 2);

        vm.prank(RECIPIENT_2);
        registry.vote(proposalId);

        // Should auto-execute proposal with 2 votes (but not process queue)
        (,,,, bool executed,) = registry.getProposal(proposalId);
        assertTrue(executed);

        // Verify recipient is still active (not yet processed)
        assertTrue(registry.isRecipient(RECIPIENT_3)); // Still active
        assertTrue(registry.isQueuedForRemoval(RECIPIENT_3)); // Queued for removal
        assertEq(registry.getRecipientCount(), 3); // Original count

        // Process the queue to actually remove the recipient
        registry.processQueue();

        // Now verify the recipient is removed
        assertFalse(registry.isRecipient(RECIPIENT_3));
        assertEq(registry.getRecipientCount(), 2);
        assertFalse(registry.isQueuedForRemoval(RECIPIENT_3)); // No longer queued
    }

    function test_ProposalExpiry() public {
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

    function test_RevertOnNonRecipientPropose() public {
        vm.prank(NON_RECIPIENT);
        vm.expectRevert(VotingRecipientRegistry.NotARecipient.selector);
        registry.proposeAddition(NEW_RECIPIENT);
    }

    function test_RevertOnNonRecipientVote() public {
        vm.prank(RECIPIENT_1);
        uint256 proposalId = registry.proposeAddition(NEW_RECIPIENT);

        vm.prank(NON_RECIPIENT);
        vm.expectRevert(VotingRecipientRegistry.NotEligibleVoter.selector);
        registry.vote(proposalId);
    }

    function test_RevertOnDoubleVote() public {
        vm.prank(RECIPIENT_1);
        uint256 proposalId = registry.proposeAddition(NEW_RECIPIENT);

        vm.prank(RECIPIENT_1);
        vm.expectRevert(VotingRecipientRegistry.AlreadyVoted.selector);
        registry.vote(proposalId);
    }

    function test_RevertOnInvalidProposal() public {
        vm.prank(RECIPIENT_1);
        vm.expectRevert(VotingRecipientRegistry.ProposalNotFound.selector);
        registry.vote(999);
    }

    function test_RevertOnExecutedProposal() public {
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

    function test_RevertOnProposingExistingRecipient() public {
        vm.prank(RECIPIENT_1);
        vm.expectRevert(IRecipientRegistry.RecipientAlreadyExists.selector);
        registry.proposeAddition(RECIPIENT_2);
    }

    function test_RevertOnRemovingNonExistent() public {
        vm.prank(RECIPIENT_1);
        vm.expectRevert(IRecipientRegistry.RecipientNotFound.selector);
        registry.proposeRemoval(NEW_RECIPIENT);
    }

    function test_RevertOnNotEnoughVotes() public {
        vm.prank(RECIPIENT_1);
        uint256 proposalId = registry.proposeAddition(NEW_RECIPIENT);

        vm.prank(RECIPIENT_2);
        registry.vote(proposalId);

        // Only 2 out of 3 votes
        vm.expectRevert(VotingRecipientRegistry.NotEnoughVotes.selector);
        registry.executeProposal(proposalId);
    }

    function test_NewRecipientCanVoteAfterAdded() public {
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

    function test_RevertOnEmptyInitialRecipients() public {
        VotingRecipientRegistry newRegistry = new VotingRecipientRegistry();
        address[] memory empty = new address[](0);

        vm.expectRevert(VotingRecipientRegistry.NoRecipients.selector);
        newRegistry.initialize(ADMIN, empty, 7 days);
    }

    function test_ProposalExpiryConfiguration() public view {
        // Test that proposal expiry is set correctly during initialization
        assertEq(registry.proposalExpiry(), 7 days);
    }

    function test_SetProposalExpiry() public {
        uint256 newExpiry = 3 days;

        vm.prank(ADMIN);
        vm.expectEmit(true, true, false, false);
        emit ProposalExpiryUpdated(7 days, newExpiry);
        registry.setProposalExpiry(newExpiry);

        assertEq(registry.proposalExpiry(), newExpiry);
    }

    function test_RevertOnInvalidProposalExpiryInitialize() public {
        VotingRecipientRegistry newRegistry = new VotingRecipientRegistry();
        address[] memory initial = new address[](1);
        initial[0] = RECIPIENT_1;

        vm.expectRevert(VotingRecipientRegistry.InvalidProposalExpiry.selector);
        newRegistry.initialize(ADMIN, initial, 0);
    }

    function test_RevertOnInvalidProposalExpiryUpdate() public {
        vm.prank(ADMIN);
        vm.expectRevert(VotingRecipientRegistry.InvalidProposalExpiry.selector);
        registry.setProposalExpiry(0);
    }

    function test_OnlyAdminCanSetProposalExpiry() public {
        vm.prank(RECIPIENT_1);
        vm.expectRevert();
        registry.setProposalExpiry(3 days);
    }

    function test_RequiredVotesUnchangedAfterRecipientSetChanges() public {
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
