// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {SimpleDAO} from "../../src/19-dao/SimpleDAO.sol";

contract SimpleDAOTest is Test {
    SimpleDAO public dao;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");

    uint256 public constant VOTING_PERIOD = 3 days;
    uint256 public constant EXECUTION_WINDOW = 7 days;
    uint256 public constant QUORUM_PERCENTAGE = 25;
    uint256 public constant PROPOSAL_THRESHOLD = 1 ether;

    function setUp() public {
        dao = new SimpleDAO(VOTING_PERIOD, EXECUTION_WINDOW, QUORUM_PERCENTAGE, PROPOSAL_THRESHOLD);

        // Fund test accounts
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(charlie, 100 ether);
    }

    // ============ MEMBERSHIP TESTS ============

    function test_JoinWithETH() public {
        vm.prank(alice);
        dao.join{value: 10 ether}();

        (uint256 balance, uint256 joinedAt) = dao.members(alice);
        assertEq(balance, 10 ether);
        assertGt(joinedAt, 0);
        assertEq(dao.totalVotingPower(), 10 ether);
    }

    function test_RevertWhen_JoinWithZeroETH() public {
        vm.prank(alice);
        vm.expectRevert(SimpleDAO.ZeroAmount.selector);
        dao.join{value: 0}();
    }

    function test_RevertWhen_JoinTwice() public {
        vm.startPrank(alice);
        dao.join{value: 10 ether}();
        vm.expectRevert(SimpleDAO.AlreadyAMember.selector);
        dao.join{value: 5 ether}();
        vm.stopPrank();
    }

    function test_AddFunds() public {
        _joinDAO(alice, 10 ether);

        vm.prank(alice);
        dao.addFunds{value: 5 ether}();

        (uint256 balance, ) = dao.members(alice);
        assertEq(balance, 15 ether);
        assertEq(dao.totalVotingPower(), 15 ether);
    }

    function test_RevertWhen_AddFundsNotMember() public {
        vm.prank(alice);
        vm.expectRevert(SimpleDAO.NotAMember.selector);
        dao.addFunds{value: 5 ether}();
    }

    function test_Withdraw() public {
        _joinDAO(alice, 10 ether);

        uint256 balanceBefore = alice.balance;
        vm.prank(alice);
        dao.withdraw(3 ether);

        (uint256 daoBalance, ) = dao.members(alice);
        assertEq(daoBalance, 7 ether);
        assertEq(alice.balance, balanceBefore + 3 ether);
        assertEq(dao.totalVotingPower(), 7 ether);
    }

    function test_RevertWhen_WithdrawMoreThanBalance() public {
        _joinDAO(alice, 10 ether);

        vm.prank(alice);
        vm.expectRevert(SimpleDAO.InsufficientBalance.selector);
        dao.withdraw(15 ether);
    }

    // ============ PROPOSAL TESTS ============

    function test_CreateProposal() public {
        _joinDAO(alice, 10 ether);

        vm.prank(alice);
        uint256 proposalId = dao.propose(charlie, 5 ether, "Fund Charlie");

        assertEq(proposalId, 1);
        (
            uint256 id,
            address proposer,
            address recipient,
            uint256 amount,
            ,
            uint256 createdAt,
            uint256 forVotes,
            uint256 againstVotes,
            bool executed,
            bool canceled
        ) = dao.proposals(1);

        assertEq(id, 1);
        assertEq(proposer, alice);
        assertEq(recipient, charlie);
        assertEq(amount, 5 ether);
        assertGt(createdAt, 0);
        assertEq(forVotes, 0);
        assertEq(againstVotes, 0);
        assertFalse(executed);
        assertFalse(canceled);
    }

    function test_RevertWhen_NonMemberProposes() public {
        vm.prank(alice);
        vm.expectRevert(SimpleDAO.NotAMember.selector);
        dao.propose(charlie, 1 ether, "Test");
    }

    function test_RevertWhen_BelowThreshold() public {
        _joinDAO(alice, 0.5 ether); // Below 1 ether threshold

        vm.prank(alice);
        vm.expectRevert(SimpleDAO.BelowProposalThreshold.selector);
        dao.propose(charlie, 0.1 ether, "Test");
    }

    function test_RevertWhen_ProposeZeroAmount() public {
        _joinDAO(alice, 10 ether);

        vm.prank(alice);
        vm.expectRevert(SimpleDAO.ZeroAmount.selector);
        dao.propose(charlie, 0, "Test");
    }

    function test_RevertWhen_ProposeToZeroAddress() public {
        _joinDAO(alice, 10 ether);

        vm.prank(alice);
        vm.expectRevert(SimpleDAO.InvalidRecipient.selector);
        dao.propose(address(0), 1 ether, "Test");
    }

    function test_CancelProposal() public {
        _joinDAO(alice, 10 ether);
        uint256 proposalId = _createProposal(alice, charlie, 5 ether, "Test");

        vm.prank(alice);
        dao.cancel(proposalId);

        assertEq(uint256(dao.getProposalState(proposalId)), uint256(SimpleDAO.ProposalState.Canceled));
    }

    function test_RevertWhen_NonProposerCancels() public {
        _joinDAO(alice, 10 ether);
        _joinDAO(bob, 10 ether);
        uint256 proposalId = _createProposal(alice, charlie, 5 ether, "Test");

        vm.prank(bob);
        vm.expectRevert(SimpleDAO.OnlyProposer.selector);
        dao.cancel(proposalId);
    }

    // ============ VOTING TESTS ============

    function test_VoteFor() public {
        _joinDAO(alice, 10 ether);
        uint256 proposalId = _createProposal(alice, charlie, 5 ether, "Test");

        vm.prank(alice);
        dao.vote(proposalId, true);

        (, , , , , , uint256 forVotes, uint256 againstVotes, , ) = dao.proposals(proposalId);
        assertEq(forVotes, 10 ether);
        assertEq(againstVotes, 0);
        assertTrue(dao.hasVoted(proposalId, alice));
    }

    function test_VoteAgainst() public {
        _joinDAO(alice, 10 ether);
        uint256 proposalId = _createProposal(alice, charlie, 5 ether, "Test");

        vm.prank(alice);
        dao.vote(proposalId, false);

        (, , , , , , uint256 forVotes, uint256 againstVotes, , ) = dao.proposals(proposalId);
        assertEq(forVotes, 0);
        assertEq(againstVotes, 10 ether);
    }

    function test_RevertWhen_VoteTwice() public {
        _joinDAO(alice, 10 ether);
        uint256 proposalId = _createProposal(alice, charlie, 5 ether, "Test");

        vm.startPrank(alice);
        dao.vote(proposalId, true);
        vm.expectRevert(SimpleDAO.AlreadyVoted.selector);
        dao.vote(proposalId, false);
        vm.stopPrank();
    }

    function test_RevertWhen_VoteAfterPeriod() public {
        _joinDAO(alice, 10 ether);
        uint256 proposalId = _createProposal(alice, charlie, 5 ether, "Test");

        vm.warp(block.timestamp + VOTING_PERIOD + 1);

        vm.prank(alice);
        vm.expectRevert(SimpleDAO.ProposalNotActive.selector);
        dao.vote(proposalId, true);
    }

    function test_RevertWhen_NonMemberVotes() public {
        _joinDAO(alice, 10 ether);
        uint256 proposalId = _createProposal(alice, charlie, 5 ether, "Test");

        vm.prank(bob); // bob is not a member
        vm.expectRevert(SimpleDAO.NotAMember.selector);
        dao.vote(proposalId, true);
    }

    // ============ PROPOSAL STATE TESTS ============

    function test_ProposalState_Active() public {
        _joinDAO(alice, 10 ether);
        uint256 proposalId = _createProposal(alice, charlie, 5 ether, "Test");

        assertEq(uint256(dao.getProposalState(proposalId)), uint256(SimpleDAO.ProposalState.Active));
    }

    function test_ProposalState_Canceled() public {
        _joinDAO(alice, 10 ether);
        uint256 proposalId = _createProposal(alice, charlie, 5 ether, "Test");

        vm.prank(alice);
        dao.cancel(proposalId);

        assertEq(uint256(dao.getProposalState(proposalId)), uint256(SimpleDAO.ProposalState.Canceled));
    }

    function test_ProposalState_Defeated_NoQuorum() public {
        _joinDAO(alice, 10 ether);
        _joinDAO(bob, 90 ether); // Total 100 ether, need 25% = 25 ether to vote

        uint256 proposalId = _createProposal(alice, charlie, 5 ether, "Test");

        // Only alice votes (10 ether < 25 ether quorum)
        vm.prank(alice);
        dao.vote(proposalId, true);

        vm.warp(block.timestamp + VOTING_PERIOD + 1);

        assertEq(uint256(dao.getProposalState(proposalId)), uint256(SimpleDAO.ProposalState.Defeated));
    }

    function test_ProposalState_Defeated_NoMajority() public {
        _joinDAO(alice, 10 ether);
        _joinDAO(bob, 20 ether);

        uint256 proposalId = _createProposal(alice, charlie, 5 ether, "Test");

        // Alice votes FOR (10), Bob votes AGAINST (20)
        _vote(alice, proposalId, true);
        _vote(bob, proposalId, false);

        vm.warp(block.timestamp + VOTING_PERIOD + 1);

        // Quorum reached (30/30 = 100% > 25%), but AGAINST wins
        assertEq(uint256(dao.getProposalState(proposalId)), uint256(SimpleDAO.ProposalState.Defeated));
    }

    function test_ProposalState_Succeeded() public {
        _joinDAO(alice, 10 ether);
        _joinDAO(bob, 5 ether);

        uint256 proposalId = _createProposal(alice, charlie, 5 ether, "Test");

        // Alice votes FOR (10), Bob votes AGAINST (5)
        _vote(alice, proposalId, true);
        _vote(bob, proposalId, false);

        vm.warp(block.timestamp + VOTING_PERIOD + 1);

        // Quorum reached (15/15 = 100% > 25%), FOR wins (10 > 5)
        assertEq(uint256(dao.getProposalState(proposalId)), uint256(SimpleDAO.ProposalState.Succeeded));
    }

    function test_ProposalState_Expired() public {
        _joinDAO(alice, 10 ether);
        uint256 proposalId = _createProposal(alice, charlie, 5 ether, "Test");

        _vote(alice, proposalId, true);

        // Skip past voting period AND execution window
        vm.warp(block.timestamp + VOTING_PERIOD + EXECUTION_WINDOW + 1);

        assertEq(uint256(dao.getProposalState(proposalId)), uint256(SimpleDAO.ProposalState.Expired));
    }

    function test_ProposalState_Executed() public {
        _joinDAO(alice, 10 ether);
        uint256 proposalId = _createProposal(alice, charlie, 5 ether, "Test");

        _vote(alice, proposalId, true);

        vm.warp(block.timestamp + VOTING_PERIOD + 1);

        dao.execute(proposalId);

        assertEq(uint256(dao.getProposalState(proposalId)), uint256(SimpleDAO.ProposalState.Executed));
    }

    // ============ EXECUTION TESTS ============

    function test_Execute() public {
        _joinDAO(alice, 10 ether);
        uint256 proposalId = _createProposal(alice, charlie, 5 ether, "Test");

        _vote(alice, proposalId, true);

        vm.warp(block.timestamp + VOTING_PERIOD + 1);

        uint256 charlieBefore = charlie.balance;
        dao.execute(proposalId);

        assertEq(charlie.balance, charlieBefore + 5 ether);
        (, , , , , , , , bool executed, ) = dao.proposals(proposalId);
        assertTrue(executed);
    }

    function test_RevertWhen_ExecuteDefeated() public {
        _joinDAO(alice, 10 ether);
        _joinDAO(bob, 20 ether);
        uint256 proposalId = _createProposal(alice, charlie, 5 ether, "Test");

        _vote(alice, proposalId, true);
        _vote(bob, proposalId, false);

        vm.warp(block.timestamp + VOTING_PERIOD + 1);

        vm.expectRevert(SimpleDAO.ProposalNotSucceeded.selector);
        dao.execute(proposalId);
    }

    function test_RevertWhen_ExecuteExpired() public {
        _joinDAO(alice, 10 ether);
        uint256 proposalId = _createProposal(alice, charlie, 5 ether, "Test");

        _vote(alice, proposalId, true);

        vm.warp(block.timestamp + VOTING_PERIOD + EXECUTION_WINDOW + 1);

        vm.expectRevert(SimpleDAO.ProposalNotSucceeded.selector);
        dao.execute(proposalId);
    }

    function test_RevertWhen_ExecuteTwice() public {
        _joinDAO(alice, 10 ether);
        uint256 proposalId = _createProposal(alice, charlie, 5 ether, "Test");

        _vote(alice, proposalId, true);

        vm.warp(block.timestamp + VOTING_PERIOD + 1);

        dao.execute(proposalId);

        vm.expectRevert(SimpleDAO.ProposalNotSucceeded.selector);
        dao.execute(proposalId);
    }

    // ============ EDGE CASE TESTS ============

    function test_ExactlyAtQuorum() public {
        _joinDAO(alice, 25 ether);
        _joinDAO(bob, 75 ether); // Total 100 ether, quorum = 25 ether

        uint256 proposalId = _createProposal(alice, charlie, 5 ether, "Test");

        // Only alice votes (exactly 25% quorum)
        _vote(alice, proposalId, true);

        vm.warp(block.timestamp + VOTING_PERIOD + 1);

        // Should succeed - exactly at quorum
        assertEq(uint256(dao.getProposalState(proposalId)), uint256(SimpleDAO.ProposalState.Succeeded));
    }

    function test_TieVote() public {
        _joinDAO(alice, 10 ether);
        _joinDAO(bob, 10 ether);

        uint256 proposalId = _createProposal(alice, charlie, 5 ether, "Test");

        _vote(alice, proposalId, true);
        _vote(bob, proposalId, false);

        vm.warp(block.timestamp + VOTING_PERIOD + 1);

        // Tie should be defeated (forVotes > againstVotes required, not >=)
        assertEq(uint256(dao.getProposalState(proposalId)), uint256(SimpleDAO.ProposalState.Defeated));
    }

    function test_QuorumReached() public {
        _joinDAO(alice, 30 ether);
        _joinDAO(bob, 70 ether); // Total 100 ether

        uint256 proposalId = _createProposal(alice, charlie, 5 ether, "Test");

        _vote(alice, proposalId, true); // 30% voted

        assertTrue(dao.quorumReached(proposalId)); // 30 >= 25
    }

    function test_QuorumNotReached() public {
        _joinDAO(alice, 20 ether);
        _joinDAO(bob, 80 ether); // Total 100 ether

        uint256 proposalId = _createProposal(alice, charlie, 5 ether, "Test");

        _vote(alice, proposalId, true); // 20% voted

        assertFalse(dao.quorumReached(proposalId)); // 20 < 25
    }

    // ============ HELPER FUNCTIONS ============

    function _joinDAO(address member, uint256 amount) internal {
        vm.prank(member);
        dao.join{value: amount}();
    }

    function _createProposal(
        address proposer,
        address recipient,
        uint256 amount,
        string memory description
    ) internal returns (uint256) {
        vm.prank(proposer);
        return dao.propose(recipient, amount, description);
    }

    function _vote(address voter, uint256 proposalId, bool support) internal {
        vm.prank(voter);
        dao.vote(proposalId, support);
    }
}
