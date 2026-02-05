// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "../../../../util/Imports.sol";
import "../../../../NexusTestBase.t.sol";

/// @title TestERC4337Account_EntryPoint
/// @notice Tests the correct EntryPoint address for ERC4337 accounts.
contract TestERC4337Account_EntryPoint is NexusTestBase {
    /// @notice Initializes the testing environment.
    function setUp() public virtual override {
        init();
    }

    /// @notice Tests if the correct EntryPoint address is returned for different accounts.
    function test_EntryPointAddressIsCorrect() public {
        assertEq(BOB_ACCOUNT.entryPoint(), address(ENTRYPOINT), "Should return the correct EntryPoint address");
        assertEq(ALICE_ACCOUNT.entryPoint(), address(ENTRYPOINT), "Should return the correct EntryPoint address");
        assertEq(CHARLIE_ACCOUNT.entryPoint(), address(ENTRYPOINT), "Should return the correct EntryPoint address");
    }
}
