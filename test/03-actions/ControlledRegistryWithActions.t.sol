// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import "lib/forge-std/src/Test.sol";
import "../../src/03-actions/ControlledRegistryWithActions.sol";

contract ControlledRegistryWithActionsTest is Test {
    ControlledRegistryWithActions registry;

    address owner = address(this);
    address user = address(0xBEEF);

    function setUp() public {
        registry = new ControlledRegistryWithActions();
    }

    /*//////////////////////////////////////////////////////////////
                            DEPLOYMENT
    //////////////////////////////////////////////////////////////*/

    function testOwnerIsDeployer() public {
        assertEq(registry.i_owner(), owner);
    }

    /*//////////////////////////////////////////////////////////////
                            REGISTRATION
    //////////////////////////////////////////////////////////////*/

    function testOwnerCanRegisterUser() public {
        registry.registerUser(user);

        assertTrue(registry.isRegistered(user));
        assertEq(registry.values(user), registry.defaultValue());
    }

    function testCannotRegisterSameUserTwice() public {
        registry.registerUser(user);

        vm.expectRevert(
            ControlledRegistryWithActions.UserAlreadyRegistered.selector
        );
        registry.registerUser(user);
    }

    /*//////////////////////////////////////////////////////////////
                            USER ACTIONS
    //////////////////////////////////////////////////////////////*/

    function testRegisteredUserCanUpdateOwnValue() public {
        registry.registerUser(user);

        vm.prank(user);
        registry.updateNumber(42);

        assertEq(registry.values(user), 42);
    }

    function testNonRegisteredUserCannotUpdate() public {
        vm.prank(user);
        vm.expectRevert(
            ControlledRegistryWithActions.UserNotRegistered.selector
        );
        registry.updateNumber(42);
    }

    function testUserCannotUpdateWithSameValue() public {
        registry.registerUser(user);

        vm.prank(user);
        registry.updateNumber(42);

        vm.prank(user);
        vm.expectRevert(
            ControlledRegistryWithActions
                .NewNumberMustDifferFromOldNumber
                .selector
        );
        registry.updateNumber(42);
    }
}
