// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test, Vm } from "forge-std/Test.sol";
import { StxValidator } from "contracts/validators/stx-validator/StxValidator.sol";
import { SubmoduleAddresses, ValidationConfig } from "contracts/validators/stx-validator/ConfigManager.sol";
import { EOAStatelessValidator } from "contracts/validators/stx-validator/submodules/EOAStatelessValidator.sol";
import { NoStxModeVerifier } from "contracts/validators/stx-validator/submodules/NoStxModeVerifier.sol";
import { SimpleModeSubmodule } from "contracts/validators/stx-validator/submodules/SimpleModeSubmodule.sol";
import { PermitSubmodule } from "contracts/validators/stx-validator/submodules/PermitSubmodule.sol";
import { TxSubmodule } from "contracts/validators/stx-validator/submodules/TxSubmodule.sol";
import { SafeAccountSubmodule } from "contracts/validators/stx-validator/submodules/SafeAccountSubmodule.sol";
import { P256StatelessValidator } from "contracts/validators/stx-validator/submodules/p256/P256StatelessValidator.sol";

/// @title StxValidator Module Lifecycle Unit Tests
/// @notice Unit tests for onInstall and onUninstall functionality
contract StxValidator_onInstall_onUninstall_Test is Test {
    StxValidator internal stxValidator;

    EOAStatelessValidator internal eoaStatelessValidator;
    NoStxModeVerifier internal noStxModeVerifier;
    SimpleModeSubmodule internal simpleModeSubmodule;
    PermitSubmodule internal permitSubmodule;
    TxSubmodule internal txSubmodule;
    SafeAccountSubmodule internal safeAccountSubmodule;
    P256StatelessValidator internal p256StatelessValidator;

    Vm.Wallet internal owner;
    Vm.Wallet internal anotherOwner;
    address internal smartAccount;
    address internal anotherSmartAccount;

    // Custom config test data
    address internal customStxModeVerifier;
    address internal customStatelessValidator;
    bytes32 internal customConfigId;

    function setUp() public {
        // Deploy all submodules
        eoaStatelessValidator = new EOAStatelessValidator();
        noStxModeVerifier = new NoStxModeVerifier();
        simpleModeSubmodule = new SimpleModeSubmodule();
        permitSubmodule = new PermitSubmodule();
        txSubmodule = new TxSubmodule();
        safeAccountSubmodule = new SafeAccountSubmodule();
        p256StatelessValidator = new P256StatelessValidator();

        // Deploy StxValidator with all submodules
        stxValidator = new StxValidator(
            SubmoduleAddresses({
                noStxModeVerifier: address(noStxModeVerifier),
                simpleModeVerifier: address(simpleModeSubmodule),
                permitModeVerifier: address(permitSubmodule),
                txModeVerifier: address(txSubmodule),
                safeAccountSubmodule: address(safeAccountSubmodule),
                eoaStatelessValidator: address(eoaStatelessValidator),
                p256StatelessValidator: address(p256StatelessValidator)
            })
        );

        // Create test wallets
        owner = vm.createWallet("owner");
        anotherOwner = vm.createWallet("anotherOwner");

        // Use deterministic addresses for smart accounts
        smartAccount = address(0x1234567890123456789012345678901234567890);
        anotherSmartAccount = address(0x0987654321098765432109876543210987654321);

        // Setup custom config test data
        customStxModeVerifier = address(0xCAFE);
        customStatelessValidator = address(0xBEEF);
        customConfigId = keccak256("custom-config-1");
    }

    // ==================== onInstall Tests ====================

    /// @notice Test installing with EOA stateless validator stores ownership data correctly
    function test_onInstall_withEOAStatelessValidator_setsOwnershipData() public {
        bytes memory installData = abi.encodePacked(
            address(eoaStatelessValidator), // stateless validator address
            uint8(0), // no safe senders
            abi.encodePacked(owner.addr) // ownership data (owner address)
        );

        vm.prank(smartAccount);
        stxValidator.onInstall(installData);

        // Verify initialized
        assertTrue(stxValidator.isInitialized(smartAccount));
        // Verify ownership data (must call as smartAccount since getOwnershipData uses msg.sender)
        bytes memory ownershipData = stxValidator.getOwnershipData(smartAccount, address(eoaStatelessValidator));
        assertEq(ownershipData, abi.encodePacked(owner.addr));
    }

    /// @notice Test installing with P256 stateless validator stores public key data
    function test_onInstall_withP256StatelessValidator_setsOwnershipData() public {
        // P256 ownership data is pubkey x and y (64 bytes)
        uint256 pubKeyX = uint256(keccak256("pubKeyX"));
        uint256 pubKeyY = uint256(keccak256("pubKeyY"));
        bytes memory p256OwnershipData = abi.encodePacked(pubKeyX, pubKeyY);

        bytes memory installData = abi.encodePacked(
            address(p256StatelessValidator), // stateless validator address
            uint8(0), // no safe senders
            p256OwnershipData // ownership data (pubkey x, y)
        );

        vm.prank(smartAccount);
        stxValidator.onInstall(installData);

        // Verify initialized
        assertTrue(stxValidator.isInitialized(smartAccount));
        // Verify ownership data (must call as smartAccount since getOwnershipData uses msg.sender)
        bytes memory ownershipData = stxValidator.getOwnershipData(smartAccount, address(p256StatelessValidator));
        assertEq(ownershipData, p256OwnershipData);
    }

    /// @notice Test installing with Safe account submodule stores ownership data
    function test_onInstall_withSafeAccountSubmodule_setsOwnershipData() public {
        // Safe ownership data: safe account address + smart account address
        address safeAccount = address(0x5afe5afE5afE5afE5afE5aFe5aFe5Afe5Afe5AfE);
        bytes memory safeOwnershipData = abi.encodePacked(safeAccount, smartAccount);

        bytes memory installData = abi.encodePacked(
            address(safeAccountSubmodule), // stateless validator address
            uint8(0), // no safe senders
            safeOwnershipData // ownership data
        );

        vm.prank(smartAccount);
        stxValidator.onInstall(installData);

        // Verify initialized
        assertTrue(stxValidator.isInitialized(smartAccount));
        // Verify ownership data (must call as smartAccount since getOwnershipData uses msg.sender)
        bytes memory ownershipData = stxValidator.getOwnershipData(smartAccount, address(safeAccountSubmodule));
        assertEq(ownershipData, safeOwnershipData);
    }

    /// @notice Test installing with custom config stores config and ownership data
    /// @dev Note: onInstall does NOT emit ConfigAdded event (only addConfig does)
    function test_onInstall_withCustomConfig_storesConfigAndOwnershipData() public {
        bytes memory ownershipData = abi.encodePacked(owner.addr);

        // Custom config format: [20 bytes stateless validator][20 bytes stx mode verifier][32 bytes configId][1 byte
        // safeSendersCount][ownership data]
        bytes memory installData = abi.encodePacked(
            customStatelessValidator, // stateless validator address (non-default = custom)
            customStxModeVerifier, // stx mode verifier address
            customConfigId, // config id
            uint8(0), // no safe senders
            ownershipData // ownership data
        );

        vm.prank(smartAccount);
        stxValidator.onInstall(installData);

        // Verify config was stored
        ValidationConfig memory config = stxValidator.getConfigData(smartAccount, customConfigId);
        assertEq(config.stxModeVerifierAddress, customStxModeVerifier);
        assertEq(config.statelessValidatorAddress, customStatelessValidator);

        // Verify initialized
        assertTrue(stxValidator.isInitialized(smartAccount));
        // Verify ownership data (must call as smartAccount since getOwnershipData uses msg.sender)
        bytes memory retrievedOwnershipData = stxValidator.getOwnershipData(smartAccount, customStatelessValidator);
        assertEq(retrievedOwnershipData, ownershipData);
    }

    /// @notice Test installing with safe senders adds them to the list
    function test_onInstall_withSafeSenders_addsSafeSendersToList() public {
        address safeSender1 = address(0x1111);
        address safeSender2 = address(0x2222);
        address safeSender3 = address(0x3333);

        bytes memory installData = abi.encodePacked(
            address(eoaStatelessValidator), // stateless validator address
            uint8(3), // 3 safe senders
            safeSender1,
            safeSender2,
            safeSender3,
            abi.encodePacked(owner.addr) // ownership data
        );

        vm.prank(smartAccount);
        stxValidator.onInstall(installData);

        // Verify safe senders were added
        assertTrue(stxValidator.isSafeSender(safeSender1, smartAccount));
        assertTrue(stxValidator.isSafeSender(safeSender2, smartAccount));
        assertTrue(stxValidator.isSafeSender(safeSender3, smartAccount));

        // Verify non-added address is not a safe sender
        assertFalse(stxValidator.isSafeSender(address(0x9999), smartAccount));

        // Verify ownership data (must call as smartAccount since getOwnershipData uses msg.sender)
        bytes memory retrievedOwnershipData =
            stxValidator.getOwnershipData(smartAccount, address(eoaStatelessValidator));
        assertEq(retrievedOwnershipData, abi.encodePacked(owner.addr));

        // Verify module is initialized
        assertTrue(stxValidator.isInitialized(smartAccount));
    }

    /// @notice Test installing with custom config and safe senders adds them to the list
    function test_onInstall_withCustomConfigAndSafeSenders_addsSafeSendersToList() public {
        address safeSender1 = address(0x1111);
        address safeSender2 = address(0x2222);
        address safeSender3 = address(0x3333);

        bytes memory installData = abi.encodePacked(
            customStatelessValidator, // stateless validator address
            customStxModeVerifier, // stx mode verifier address
            customConfigId, // config id
            uint8(3), // 3 safe senders
            safeSender1,
            safeSender2,
            safeSender3,
            abi.encodePacked(owner.addr) // ownership data
        );

        vm.prank(smartAccount);
        stxValidator.onInstall(installData);

        // Verify safe senders were added
        assertTrue(stxValidator.isSafeSender(safeSender1, smartAccount));
        assertTrue(stxValidator.isSafeSender(safeSender2, smartAccount));
        assertTrue(stxValidator.isSafeSender(safeSender3, smartAccount));

        // Verify ownership data (must call as smartAccount since getOwnershipData uses msg.sender)
        bytes memory retrievedOwnershipData = stxValidator.getOwnershipData(smartAccount, customStatelessValidator);
        assertEq(retrievedOwnershipData, abi.encodePacked(owner.addr));

        // Verify module is initialized
        assertTrue(stxValidator.isInitialized(smartAccount));
    }

    /// @notice Test onInstall reverts when already initialized
    function test_onInstall_revertWhen_alreadyInitialized() public {
        bytes memory installData =
            abi.encodePacked(address(eoaStatelessValidator), uint8(0), abi.encodePacked(owner.addr));

        // First install
        vm.prank(smartAccount);
        stxValidator.onInstall(installData);

        // Second install should revert
        vm.prank(smartAccount);
        vm.expectRevert(StxValidator.ModuleAlreadyInitialized.selector);
        stxValidator.onInstall(installData);
    }

    /// @notice Test onInstall reverts when data length is too short (< 20 bytes)
    function test_onInstall_revertWhen_dataLengthTooShort() public {
        bytes memory shortData = abi.encodePacked(bytes19(0)); // only 19 bytes

        vm.prank(smartAccount);
        vm.expectRevert(StxValidator.InvalidDataLength.selector);
        stxValidator.onInstall(shortData);
    }

    /// @notice Test onInstall reverts when custom config data length is invalid (< 72 bytes)
    function test_onInstall_revertWhen_customConfigDataLengthInvalid() public {
        // Custom config requires: 20 (stateless validator) + 20 (stx mode verifier) + 32 (configId) = 72 bytes minimum
        // Using a non-default validator address triggers custom config path
        bytes memory invalidCustomData = abi.encodePacked(
            customStatelessValidator, // 20 bytes - non-default triggers custom config
            customStxModeVerifier, // 20 bytes
            bytes10(0) // only 10 more bytes instead of 32 for configId
        );

        vm.prank(smartAccount);
        vm.expectRevert(StxValidator.InvalidDataLength.selector);
        stxValidator.onInstall(invalidCustomData);
    }

    /// @notice Test onInstall reverts when data length is less than expected for safe senders
    function test_onInstall_reverts_when_dataLengthLessThanSafeSendersRequired() public {
        // Claiming 2 safe senders but not providing enough data
        bytes memory installData = abi.encodePacked(
            address(eoaStatelessValidator), // 20 bytes
            uint8(2), // claims 2 safe senders (would need 40 bytes)
            address(0x1111) // only 20 bytes provided
            // missing second safe sender and ownership data
        );

        vm.prank(smartAccount);
        vm.expectRevert(StxValidator.InvalidDataLength.selector);
        stxValidator.onInstall(installData);
    }

    // ==================== onUninstall Tests ====================

    /// @notice Test onUninstall clears all ownership data
    function test_onUninstall_clearsAllOwnershipData() public {
        // Install with EOA validator
        bytes memory installData =
            abi.encodePacked(address(eoaStatelessValidator), uint8(0), abi.encodePacked(owner.addr));

        vm.prank(smartAccount);
        stxValidator.onInstall(installData);
        assertTrue(stxValidator.isInitialized(smartAccount));

        vm.startPrank(smartAccount);
        stxValidator.setOwnershipData(
            address(p256StatelessValidator), abi.encodePacked(bytes32(0), bytes32(uint256(1)))
        );
        stxValidator.setOwnershipData(address(safeAccountSubmodule), abi.encodePacked(address(0x1111), smartAccount));
        vm.stopPrank();

        // Uninstall
        vm.prank(smartAccount);
        stxValidator.onUninstall("");

        // Verify no longer initialized
        assertFalse(stxValidator.isInitialized(smartAccount));

        // Verify ownership data was cleared
        bytes memory ownershipData = stxValidator.getOwnershipData(smartAccount, address(eoaStatelessValidator));
        // for eoa stateless validator, it should return the smart account address as owner
        // in case there been no ownership data set for a smart account
        // it is the 7702 compatibility flow
        assertEq(ownershipData, abi.encodePacked(smartAccount));

        // for p256 stateless validator, it should return empty ownership data
        bytes memory ownershipDataP256 = stxValidator.getOwnershipData(smartAccount, address(p256StatelessValidator));
        assertEq(ownershipDataP256, "");

        // for safe account submodule, it should return empty ownership data
        bytes memory ownershipDataSafeAccount =
            stxValidator.getOwnershipData(smartAccount, address(safeAccountSubmodule));
        assertEq(ownershipDataSafeAccount, "");
    }

    /// @notice Test onUninstall clears all safe senders
    function test_onUninstall_clearsAllSafeSenders() public {
        address safeSender1 = address(0x1111);
        address safeSender2 = address(0x2222);

        bytes memory installData = abi.encodePacked(
            address(eoaStatelessValidator), uint8(2), safeSender1, safeSender2, abi.encodePacked(owner.addr)
        );

        vm.prank(smartAccount);
        stxValidator.onInstall(installData);

        // Verify safe senders were added
        assertTrue(stxValidator.isSafeSender(safeSender1, smartAccount));
        assertTrue(stxValidator.isSafeSender(safeSender2, smartAccount));

        // Uninstall
        vm.prank(smartAccount);
        stxValidator.onUninstall("");

        // Verify safe senders were cleared
        assertFalse(stxValidator.isSafeSender(safeSender1, smartAccount));
        assertFalse(stxValidator.isSafeSender(safeSender2, smartAccount));
    }

    /// @notice Test onUninstall clears all custom configs and their associated ownership data
    function test_onUninstall_clearsAllCustomConfigs(uint256 numConfigs) public {
        numConfigs = bound(numConfigs, 5, 10);
        bytes memory ownershipData = abi.encodePacked(owner.addr);

        // Install with custom config
        bytes memory installData = abi.encodePacked(
            customStatelessValidator, customStxModeVerifier, customConfigId, uint8(0), ownershipData
        );

        vm.prank(smartAccount);
        stxValidator.onInstall(installData);

        // add few more configs
        vm.startPrank(smartAccount);
        for (uint256 i = 1; i < numConfigs; i++) {
            stxValidator.addConfig(
                keccak256(abi.encodePacked("custom-config-", i)), address(uint160(i)), address(uint160(i + 100))
            );
        }
        vm.stopPrank();

        // Verify config exists
        ValidationConfig memory configBefore = stxValidator.getConfigData(smartAccount, customConfigId);
        assertEq(configBefore.stxModeVerifierAddress, customStxModeVerifier);
        assertTrue(stxValidator.isInitialized(smartAccount));
        for (uint256 i = 1; i < numConfigs; i++) {
            ValidationConfig memory config =
                stxValidator.getConfigData(smartAccount, keccak256(abi.encodePacked("custom-config-", i)));
            assertEq(config.stxModeVerifierAddress, address(uint160(i)));
            assertEq(config.statelessValidatorAddress, address(uint160(i + 100)));
        }

        // Uninstall
        vm.prank(smartAccount);
        stxValidator.onUninstall("");

        // Verify config was cleared
        ValidationConfig memory configAfter = stxValidator.getConfigData(smartAccount, customConfigId);
        assertEq(configAfter.stxModeVerifierAddress, address(0));
        assertEq(configAfter.statelessValidatorAddress, address(0));
        assertFalse(stxValidator.isInitialized(smartAccount));
        for (uint256 i = 1; i < numConfigs; i++) {
            ValidationConfig memory config =
                stxValidator.getConfigData(smartAccount, keccak256(abi.encodePacked("custom-config-", i)));
            assertEq(config.stxModeVerifierAddress, address(0));
            assertEq(config.statelessValidatorAddress, address(0));
            assertFalse(stxValidator.isConfigEnabled(smartAccount, keccak256(abi.encodePacked("custom-config-", i))));
        }
        for (uint256 i = 1; i < numConfigs; i++) {
            bytes memory _ownershipData = stxValidator.getOwnershipData(smartAccount, address(uint160(i + 100)));
            assertEq(_ownershipData, "");
        }
    }

    /// @notice Test onUninstall clears config added via addConfig
    function test_onUninstall_clearsConfigAddedViaAddConfig() public {
        bytes memory ownershipData = abi.encodePacked(owner.addr);

        // initialize via onInstall first with no custom configs
        bytes memory installData =
            abi.encodePacked(address(eoaStatelessValidator), uint8(0), abi.encodePacked(owner.addr));
        vm.prank(smartAccount);
        stxValidator.onInstall(installData);

        // add custom config
        vm.startPrank(smartAccount);
        stxValidator.addConfig(customConfigId, customStxModeVerifier, customStatelessValidator);
        stxValidator.setOwnershipData(customStatelessValidator, ownershipData);
        vm.stopPrank();

        // Verify config exists
        ValidationConfig memory configBefore = stxValidator.getConfigData(smartAccount, customConfigId);
        assertEq(configBefore.stxModeVerifierAddress, customStxModeVerifier);

        // Uninstall
        vm.prank(smartAccount);
        stxValidator.onUninstall("");

        // Verify config was cleared
        ValidationConfig memory configAfter = stxValidator.getConfigData(smartAccount, customConfigId);
        assertEq(configAfter.stxModeVerifierAddress, address(0));
        assertEq(configAfter.statelessValidatorAddress, address(0));
        assertFalse(stxValidator.isInitialized(smartAccount));
        bytes memory ownershipDataAfter = stxValidator.getOwnershipData(smartAccount, customStatelessValidator);
        // in case of custom stateless validator, if ownership data is empty,
        // smart account address is not returned as owner because
        // it was ,ade for 7702 compatibility which is only required for EOA signatures (eoa stateless validator)
        assertEq(ownershipDataAfter, "");
    }

    /// @notice Test onUninstall clears ownership data for preconfigured sig types
    function test_onUninstall_clearsOwnershipDataForPreconfiguredSigTypes() public {
        // install with preconfigured sig type
        bytes memory installData =
            abi.encodePacked(address(eoaStatelessValidator), uint8(0), abi.encodePacked(owner.addr));
        vm.prank(smartAccount);
        stxValidator.onInstall(installData);

        // uninstall
        vm.prank(smartAccount);
        stxValidator.onUninstall("");

        // Verify ownership data was cleared
        bytes memory ownershipData = stxValidator.getOwnershipData(smartAccount, address(eoaStatelessValidator));
        assertEq(ownershipData, abi.encodePacked(smartAccount));
    }

    /// @notice Test onUninstall clears ownership data for the stateless validator associated with several configs
    function test_onUninstall_clearsOwnershipDataForTheStatelessValidatorAssociatedWithSeveralConfigs() public {
        // install with several configs
        bytes memory installData =
            abi.encodePacked(address(eoaStatelessValidator), uint8(0), abi.encodePacked(owner.addr));
        vm.prank(smartAccount);
        stxValidator.onInstall(installData);

        // add custom config
        vm.startPrank(smartAccount);
        stxValidator.addConfig(customConfigId, customStxModeVerifier, address(eoaStatelessValidator));
        vm.stopPrank();

        // make sure ownership data is set for the stateless validator associated with the custom config
        bytes memory ownershipData = stxValidator.getOwnershipData(smartAccount, address(eoaStatelessValidator));
        assertEq(ownershipData, abi.encodePacked(owner.addr));

        // uninstall
        vm.prank(smartAccount);
        stxValidator.onUninstall("");

        // Verify ownership data was cleared
        bytes memory ownershipDataAfter = stxValidator.getOwnershipData(smartAccount, address(eoaStatelessValidator));
        assertEq(ownershipDataAfter, abi.encodePacked(smartAccount));
    }

    /// @notice Test that onUninstall for one account doesn't affect another account
    function test_onUninstall_doesNotAffectOtherAccounts() public {
        // Install for first account
        bytes memory installData1 =
            abi.encodePacked(address(eoaStatelessValidator), uint8(0), abi.encodePacked(owner.addr));

        vm.prank(smartAccount);
        stxValidator.onInstall(installData1);

        // Install for second account
        bytes memory installData2 =
            abi.encodePacked(address(eoaStatelessValidator), uint8(0), abi.encodePacked(anotherOwner.addr));

        vm.prank(anotherSmartAccount);
        stxValidator.onInstall(installData2);

        // Both should be initialized
        assertTrue(stxValidator.isInitialized(smartAccount));
        assertTrue(stxValidator.isInitialized(anotherSmartAccount));

        // Uninstall first account
        vm.prank(smartAccount);
        stxValidator.onUninstall("");

        // First account should be uninitialized, second should still be initialized
        assertFalse(stxValidator.isInitialized(smartAccount));
        assertTrue(stxValidator.isInitialized(anotherSmartAccount));
    }

    /// @notice Test onUninstall can be called even if not initialized (no-op)
    function test_onUninstall_revertsWhenNotInitialized() public {
        // Should not revert even if not initialized
        assertFalse(stxValidator.isInitialized(smartAccount));

        vm.prank(smartAccount);
        vm.expectRevert(StxValidator.ModuleNotInitialized.selector);
        stxValidator.onUninstall("");

        // Still not initialized
        assertFalse(stxValidator.isInitialized(smartAccount));
    }

    /// @notice Test reinstall after uninstall works correctly
    function test_reinstall_afterUninstall_succeeds() public {
        bytes memory installData =
            abi.encodePacked(address(eoaStatelessValidator), uint8(0), abi.encodePacked(owner.addr));

        // First install
        vm.prank(smartAccount);
        stxValidator.onInstall(installData);
        assertTrue(stxValidator.isInitialized(smartAccount));

        // Uninstall
        vm.prank(smartAccount);
        stxValidator.onUninstall("");
        assertFalse(stxValidator.isInitialized(smartAccount));

        // Reinstall with different owner
        bytes memory reinstallData =
            abi.encodePacked(address(eoaStatelessValidator), uint8(0), abi.encodePacked(anotherOwner.addr));

        vm.prank(smartAccount);
        stxValidator.onInstall(reinstallData);
        assertTrue(stxValidator.isInitialized(smartAccount));
    }
}
