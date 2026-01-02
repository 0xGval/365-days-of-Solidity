// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import "lib/forge-std/src/Test.sol";
import "../../src/02-basics/ControlledRegistry.sol";

contract ControlledRegistryTest is Test {
    ControlledRegistry registry;

    function setUp() public {
        registry = new ControlledRegistry();
    }

    /// @notice Verifies that the deployer is correctly set as the owner
    function testOwnerIsDeployer() public {
        address owner = registry.i_owner();
        assertEq(owner, address(this));
    }

    /// @notice Verifies that the owner can register a new user with a value
    function testOwnerCanRegisterUser() public {
        address user = address(0xBEEF);
        uint256 value = 42;

        registry.registerNumber(user, value);

        bool registered = registry.isRegistered(user);
        uint256 storedValue = registry.registry(user);

        assertTrue(registered);
        assertEq(storedValue, value);
    }

    /// @notice Verifies that the same user cannot be registered twice
    function testCannotRegisterSameUserTwice() public {
        address user = address(0xBEEF);

        registry.registerNumber(user, 1);

        vm.expectRevert(ControlledRegistry.UserAlreadyRegistered.selector);
        registry.registerNumber(user, 2);
    }

    /// @notice Verifies that the owner can update the value of a registered user
    function testOwnerCanUpdateRegisteredUser() public {
        address user = address(0xBEEF);

        registry.registerNumber(user, 10);
        registry.updateNumber(user, 20);

        uint256 updatedValue = registry.registry(user);
        assertEq(updatedValue, 20);
    }

    /// @notice Verifies that a non-owner cannot register or update users
    function testNonOwnerCannotRegisterOrUpdate() public {
        address nonOwner = address(0xCAFE);
        address user = address(0xBEEF);

        vm.prank(nonOwner);
        vm.expectRevert(ControlledRegistry.NotOwner.selector);
        registry.registerNumber(user, 1);

        registry.registerNumber(user, 1);

        vm.prank(nonOwner);
        vm.expectRevert(ControlledRegistry.NotOwner.selector);
        registry.updateNumber(user, 2);
    }
}
