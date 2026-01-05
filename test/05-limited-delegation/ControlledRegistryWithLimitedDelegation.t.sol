// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import "lib/forge-std/src/Test.sol";
import "../../src/05-limited-delegation/ControlledRegistryWithLimitedDelegation.sol";

contract ControlledRegistryWithLimitedDelegationTest is Test {
    ControlledRegistryWithLimitedDelegation registry;

    address owner = address(this);
    address user = address(0xA11CE);
    address delegate = address(0xBEEF);
    address attacker = address(0xBAD);

    function setUp() public {
        registry = new ControlledRegistryWithLimitedDelegation();
        registry.registerUser(user);
    }

    /*//////////////////////////////////////////////////////////////
                                OWNER
    //////////////////////////////////////////////////////////////*/

    function testOwnerIsDeployer() public {
        assertEq(registry.i_owner(), owner);
    }

    function testNonOwnerCannotRegisterUser() public {
        vm.prank(attacker);
        vm.expectRevert(
            ControlledRegistryWithLimitedDelegation.NotOwner.selector
        );
        registry.registerUser(attacker);
    }

    /*//////////////////////////////////////////////////////////////
                        DELEGATION SETUP
    //////////////////////////////////////////////////////////////*/

    function testUserCanAssignDelegateWithAllowance() public {
        vm.prank(user);
        registry.setDelegate(delegate, 3);

        (address storedDelegate, uint256 remainingUses) = registry
            .userToDelegation(user);

        assertEq(storedDelegate, delegate);
        assertEq(remainingUses, 3);
    }

    function testUserCannotSelfDelegate() public {
        vm.prank(user);
        vm.expectRevert(
            ControlledRegistryWithLimitedDelegation
                .DelegateMustDifferFromUser
                .selector
        );
        registry.setDelegate(user, 1);
    }

    function testUserCannotAssignZeroAllowance() public {
        vm.prank(user);
        vm.expectRevert(
            ControlledRegistryWithLimitedDelegation.InvalidAllowance.selector
        );
        registry.setDelegate(delegate, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        DELEGATED ACTIONS
    //////////////////////////////////////////////////////////////*/

    function testDelegateCanUpdateValueAndConsumesAllowance() public {
        vm.prank(user);
        registry.setDelegate(delegate, 2);

        vm.prank(delegate);
        registry.setDelegateNumber(user, 42);

        assertEq(registry.userToValue(user), 42);

        (, uint256 remainingUses) = registry.userToDelegation(user);
        assertEq(remainingUses, 1);
    }

    function testDelegateCannotActWhenAllowanceIsZero() public {
        vm.prank(user);
        registry.setDelegate(delegate, 1);

        vm.prank(delegate);
        registry.setDelegateNumber(user, 10);

        vm.prank(delegate);
        vm.expectRevert(
            ControlledRegistryWithLimitedDelegation.NoRemainingUses.selector
        );
        registry.setDelegateNumber(user, 20);
    }

    function testNonDelegateCannotAct() public {
        vm.prank(user);
        registry.setDelegate(delegate, 1);

        vm.prank(attacker);
        vm.expectRevert(
            ControlledRegistryWithLimitedDelegation
                .NotAuthorizedDelegate
                .selector
        );
        registry.setDelegateNumber(user, 1);
    }

    /*//////////////////////////////////////////////////////////////
                            REVOCATION
    //////////////////////////////////////////////////////////////*/

    function testUserCanRevokeDelegation() public {
        vm.prank(user);
        registry.setDelegate(delegate, 2);

        vm.prank(user);
        registry.revokeDelegate();

        (address storedDelegate, uint256 remainingUses) = registry
            .userToDelegation(user);

        assertEq(storedDelegate, address(0));
        assertEq(remainingUses, 0);
    }

    function testRevokedDelegateCannotAct() public {
        vm.prank(user);
        registry.setDelegate(delegate, 1);

        vm.prank(user);
        registry.revokeDelegate();

        vm.prank(delegate);
        vm.expectRevert(
            ControlledRegistryWithLimitedDelegation
                .NotAuthorizedDelegate
                .selector
        );
        registry.setDelegateNumber(user, 5);
    }
}
