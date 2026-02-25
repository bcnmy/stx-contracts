// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { StxValidator_Unit_Base_Test } from "./StxValidator_Unit_Base_Test.t.sol";
import { StxValidator } from "contracts/validators/stx-validator/StxValidator.sol";
import { ConfigManager, ValidationConfig } from "contracts/validators/stx-validator/ConfigManager.sol";

/// @title StxValidator Config Management Unit Tests
/// @notice Unit tests for config management functionality (addConfig, replaceConfig, deleteConfig, ownership data)
contract StxValidator_ConfigManagement_Test is StxValidator_Unit_Base_Test {
    function setUp() public override {
        super.setUp();

        // Initialize validator for smartAccount
        _initializeValidator();
    }

    // ==================== addConfig Tests ====================

    /// @notice Test addConfig stores new config correctly
    function test_addConfig_storesNewConfig() public {
        vm.prank(smartAccount);
        stxValidator.addConfig(customConfigId, customStxModeVerifier, customStatelessValidator);

        // Verify config was stored
        ValidationConfig memory config = stxValidator.getConfigData(smartAccount, customConfigId);
        assertEq(config.stxModeVerifierAddress, customStxModeVerifier);
        assertEq(config.statelessValidatorAddress, customStatelessValidator);

        // Verify config is marked as enabled
        assertTrue(stxValidator.isConfigEnabled(smartAccount, customConfigId));
    }

    /// @notice Test addConfig emits ConfigAdded event
    function test_addConfig_emitsConfigAddedEvent() public {
        vm.prank(smartAccount);
        vm.expectEmit(true, true, false, false);
        emit ConfigAdded(customConfigId, smartAccount);
        stxValidator.addConfig(customConfigId, customStxModeVerifier, customStatelessValidator);
    }

    /// @notice Test addConfig reverts when config already enabled
    function test_addConfig_revertWhen_configAlreadyEnabled() public {
        // Add config first time
        vm.prank(smartAccount);
        stxValidator.addConfig(customConfigId, customStxModeVerifier, customStatelessValidator);

        // Try to add same config again
        vm.prank(smartAccount);
        vm.expectRevert(ConfigManager.ConfigAlreadyEnabled.selector);
        stxValidator.addConfig(customConfigId, customStxModeVerifier, customStatelessValidator);
    }

    /// @notice Test addConfig reverts when stxModeVerifier is zero address
    function test_addConfig_revertWhen_stxModeVerifierIsZeroAddress() public {
        vm.prank(smartAccount);
        vm.expectRevert(ConfigManager.StxModeVerifierAddressCannotBeZeroAddress.selector);
        stxValidator.addConfig(customConfigId, address(0), customStatelessValidator);
    }

    /// @notice Test addConfig reverts when statelessValidator is zero address
    function test_addConfig_revertWhen_statelessValidatorIsZeroAddress() public {
        vm.prank(smartAccount);
        vm.expectRevert(ConfigManager.StatelessValidatorAddressCannotBeZeroAddress.selector);
        stxValidator.addConfig(customConfigId, customStxModeVerifier, address(0));
    }

    // ==================== replaceConfig Tests ====================

    /// @notice Test replaceConfig updates existing config and clears old ownership data when validator changes
    function test_replaceConfig_updatesConfigAndClearsOldOwnershipData() public {
        // Add config with ownership data
        vm.startPrank(smartAccount);
        stxValidator.addConfig(customConfigId, customStxModeVerifier, customStatelessValidator);
        stxValidator.setOwnershipData(customStatelessValidator, abi.encodePacked(owner.addr));
        vm.stopPrank();

        // Verify ownership data exists for old validator
        bytes memory oldOwnershipData = stxValidator.getOwnershipData(smartAccount, customStatelessValidator);
        assertEq(oldOwnershipData, abi.encodePacked(owner.addr));

        // New addresses for replacement
        address newStxModeVerifier = address(0xCAFE2);
        address newStatelessValidator = address(0xBEEF2);
        bytes memory newOwnershipData = abi.encodePacked(address(0x9999));

        // Replace config
        vm.prank(smartAccount);
        stxValidator.replaceConfig(customConfigId, newStxModeVerifier, newStatelessValidator, newOwnershipData);

        // Verify config was updated
        ValidationConfig memory config = stxValidator.getConfigData(smartAccount, customConfigId);
        assertEq(config.stxModeVerifierAddress, newStxModeVerifier);
        assertEq(config.statelessValidatorAddress, newStatelessValidator);

        // Verify old validator's ownership data was cleared
        bytes memory clearedOwnershipData = stxValidator.getOwnershipData(smartAccount, customStatelessValidator);
        assertEq(clearedOwnershipData, "");

        // Verify new validator has ownership data
        bytes memory storedNewOwnershipData = stxValidator.getOwnershipData(smartAccount, newStatelessValidator);
        assertEq(storedNewOwnershipData, newOwnershipData);
    }

    /// @notice Test replaceConfig emits ConfigReplaced event
    function test_replaceConfig_emitsConfigReplacedEvent() public {
        // Add initial config
        vm.prank(smartAccount);
        stxValidator.addConfig(customConfigId, customStxModeVerifier, customStatelessValidator);

        // Replace config
        vm.prank(smartAccount);
        vm.expectEmit(true, true, false, false);
        emit ConfigReplaced(customConfigId, smartAccount);
        stxValidator.replaceConfig(customConfigId, address(0xCAFE2), address(0xBEEF2), "");
    }

    /// @notice Test replaceConfig updates ownership data when stateless validator unchanged
    function test_replaceConfig_updatesOwnershipDataWhenSameStatelessValidator() public {
        // Add config with ownership data
        vm.startPrank(smartAccount);
        stxValidator.addConfig(customConfigId, customStxModeVerifier, customStatelessValidator);
        stxValidator.setOwnershipData(customStatelessValidator, abi.encodePacked(owner.addr));
        vm.stopPrank();

        // Replace config with same stateless validator but new ownership data
        bytes memory newOwnershipData = abi.encodePacked(address(0x9999));
        address newStxModeVerifier = address(0xCAFE2);

        vm.prank(smartAccount);
        stxValidator.replaceConfig(customConfigId, newStxModeVerifier, customStatelessValidator, newOwnershipData);

        // Verify stx mode verifier was updated
        ValidationConfig memory config = stxValidator.getConfigData(smartAccount, customConfigId);
        assertEq(config.stxModeVerifierAddress, newStxModeVerifier);
        assertEq(config.statelessValidatorAddress, customStatelessValidator);

        // Verify ownership data was updated (not cleared, just overwritten)
        bytes memory storedOwnershipData = stxValidator.getOwnershipData(smartAccount, customStatelessValidator);
        assertEq(storedOwnershipData, newOwnershipData);
    }

    /// @notice Test replaceConfig reverts when config not enabled
    function test_replaceConfig_revertWhen_configNotEnabled() public {
        vm.prank(smartAccount);
        vm.expectRevert(ConfigManager.ConfigNotEnabled.selector);
        stxValidator.replaceConfig(customConfigId, customStxModeVerifier, customStatelessValidator, "");
    }

    /// @notice Test replaceConfig reverts when stxModeVerifier is zero address
    function test_replaceConfig_revertWhen_stxModeVerifierIsZeroAddress() public {
        // Add config first
        vm.prank(smartAccount);
        stxValidator.addConfig(customConfigId, customStxModeVerifier, customStatelessValidator);

        // Try to replace with zero stxModeVerifier
        vm.prank(smartAccount);
        vm.expectRevert(ConfigManager.StxModeVerifierAddressCannotBeZeroAddress.selector);
        stxValidator.replaceConfig(customConfigId, address(0), customStatelessValidator, "");
    }

    /// @notice Test replaceConfig reverts when statelessValidator is zero address
    function test_replaceConfig_revertWhen_statelessValidatorIsZeroAddress() public {
        // Add config first
        vm.prank(smartAccount);
        stxValidator.addConfig(customConfigId, customStxModeVerifier, customStatelessValidator);

        // Try to replace with zero statelessValidator
        vm.prank(smartAccount);
        vm.expectRevert(ConfigManager.StatelessValidatorAddressCannotBeZeroAddress.selector);
        stxValidator.replaceConfig(customConfigId, customStxModeVerifier, address(0), "");
    }

    // ==================== deleteConfig Tests ====================

    /// @notice Test deleteConfig removes config from storage and enabledCustomConfigs set
    function test_deleteConfig_removesConfig() public {
        // Add config
        vm.prank(smartAccount);
        stxValidator.addConfig(customConfigId, customStxModeVerifier, customStatelessValidator);

        // Verify config exists
        assertTrue(stxValidator.isConfigEnabled(smartAccount, customConfigId));

        // Delete config
        vm.prank(smartAccount);
        stxValidator.deleteConfig(customConfigId);

        // Verify config was removed
        assertFalse(stxValidator.isConfigEnabled(smartAccount, customConfigId));
        ValidationConfig memory config = stxValidator.getConfigData(smartAccount, customConfigId);
        assertEq(config.stxModeVerifierAddress, address(0));
        assertEq(config.statelessValidatorAddress, address(0));
    }

    /// @notice Test deleteConfig emits ConfigDeleted event
    function test_deleteConfig_emitsConfigDeletedEvent() public {
        // Add config
        vm.prank(smartAccount);
        stxValidator.addConfig(customConfigId, customStxModeVerifier, customStatelessValidator);

        // Delete config
        vm.prank(smartAccount);
        vm.expectEmit(true, true, false, false);
        emit ConfigDeleted(customConfigId, smartAccount);
        stxValidator.deleteConfig(customConfigId);
    }

    /// @notice Test deleteConfig does NOT clear ownership data (may be shared with other configs)
    function test_deleteConfig_doesNotClearOwnershipData() public {
        // Add config with ownership data
        vm.startPrank(smartAccount);
        stxValidator.addConfig(customConfigId, customStxModeVerifier, customStatelessValidator);
        stxValidator.setOwnershipData(customStatelessValidator, abi.encodePacked(owner.addr));
        vm.stopPrank();

        // Delete config
        vm.prank(smartAccount);
        stxValidator.deleteConfig(customConfigId);

        // Verify ownership data still exists (intentionally not cleared)
        bytes memory storedOwnershipData = stxValidator.getOwnershipData(smartAccount, customStatelessValidator);
        assertEq(storedOwnershipData, abi.encodePacked(owner.addr));
    }

    /// @notice Test deleteConfig reverts when config not enabled
    function test_deleteConfig_revertWhen_configNotEnabled() public {
        vm.prank(smartAccount);
        vm.expectRevert(ConfigManager.ConfigNotEnabled.selector);
        stxValidator.deleteConfig(customConfigId);
    }

    // ==================== getConfigData Tests ====================

    /// @notice Test getConfigData returns correct config
    function test_getConfigData_returnsCorrectConfig() public {
        vm.prank(smartAccount);
        stxValidator.addConfig(customConfigId, customStxModeVerifier, customStatelessValidator);

        ValidationConfig memory config = stxValidator.getConfigData(smartAccount, customConfigId);
        assertEq(config.stxModeVerifierAddress, customStxModeVerifier);
        assertEq(config.statelessValidatorAddress, customStatelessValidator);
    }

    /// @notice Test getConfigData returns empty for non-existent config
    function test_getConfigData_returnsEmptyForNonExistentConfig() public view {
        ValidationConfig memory config = stxValidator.getConfigData(smartAccount, customConfigId);
        assertEq(config.stxModeVerifierAddress, address(0));
        assertEq(config.statelessValidatorAddress, address(0));
    }

    // ==================== isConfigEnabled Tests ====================

    /// @notice Test isConfigEnabled returns true for enabled config
    function test_isConfigEnabled_returnsTrueForEnabledConfig() public {
        vm.prank(smartAccount);
        stxValidator.addConfig(customConfigId, customStxModeVerifier, customStatelessValidator);

        assertTrue(stxValidator.isConfigEnabled(smartAccount, customConfigId));
    }

    /// @notice Test isConfigEnabled returns false for disabled/non-existent config
    function test_isConfigEnabled_returnsFalseForDisabledConfig() public {
        // Non-existent config
        assertFalse(stxValidator.isConfigEnabled(smartAccount, customConfigId));

        // Add and then delete config
        vm.prank(smartAccount);
        stxValidator.addConfig(customConfigId, customStxModeVerifier, customStatelessValidator);
        assertTrue(stxValidator.isConfigEnabled(smartAccount, customConfigId));

        vm.prank(smartAccount);
        stxValidator.deleteConfig(customConfigId);
        assertFalse(stxValidator.isConfigEnabled(smartAccount, customConfigId));
    }

    // ==================== setOwnershipData Tests ====================

    /// @notice Test setOwnershipData stores data correctly
    function test_setOwnershipData_storesData() public {
        bytes memory storedDataBefore = stxValidator.getOwnershipData(smartAccount, customStatelessValidator);
        assertEq(storedDataBefore, "");

        bytes memory newOwnershipData = abi.encodePacked(address(0x9999));

        vm.prank(smartAccount);
        stxValidator.setOwnershipData(customStatelessValidator, newOwnershipData);

        bytes memory storedData = stxValidator.getOwnershipData(smartAccount, customStatelessValidator);
        assertEq(storedData, newOwnershipData);
    }

    /// @notice Test setOwnershipData overwrites existing data
    function test_setOwnershipData_overwritesExistingData() public {
        bytes memory initialData = abi.encodePacked(owner.addr);
        bytes memory newData = abi.encodePacked(address(0x9999));

        vm.startPrank(smartAccount);
        stxValidator.setOwnershipData(customStatelessValidator, initialData);

        // Verify initial data
        bytes memory storedInitial = stxValidator.getOwnershipData(smartAccount, customStatelessValidator);
        assertEq(storedInitial, initialData);

        // Overwrite with new data
        stxValidator.setOwnershipData(customStatelessValidator, newData);
        vm.stopPrank();

        // Verify new data
        bytes memory storedNew = stxValidator.getOwnershipData(smartAccount, customStatelessValidator);
        assertEq(storedNew, newData);
    }

    // ==================== cleanOwnershipData Tests ====================

    /// @notice Test cleanOwnershipData clears data
    function test_cleanOwnershipData_clearsData() public {
        // Set ownership data
        vm.prank(smartAccount);
        stxValidator.setOwnershipData(customStatelessValidator, abi.encodePacked(owner.addr));

        // Verify data exists
        bytes memory storedData = stxValidator.getOwnershipData(smartAccount, customStatelessValidator);
        assertEq(storedData, abi.encodePacked(owner.addr));

        // Clean ownership data
        vm.prank(smartAccount);
        stxValidator.cleanOwnershipData(customStatelessValidator);

        // Verify data was cleared
        bytes memory clearedData = stxValidator.getOwnershipData(smartAccount, customStatelessValidator);
        assertEq(clearedData, "");
    }

    /// @notice Test cleanOwnershipData reverts when no data exists
    function test_cleanOwnershipData_revertWhen_noDataExists() public {
        // Try to clean non-existent ownership data
        vm.prank(smartAccount);
        vm.expectRevert(
            abi.encodeWithSelector(StxValidator.NoOwnershipDataExists.selector, customStatelessValidator, smartAccount)
        );
        stxValidator.cleanOwnershipData(customStatelessValidator);
    }

    // ==================== getOwnershipData Tests ====================

    /// @notice Test getOwnershipData returns stored data
    function test_getOwnershipData_returnsStoredData() public {
        bytes memory testData = abi.encodePacked(owner.addr);

        vm.prank(smartAccount);
        stxValidator.setOwnershipData(customStatelessValidator, testData);

        bytes memory storedData = stxValidator.getOwnershipData(smartAccount, customStatelessValidator);
        assertEq(storedData, testData);
    }

    /// @notice Test getOwnershipData returns smartAccount address for EOA validator with empty data (7702 fallback)
    function test_getOwnershipData_returnsSmartAccountAddressForEOAWithEmptyData() public view {
        // Use a different account that was not initialized (so no ownership data set)
        address uninitializedAccount = address(0x9876543210987654321098765432109876543210);

        // For EOA stateless validator with no ownership data set,
        // it should return the smart account address (7702 compatibility)
        bytes memory ownershipData = stxValidator.getOwnershipData(uninitializedAccount, address(eoaStatelessValidator));
        assertEq(ownershipData, abi.encodePacked(uninitializedAccount));
    }

    /// @notice Test getOwnershipData returns empty for P256 validator with empty data (no fallback)
    function test_getOwnershipData_returnsEmptyForP256WithEmptyData() public view {
        // Use a different account that was not initialized (so no ownership data set)
        address uninitializedAccount = address(0x9876543210987654321098765432109876543210);

        // For P256 stateless validator with no ownership data set,
        // it should return empty (no 7702 fallback)
        bytes memory ownershipData =
            stxValidator.getOwnershipData(uninitializedAccount, address(p256StatelessValidator));
        assertEq(ownershipData, "");
    }

    /// @notice Test getOwnershipData returns empty for custom validator with empty data (no fallback)
    function test_getOwnershipData_returnsEmptyForCustomValidatorWithEmptyData() public view {
        // Use a different account that was not initialized (so no ownership data set)
        address uninitializedAccount = address(0x9876543210987654321098765432109876543210);

        // For custom stateless validators with no ownership data set,
        // it should return empty (no 7702 fallback)
        bytes memory ownershipData = stxValidator.getOwnershipData(uninitializedAccount, customStatelessValidator);
        assertEq(ownershipData, "");
    }

    /// @notice Test getOwnershipData returns stored data even for EOA validator (overrides 7702 fallback)
    function test_getOwnershipData_returnsStoredDataForEOA_overrides7702Fallback() public view {
        // The ownership data was set during initialization (in setUp)
        bytes memory ownershipData = stxValidator.getOwnershipData(smartAccount, address(eoaStatelessValidator));
        assertEq(ownershipData, abi.encodePacked(owner.addr));

        // Not the smartAccount address (7702 fallback is NOT used when data exists)
        assertTrue(keccak256(ownershipData) != keccak256(abi.encodePacked(smartAccount)));
    }
}
