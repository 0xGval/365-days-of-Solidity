// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

import "lib/forge-std/src/Test.sol";
import "../../src/01-basics/ControlledStorage.sol";

contract ControlledStorageTest is Test {
    /// @notice Instance of the contract under test
    ControlledStorage storageContract;

    /// @notice Deploy a fresh contract instance before each test
    function setUp() public {
        storageContract = new ControlledStorage();
    }

    /// @notice Verifies that the initial stored value is zero after deployment
    function testInitialValueIsZero() public {
        uint256 value = storageContract.number();
        assertEq(value, 0);
    }

    /// @notice Verifies that the deployer is correctly set as the owner
    function testOwnerIsDeployer() public {
        address owner = storageContract.i_owner();
        assertEq(owner, address(this));
    }

    /// @notice Verifies that non-owner addresses cannot update the stored value
    function testNonOwnerCannotUpdate() public {
        address nonOwner = address(0xBEEF);

        vm.prank(nonOwner);
        vm.expectRevert(ControlledStorage.NotOwner.selector);

        storageContract.updateNumber(123);
    }
}
