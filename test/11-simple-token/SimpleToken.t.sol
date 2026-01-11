// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import "lib/forge-std/src/Test.sol";
import "../../src/11-simple-token/SimpleToken.sol";

contract SimpleTokenTest is Test {
    SimpleToken token;

    address owner = address(this);
    address user1 = address(0xA11CE);
    address user2 = address(0xB0B);
    address spender = address(0x5E11E7);

    string constant NAME = "TestToken";
    string constant SYMBOL = "TST";
    uint256 constant MAX_SUPPLY = 1000 ether;
    uint8 constant DECIMALS = 18;

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    function setUp() public {
        token = new SimpleToken(NAME, SYMBOL, MAX_SUPPLY, DECIMALS);
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    function testConstructorSetsValues() public view {
        assertEq(token.name(), NAME);
        assertEq(token.symbol(), SYMBOL);
        assertEq(token.maxSupply(), MAX_SUPPLY);
        assertEq(token.decimals(), DECIMALS);
        assertEq(token.owner(), owner);
        assertEq(token.totalSupply(), 0);
    }

    function testConstructorRevertsOnEmptyName() public {
        vm.expectRevert();
        new SimpleToken("", SYMBOL, MAX_SUPPLY, DECIMALS);
    }

    function testConstructorRevertsOnEmptySymbol() public {
        vm.expectRevert();
        new SimpleToken(NAME, "", MAX_SUPPLY, DECIMALS);
    }

    function testConstructorRevertsOnZeroMaxSupply() public {
        vm.expectRevert();
        new SimpleToken(NAME, SYMBOL, 0, DECIMALS);
    }

    /*//////////////////////////////////////////////////////////////
                            MINTING
    //////////////////////////////////////////////////////////////*/

    function testMintIncreasesBalanceAndSupply() public {
        token.mint(user1, 100 ether);

        assertEq(token.balanceOf(user1), 100 ether);
        assertEq(token.totalSupply(), 100 ether);
    }

    function testMintEmitsTransferEvent() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), user1, 100 ether);

        token.mint(user1, 100 ether);
    }

    function testMintRevertsIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        token.mint(user1, 100 ether);
    }

    function testMintRevertsIfExceedsMaxSupply() public {
        token.mint(user1, MAX_SUPPLY);

        vm.expectRevert();
        token.mint(user1, 1);
    }

    function testMintRevertsOnZeroAddress() public {
        vm.expectRevert();
        token.mint(address(0), 100 ether);
    }

    function testMintRevertsOnZeroAmount() public {
        vm.expectRevert();
        token.mint(user1, 0);
    }

    /*//////////////////////////////////////////////////////////////
                            TRANSFER
    //////////////////////////////////////////////////////////////*/

    function testTransferMovesTokens() public {
        token.mint(user1, 100 ether);

        vm.prank(user1);
        token.transfer(user2, 30 ether);

        assertEq(token.balanceOf(user1), 70 ether);
        assertEq(token.balanceOf(user2), 30 ether);
    }

    function testTransferEmitsEvent() public {
        token.mint(user1, 100 ether);

        vm.expectEmit(true, true, false, true);
        emit Transfer(user1, user2, 30 ether);

        vm.prank(user1);
        token.transfer(user2, 30 ether);
    }

    function testTransferReturnsTrue() public {
        token.mint(user1, 100 ether);

        vm.prank(user1);
        bool success = token.transfer(user2, 30 ether);

        assertTrue(success);
    }

    function testTransferRevertsOnInsufficientBalance() public {
        token.mint(user1, 10 ether);

        vm.prank(user1);
        vm.expectRevert();
        token.transfer(user2, 20 ether);
    }

    function testTransferRevertsOnZeroAddress() public {
        token.mint(user1, 100 ether);

        vm.prank(user1);
        vm.expectRevert();
        token.transfer(address(0), 10 ether);
    }

    function testTransferRevertsOnZeroAmount() public {
        token.mint(user1, 100 ether);

        vm.prank(user1);
        vm.expectRevert();
        token.transfer(user2, 0);
    }

    /*//////////////////////////////////////////////////////////////
                            APPROVE
    //////////////////////////////////////////////////////////////*/

    function testApproveSetsAllowance() public {
        vm.prank(user1);
        token.approve(spender, 50 ether);

        assertEq(token.allowance(user1, spender), 50 ether);
    }

    function testApproveEmitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit Approval(user1, spender, 50 ether);

        vm.prank(user1);
        token.approve(spender, 50 ether);
    }

    function testApproveReturnsTrue() public {
        vm.prank(user1);
        bool success = token.approve(spender, 50 ether);

        assertTrue(success);
    }

    function testApproveOverwritesExisting() public {
        vm.prank(user1);
        token.approve(spender, 50 ether);

        vm.prank(user1);
        token.approve(spender, 100 ether);

        assertEq(token.allowance(user1, spender), 100 ether);
    }

    function testApproveRevertsOnZeroSpender() public {
        vm.prank(user1);
        vm.expectRevert();
        token.approve(address(0), 50 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            TRANSFER FROM
    //////////////////////////////////////////////////////////////*/

    function testTransferFromMovesTokens() public {
        token.mint(user1, 100 ether);

        vm.prank(user1);
        token.approve(spender, 50 ether);

        vm.prank(spender);
        token.transferFrom(user1, user2, 30 ether);

        assertEq(token.balanceOf(user1), 70 ether);
        assertEq(token.balanceOf(user2), 30 ether);
    }

    function testTransferFromDecreasesAllowance() public {
        token.mint(user1, 100 ether);

        vm.prank(user1);
        token.approve(spender, 50 ether);

        vm.prank(spender);
        token.transferFrom(user1, user2, 30 ether);

        assertEq(token.allowance(user1, spender), 20 ether);
    }

    function testTransferFromEmitsEvent() public {
        token.mint(user1, 100 ether);

        vm.prank(user1);
        token.approve(spender, 50 ether);

        vm.expectEmit(true, true, false, true);
        emit Transfer(user1, user2, 30 ether);

        vm.prank(spender);
        token.transferFrom(user1, user2, 30 ether);
    }

    function testTransferFromRevertsOnInsufficientAllowance() public {
        token.mint(user1, 100 ether);

        vm.prank(user1);
        token.approve(spender, 10 ether);

        vm.prank(spender);
        vm.expectRevert();
        token.transferFrom(user1, user2, 20 ether);
    }

    function testTransferFromRevertsOnInsufficientBalance() public {
        token.mint(user1, 10 ether);

        vm.prank(user1);
        token.approve(spender, 100 ether);

        vm.prank(spender);
        vm.expectRevert();
        token.transferFrom(user1, user2, 20 ether);
    }

    function testTransferFromRevertsOnZeroTo() public {
        token.mint(user1, 100 ether);

        vm.prank(user1);
        token.approve(spender, 50 ether);

        vm.prank(spender);
        vm.expectRevert();
        token.transferFrom(user1, address(0), 10 ether);
    }

    /*//////////////////////////////////////////////////////////////
                        INCREASE ALLOWANCE
    //////////////////////////////////////////////////////////////*/

    function testIncreaseAllowanceAddsToExisting() public {
        vm.prank(user1);
        token.approve(spender, 50 ether);

        vm.prank(user1);
        token.increaseAllowance(spender, 30 ether);

        assertEq(token.allowance(user1, spender), 80 ether);
    }

    function testIncreaseAllowanceEmitsEvent() public {
        vm.prank(user1);
        token.approve(spender, 50 ether);

        vm.expectEmit(true, true, false, true);
        emit Approval(user1, spender, 80 ether);

        vm.prank(user1);
        token.increaseAllowance(spender, 30 ether);
    }

    function testIncreaseAllowanceRevertsOnZeroSpender() public {
        vm.prank(user1);
        vm.expectRevert();
        token.increaseAllowance(address(0), 50 ether);
    }

    /*//////////////////////////////////////////////////////////////
                        DECREASE ALLOWANCE
    //////////////////////////////////////////////////////////////*/

    function testDecreaseAllowanceSubtractsFromExisting() public {
        vm.prank(user1);
        token.approve(spender, 50 ether);

        vm.prank(user1);
        token.decreaseAllowance(spender, 20 ether);

        assertEq(token.allowance(user1, spender), 30 ether);
    }

    function testDecreaseAllowanceEmitsEvent() public {
        vm.prank(user1);
        token.approve(spender, 50 ether);

        vm.expectEmit(true, true, false, true);
        emit Approval(user1, spender, 30 ether);

        vm.prank(user1);
        token.decreaseAllowance(spender, 20 ether);
    }

    function testDecreaseAllowanceRevertsIfExceedsCurrent() public {
        vm.prank(user1);
        token.approve(spender, 50 ether);

        vm.prank(user1);
        vm.expectRevert();
        token.decreaseAllowance(spender, 60 ether);
    }

    function testDecreaseAllowanceRevertsOnZeroSpender() public {
        vm.prank(user1);
        vm.expectRevert();
        token.decreaseAllowance(address(0), 10 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function testBalanceOfReturnsCorrectBalance() public {
        token.mint(user1, 100 ether);

        assertEq(token.balanceOf(user1), 100 ether);
        assertEq(token.balanceOf(user2), 0);
    }

    function testAllowanceReturnsCorrectValue() public {
        vm.prank(user1);
        token.approve(spender, 50 ether);

        assertEq(token.allowance(user1, spender), 50 ether);
        assertEq(token.allowance(user1, user2), 0);
    }
}
