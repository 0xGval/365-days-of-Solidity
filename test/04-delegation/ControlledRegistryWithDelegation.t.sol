// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import "lib/forge-std/src/Test.sol";
import "../../src/04-delegation/ControlledRegistryWithDelegation.sol";

contract ControlledRegistryWithDelegationTest is Test {
    ControlledRegistryWithDelegation registry;

    address owner = address(this);
    address user = address(0xA11CE);
    address delegate = address(0xBEEF);
    address attacker = address(0xBAD);

    function setUp() public {
        registry = new ControlledRegistryWithDelegation();
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
        vm.expectRevert(ControlledRegistryWithDelegation.NotOwner.selector);
        registry.registerUser(attacker);
    }

    /*//////////////////////////////////////////////////////////////
                            DELEGATION
    //////////////////////////////////////////////////////////////*/

    function testUserCanAssignDelegate() public {
        vm.prank(user);
        registry.setDelegate(delegate);

        assertEq(registry.userToDelegate(user), delegate);
    }

    function testUserCannotSelfDelegate() public {
        vm.prank(user);
        vm.expectRevert(
            ControlledRegistryWithDelegation
                .DelegateAddressMustDifferFromUserAddress
                .selector
        );
        registry.setDelegate(user);
    }

    /*//////////////////////////////////////////////////////////////
                        DELEGATED ACTIONS
    //////////////////////////////////////////////////////////////*/

    function testDelegateCanUpdateUserValue() public {
        vm.prank(user);
        registry.setDelegate(delegate);

        vm.prank(delegate);
        registry.updateNumberDelegate(user, 42);

        assertEq(registry.userToValue(user), 42);
    }

    function testNonDelegateCannotUpdateUserValue() public {
        vm.prank(user);
        registry.setDelegate(delegate);

        vm.prank(attacker);
        vm.expectRevert(
            ControlledRegistryWithDelegation
                .MsgSenderIsNotTargetUserDelegate
                .selector
        );
        registry.updateNumberDelegate(user, 1);
    }

    function testRevokedDelegateLosesPermissionImmediately() public {
        vm.prank(user);
        registry.setDelegate(delegate);

        vm.prank(user);
        registry.revokeDelegate();

        vm.prank(delegate);
        vm.expectRevert(
            ControlledRegistryWithDelegation
                .MsgSenderIsNotTargetUserDelegate
                .selector
        );
        registry.updateNumberDelegate(user, 1);
    }
}
