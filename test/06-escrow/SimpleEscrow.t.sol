// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import "lib/forge-std/src/Test.sol";
import "../../src/06-escrow/SimpleEscrow.sol";

contract SimpleEscrowTest is Test {
    SimpleEscrow escrow;

    address payer = address(0xA11CE);
    address payee = address(0xBEEF);
    address attacker = address(0xBAD);

    function setUp() public {
        escrow = new SimpleEscrow();

        // give ETH to actors
        vm.deal(payer, 10 ether);
        vm.deal(attacker, 10 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            CREATION
    //////////////////////////////////////////////////////////////*/

    function testCreateEscrow() public {
        vm.prank(payer);
        escrow.createEscrow(payee);

        (
            address storedPayer,
            address storedPayee,
            ,
            SimpleEscrow.State state
        ) = escrow.escrow();

        assertEq(storedPayer, payer);
        assertEq(storedPayee, payee);
        assertEq(uint256(state), uint256(SimpleEscrow.State.Created));
    }

    function testCannotCreateTwice() public {
        vm.prank(payer);
        escrow.createEscrow(payee);

        vm.prank(payer);
        vm.expectRevert();
        escrow.createEscrow(payee);
    }

    /*//////////////////////////////////////////////////////////////
                            FUNDING
    //////////////////////////////////////////////////////////////*/

    function testPayerCanFundEscrow() public {
        vm.prank(payer);
        escrow.createEscrow(payee);

        vm.prank(payer);
        escrow.fundEscrow{value: 1 ether}();

        (, , uint256 amount, SimpleEscrow.State state) = escrow.escrow();

        assertEq(amount, 1 ether);
        assertEq(uint256(state), uint256(SimpleEscrow.State.Funded));
    }

    function testNonPayerCannotFund() public {
        vm.prank(payer);
        escrow.createEscrow(payee);

        vm.prank(attacker);
        vm.expectRevert();
        escrow.fundEscrow{value: 1 ether}();
    }

    /*//////////////////////////////////////////////////////////////
                            RELEASE
    //////////////////////////////////////////////////////////////*/

    function testReleaseSendsEthToPayee() public {
        vm.prank(payer);
        escrow.createEscrow(payee);

        vm.prank(payer);
        escrow.fundEscrow{value: 1 ether}();

        uint256 balanceBefore = payee.balance;

        vm.prank(payer);
        escrow.releaseEscrow();

        assertEq(payee.balance, balanceBefore + 1 ether);

        (, , uint256 amount, SimpleEscrow.State state) = escrow.escrow();
        assertEq(amount, 0);
        assertEq(uint256(state), uint256(SimpleEscrow.State.Released));
    }

    /*//////////////////////////////////////////////////////////////
                            CANCEL
    //////////////////////////////////////////////////////////////*/

    function testCancelRefundsPayer() public {
        vm.prank(payer);
        escrow.createEscrow(payee);

        vm.prank(payer);
        escrow.fundEscrow{value: 1 ether}();

        uint256 balanceBefore = payer.balance;

        vm.prank(payer);
        escrow.cancelEscrow();

        assertEq(payer.balance, balanceBefore + 1 ether);

        (, , uint256 amount, SimpleEscrow.State state) = escrow.escrow();
        assertEq(amount, 0);
        assertEq(uint256(state), uint256(SimpleEscrow.State.Cancelled));
    }
}
