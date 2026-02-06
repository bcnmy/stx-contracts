// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { StxValidator_Unit_Base_Test } from "./StxValidator_Unit_Base_Test.t.sol";

/// @title StxValidator Initialization State Tests
/// @notice Tests for isInitialized functionality via non-onInstall paths
/// @dev Tests that are specific to isInitialized state changes via addConfig, setOwnershipData, etc.
///      onInstall/onUninstall lifecycle tests are in StxValidator_onInstall_onUninstall_Test.t.sol
contract StxValidator_InitializationState_Test is StxValidator_Unit_Base_Test {
    /*//////////////////////////////////////////////////////////////////////////
                              BASIC INITIALIZATION TESTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Test isInitialized returns false for uninitialized account
    function test_isInitialized_returnsFalseForUninitializedAccount() public view {
        assertFalse(stxValidator.isInitialized(smartAccount));
    }

    /// @notice Test initialization state is account-isolated
    function test_isInitialized_accountIsolation() public {
        _initializeValidator(); // Initialize smartAccount

        assertTrue(stxValidator.isInitialized(smartAccount));
        assertFalse(stxValidator.isInitialized(anotherSmartAccount));
    }

    /*//////////////////////////////////////////////////////////////////////////
                    INITIALIZATION VIA CUSTOM CONFIG TESTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Test isInitialized returns true when only custom config is enabled (no default validators)
    function test_isInitialized_returnsTrueWithOnlyCustomConfig() public {
        // Add custom config without going through onInstall
        vm.prank(smartAccount);
        stxValidator.addConfig(customConfigId, customStxModeVerifier, customStatelessValidator);

        assertTrue(stxValidator.isInitialized(smartAccount));
    }

    /// @notice Test isInitialized returns false after deleting the only custom config
    function test_isInitialized_returnsFalseAfterDeletingOnlyCustomConfig() public {
        // Add custom config
        vm.startPrank(smartAccount);
        stxValidator.addConfig(customConfigId, customStxModeVerifier, customStatelessValidator);
        assertTrue(stxValidator.isInitialized(smartAccount));

        // Delete the config
        stxValidator.deleteConfig(customConfigId);
        vm.stopPrank();

        assertFalse(stxValidator.isInitialized(smartAccount));
    }

    /// @notice Test isInitialized remains true if one of multiple custom configs is deleted
    function test_isInitialized_remainsTrueIfOtherCustomConfigsExist() public {
        bytes32 anotherConfigId = keccak256("another-config");

        vm.startPrank(smartAccount);
        stxValidator.addConfig(customConfigId, customStxModeVerifier, customStatelessValidator);
        stxValidator.addConfig(anotherConfigId, address(0xCAFE2), address(0xBEEF2));

        assertTrue(stxValidator.isInitialized(smartAccount));

        // Delete one config
        stxValidator.deleteConfig(customConfigId);
        vm.stopPrank();

        // Still initialized because another config exists
        assertTrue(stxValidator.isInitialized(smartAccount));
    }

    /*//////////////////////////////////////////////////////////////////////////
                    INITIALIZATION VIA OWNERSHIP DATA TESTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Test isInitialized returns true when EOA ownership data is set directly
    function test_isInitialized_returnsTrueWhenEOAOwnershipDataSet() public {
        vm.prank(smartAccount);
        stxValidator.setOwnershipData(address(eoaStatelessValidator), abi.encodePacked(owner.addr));

        assertTrue(stxValidator.isInitialized(smartAccount));
    }

    /// @notice Test isInitialized returns true when P256 ownership data is set directly
    function test_isInitialized_returnsTrueWhenP256OwnershipDataSet() public {
        bytes memory p256PublicKey = abi.encodePacked(bytes32(uint256(1)), bytes32(uint256(2)));

        vm.prank(smartAccount);
        stxValidator.setOwnershipData(address(p256StatelessValidator), p256PublicKey);

        assertTrue(stxValidator.isInitialized(smartAccount));
    }

    /// @notice Test isInitialized returns true when SafeAccountSubmodule ownership data is set directly
    function test_isInitialized_returnsTrueWhenSafeOwnershipDataSet() public {
        vm.prank(smartAccount);
        stxValidator.setOwnershipData(address(safeAccountSubmodule), abi.encodePacked(makeAddr("safe")));

        assertTrue(stxValidator.isInitialized(smartAccount));
    }

    /// @notice Test isInitialized returns false after cleaning EOA ownership data (when no other data exists)
    function test_isInitialized_returnsFalseAfterCleaningOnlyOwnershipData() public {
        vm.startPrank(smartAccount);
        stxValidator.setOwnershipData(address(eoaStatelessValidator), abi.encodePacked(owner.addr));
        assertTrue(stxValidator.isInitialized(smartAccount));

        stxValidator.cleanOwnershipData(address(eoaStatelessValidator));
        vm.stopPrank();

        assertFalse(stxValidator.isInitialized(smartAccount));
    }

    /*//////////////////////////////////////////////////////////////////////////
                              EDGE CASES
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Test isInitialized with zero address
    function test_isInitialized_zeroAddress() public view {
        assertFalse(stxValidator.isInitialized(address(0)));
    }

    /*//////////////////////////////////////////////////////////////////////////
                              FUZZ TESTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Fuzz test that any account starts uninitialized
    function testFuzz_isInitialized_anyAccountStartsUninitialized(address account) public view {
        assertFalse(stxValidator.isInitialized(account));
    }
}
