// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "./util/Imports.sol";
import "./util/EventsAndErrors.sol";

/// @title NexusTestBase - Base contract for testing Nexus smart account functionalities
/// @notice This contract inherits from TestHelper to provide common setup and utilities for Nexus tests
abstract contract NexusTestBase is TestHelper {
    /// @notice Modifier to check Paymaster balance before and after transaction
    /// @param paymaster The paymaster to check the balance for
    modifier checkPaymasterBalance(address paymaster) {
        uint256 balanceBefore = ENTRYPOINT.balanceOf(paymaster);
        _;
        uint256 balanceAfter = ENTRYPOINT.balanceOf(paymaster);
        assertLt(balanceAfter, balanceBefore, "Paymaster deposit not used");
    }

    /// @notice Initializes the testing environment
    function init() internal virtual {
        setupTestEnvironment();
    }

    receive() external payable { }
}
