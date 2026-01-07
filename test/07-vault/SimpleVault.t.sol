// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import "lib/forge-std/src/Test.sol";
import "../../src/07-vault/SimpleVault.sol";

contract SimpleVaultTest is Test {
    SimpleVault vault;

    address user1 = address(0xA11CE);
    address user2 = address(0xB0B);
    address feeCollector = address(0xFEE);

    uint256 constant LOCK_DURATION = 1 days;
    uint256 constant FEE_BPS = 1000; // 10%

    function setUp() public {
        vault = new SimpleVault(feeCollector, FEE_BPS, LOCK_DURATION);

        // Give ETH to test actors
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSITS
    //////////////////////////////////////////////////////////////*/

    function testFirstDepositSetsBalanceAndUnlockTime() public {
        vm.prank(user1);
        vault.deposit{value: 1 ether}();

        SimpleVault.Vault memory v = vault.getVaultInfo(user1);

        assertEq(v.balance, 1 ether);
        assertEq(v.unlockTime, block.timestamp + LOCK_DURATION);
    }

    function testAdditionalDepositAddsBalanceAndResetsTimer() public {
        vm.prank(user1);
        vault.deposit{value: 1 ether}();

        // Advance time
        vm.warp(block.timestamp + 12 hours);

        vm.prank(user1);
        vault.deposit{value: 0.5 ether}();

        SimpleVault.Vault memory v = vault.getVaultInfo(user1);

        assertEq(v.balance, 1.5 ether);
        assertEq(v.unlockTime, block.timestamp + LOCK_DURATION);
    }

    function testCannotDepositZeroValue() public {
        vm.prank(user1);
        vm.expectRevert();
        vault.deposit{value: 0}();
    }

    /*//////////////////////////////////////////////////////////////
                        NORMAL WITHDRAWALS
    //////////////////////////////////////////////////////////////*/

    function testWithdrawFailsBeforeUnlock() public {
        vm.prank(user1);
        vault.deposit{value: 1 ether}();

        vm.prank(user1);
        vm.expectRevert();
        vault.withdraw();
    }

    function testWithdrawSucceedsAfterUnlock() public {
        vm.prank(user1);
        vault.deposit{value: 1 ether}();

        // Advance past unlock time
        vm.warp(block.timestamp + LOCK_DURATION + 1);

        uint256 balanceBefore = user1.balance;

        vm.prank(user1);
        vault.withdraw();

        assertEq(user1.balance, balanceBefore + 1 ether);

        // After full withdraw, getVaultInfo reverts with NoDeposit
        // Use depositorToVault directly to check balance is 0
        (uint256 vaultBalance, ) = vault.depositorToVault(user1);
        assertEq(vaultBalance, 0);
    }

    function testWithdrawFailsWithNoDeposit() public {
        vm.prank(user1);
        vm.expectRevert();
        vault.withdraw();
    }

    /*//////////////////////////////////////////////////////////////
                        PARTIAL WITHDRAWALS
    //////////////////////////////////////////////////////////////*/

    function testPartialWithdrawSucceeds() public {
        vm.prank(user1);
        vault.deposit{value: 2 ether}();

        vm.warp(block.timestamp + LOCK_DURATION + 1);

        uint256 balanceBefore = user1.balance;

        vm.prank(user1);
        vault.withdrawPartial(0.5 ether);

        assertEq(user1.balance, balanceBefore + 0.5 ether);

        SimpleVault.Vault memory v = vault.getVaultInfo(user1);
        assertEq(v.balance, 1.5 ether);
    }

    function testPartialWithdrawFailsIfAmountExceedsBalance() public {
        vm.prank(user1);
        vault.deposit{value: 1 ether}();

        vm.warp(block.timestamp + LOCK_DURATION + 1);

        vm.prank(user1);
        vm.expectRevert();
        vault.withdrawPartial(2 ether);
    }

    function testPartialWithdrawFailsWithZeroAmount() public {
        vm.prank(user1);
        vault.deposit{value: 1 ether}();

        vm.warp(block.timestamp + LOCK_DURATION + 1);

        vm.prank(user1);
        vm.expectRevert();
        vault.withdrawPartial(0);
    }

    /*//////////////////////////////////////////////////////////////
                        EMERGENCY WITHDRAWAL
    //////////////////////////////////////////////////////////////*/

    function testEmergencyWithdrawWorksBeforeUnlock() public {
        vm.prank(user1);
        vault.deposit{value: 1 ether}();

        uint256 userBalanceBefore = user1.balance;
        uint256 feeCollectorBalanceBefore = feeCollector.balance;

        vm.prank(user1);
        vault.emergencyWithdraw();

        // 10% fee = 0.1 ether
        uint256 expectedFee = 0.1 ether;
        uint256 expectedUserReceives = 0.9 ether;

        assertEq(user1.balance, userBalanceBefore + expectedUserReceives);
        assertEq(feeCollector.balance, feeCollectorBalanceBefore + expectedFee);

        // After full withdraw, use depositorToVault directly
        (uint256 vaultBalance, ) = vault.depositorToVault(user1);
        assertEq(vaultBalance, 0);
    }

    function testEmergencyWithdrawNoPenaltyIfUnlocked() public {
        vm.prank(user1);
        vault.deposit{value: 1 ether}();

        vm.warp(block.timestamp + LOCK_DURATION + 1);

        uint256 userBalanceBefore = user1.balance;
        uint256 feeCollectorBalanceBefore = feeCollector.balance;

        vm.prank(user1);
        vault.emergencyWithdraw();

        // No fee since already unlocked
        assertEq(user1.balance, userBalanceBefore + 1 ether);
        assertEq(feeCollector.balance, feeCollectorBalanceBefore);
    }

    function testEmergencyWithdrawFailsWithNoDeposit() public {
        vm.prank(user1);
        vm.expectRevert();
        vault.emergencyWithdraw();
    }

    /*//////////////////////////////////////////////////////////////
                        LOCK EXTENSION
    //////////////////////////////////////////////////////////////*/

    function testExtendLockIncreasesUnlockTime() public {
        vm.prank(user1);
        vault.deposit{value: 1 ether}();

        SimpleVault.Vault memory vBefore = vault.getVaultInfo(user1);

        vm.prank(user1);
        vault.extendLock(1 days);

        SimpleVault.Vault memory vAfter = vault.getVaultInfo(user1);

        assertEq(vAfter.unlockTime, vBefore.unlockTime + 1 days);
    }

    function testExtendLockFailsWithZeroExtension() public {
        vm.prank(user1);
        vault.deposit{value: 1 ether}();

        vm.prank(user1);
        vm.expectRevert();
        vault.extendLock(0);
    }

    function testExtendLockFailsWithNoDeposit() public {
        vm.prank(user1);
        vm.expectRevert();
        vault.extendLock(1 days);
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function testIsUnlockedReturnsFalseBeforeUnlock() public {
        vm.prank(user1);
        vault.deposit{value: 1 ether}();

        assertFalse(vault.isUnlocked(user1));
    }

    function testIsUnlockedReturnsTrueAfterUnlock() public {
        vm.prank(user1);
        vault.deposit{value: 1 ether}();

        vm.warp(block.timestamp + LOCK_DURATION + 1);

        assertTrue(vault.isUnlocked(user1));
    }

    function testTimeUntilUnlockReturnsCorrectValue() public {
        vm.prank(user1);
        vault.deposit{value: 1 ether}();

        uint256 timeRemaining = vault.timeUntilUnlock(user1);
        assertEq(timeRemaining, LOCK_DURATION);

        vm.warp(block.timestamp + 12 hours);

        timeRemaining = vault.timeUntilUnlock(user1);
        assertEq(timeRemaining, LOCK_DURATION - 12 hours);
    }

    function testTimeUntilUnlockReturnsZeroWhenUnlocked() public {
        vm.prank(user1);
        vault.deposit{value: 1 ether}();

        vm.warp(block.timestamp + LOCK_DURATION + 1);

        assertEq(vault.timeUntilUnlock(user1), 0);
    }

    function testCalculatePenaltyReturnsCorrectFee() public {
        vm.prank(user1);
        vault.deposit{value: 1 ether}();

        uint256 penalty = vault.calculatePenalty(user1);
        assertEq(penalty, 0.1 ether); // 10% of 1 ether
    }

    function testCalculatePenaltyReturnsZeroWhenUnlocked() public {
        vm.prank(user1);
        vault.deposit{value: 1 ether}();

        vm.warp(block.timestamp + LOCK_DURATION + 1);

        uint256 penalty = vault.calculatePenalty(user1);
        assertEq(penalty, 0);
    }
}
