// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { StxValidator_Unit_Base_Test } from "./StxValidator_Unit_Base_Test.t.sol";
import { StxValidator } from "contracts/validators/stx-validator/StxValidator.sol";
import {
    ConfigManager,
    SubmoduleAddresses,
    ValidationConfig
} from "contracts/validators/stx-validator/ConfigManager.sol";
import {
    SIG_TYPE_SIMPLE,
    SIG_TYPE_ON_CHAIN,
    SIG_TYPE_ERC20_PERMIT,
    SIG_TYPE_SAFE_ACCOUNT,
    SIG_TYPE_NO_STX_VANILLA_1271_EOA,
    SIG_TYPE_SIMPLE_P256,
    SIG_TYPE_NO_STX_VANILLA_1271_P256,
    SIG_TYPE_NO_STX_P256,
    SIG_TYPE_CUSTOM,
    SIG_TYPE_MEE_FLOW
} from "contracts/types/Constants.sol";

/// @title Test harness to expose internal _getSubmodules function
contract StxValidatorHarness is StxValidator {
    constructor(SubmoduleAddresses memory submoduleAddresses) StxValidator(submoduleAddresses) { }

    /// @notice Exposes the internal _getSubmodules function for testing
    function exposed_getSubmodules(
        address smartAccount,
        bytes calldata sigData
    )
        external
        view
        returns (address stxModeVerifier, address statelessValidator, bytes calldata parsedSigData)
    {
        return _getSubmodules(smartAccount, sigData);
    }
}

/// @title StxValidator Signature Type Routing Unit Tests
/// @notice Unit tests for _getSubmodules signature type routing functionality
contract StxValidator_SignatureTypeRouting_Test is StxValidator_Unit_Base_Test {
    StxValidatorHarness internal stxValidatorHarness;

    function setUp() public override {
        super.setUp();

        // Deploy harness with same submodule addresses
        stxValidatorHarness = new StxValidatorHarness(
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

        // Initialize validator for smartAccount
        bytes memory installData =
            abi.encodePacked(address(eoaStatelessValidator), uint8(0), abi.encodePacked(owner.addr));
        vm.prank(smartAccount);
        stxValidatorHarness.onInstall(installData);
    }

    // ==================== SIG_TYPE_SIMPLE (0x177eee00) Tests ====================

    /// @notice Test SIG_TYPE_SIMPLE routes to SimpleModeVerifier + EOAStatelessValidator
    function test_getSubmodules_sigTypeSimple_routesToSimpleModeAndEOA() public view {
        bytes memory sigData = abi.encodePacked(SIG_TYPE_SIMPLE, bytes("test signature data"));

        (address stxModeVerifier, address statelessValidator, bytes memory parsedSigData) =
            stxValidatorHarness.exposed_getSubmodules(smartAccount, sigData);

        assertEq(stxModeVerifier, address(simpleModeSubmodule));
        assertEq(statelessValidator, address(eoaStatelessValidator));
        assertEq(parsedSigData, bytes("test signature data"));
    }

    // ==================== SIG_TYPE_ON_CHAIN (0x177eee01) Tests ====================

    /// @notice Test SIG_TYPE_ON_CHAIN routes to TxModeVerifier + EOAStatelessValidator
    function test_getSubmodules_sigTypeOnChain_routesToTxModeAndEOA() public view {
        bytes memory sigData = abi.encodePacked(SIG_TYPE_ON_CHAIN, bytes("test signature data"));

        (address stxModeVerifier, address statelessValidator, bytes memory parsedSigData) =
            stxValidatorHarness.exposed_getSubmodules(smartAccount, sigData);

        assertEq(stxModeVerifier, address(txSubmodule));
        assertEq(statelessValidator, address(eoaStatelessValidator));
        assertEq(parsedSigData, bytes("test signature data"));
    }

    // ==================== SIG_TYPE_ERC20_PERMIT (0x177eee02) Tests ====================

    /// @notice Test SIG_TYPE_ERC20_PERMIT routes to PermitModeVerifier + EOAStatelessValidator
    function test_getSubmodules_sigTypeErc20Permit_routesToPermitModeAndEOA() public view {
        bytes memory sigData = abi.encodePacked(SIG_TYPE_ERC20_PERMIT, bytes("test signature data"));

        (address stxModeVerifier, address statelessValidator, bytes memory parsedSigData) =
            stxValidatorHarness.exposed_getSubmodules(smartAccount, sigData);

        assertEq(stxModeVerifier, address(permitSubmodule));
        assertEq(statelessValidator, address(eoaStatelessValidator));
        assertEq(parsedSigData, bytes("test signature data"));
    }

    // ==================== SIG_TYPE_SAFE_ACCOUNT (0x177eee04) Tests ====================

    /// @notice Test SIG_TYPE_SAFE_ACCOUNT routes to SafeAccountSubmodule for both verifier and validator
    function test_getSubmodules_sigTypeSafeAccount_routesToSafeAccountSubmodule() public view {
        bytes memory sigData = abi.encodePacked(SIG_TYPE_SAFE_ACCOUNT, bytes("test signature data"));

        (address stxModeVerifier, address statelessValidator, bytes memory parsedSigData) =
            stxValidatorHarness.exposed_getSubmodules(smartAccount, sigData);

        assertEq(stxModeVerifier, address(safeAccountSubmodule));
        assertEq(statelessValidator, address(safeAccountSubmodule));
        assertEq(parsedSigData, bytes("test signature data"));
    }

    // ==================== SIG_TYPE_NO_STX_VANILLA_1271_EOA (0x177eee05) Tests ====================

    /// @notice Test SIG_TYPE_NO_STX_VANILLA_1271_EOA routes to address(0) + EOAStatelessValidator (vanilla 1271)
    function test_getSubmodules_sigTypeNoStxVanilla1271Eoa_routesToZeroAddressAndEOA() public view {
        bytes memory sigData = abi.encodePacked(SIG_TYPE_NO_STX_VANILLA_1271_EOA, bytes("test signature data"));

        (address stxModeVerifier, address statelessValidator, bytes memory parsedSigData) =
            stxValidatorHarness.exposed_getSubmodules(smartAccount, sigData);

        assertEq(stxModeVerifier, address(0));
        assertEq(statelessValidator, address(eoaStatelessValidator));
        assertEq(parsedSigData, bytes("test signature data"));
    }

    // ==================== SIG_TYPE_SIMPLE_P256 (0x177eee10) Tests ====================

    /// @notice Test SIG_TYPE_SIMPLE_P256 routes to SimpleModeVerifier + P256StatelessValidator
    function test_getSubmodules_sigTypeSimpleP256_routesToSimpleModeAndP256() public view {
        bytes memory sigData = abi.encodePacked(SIG_TYPE_SIMPLE_P256, bytes("test signature data"));

        (address stxModeVerifier, address statelessValidator, bytes memory parsedSigData) =
            stxValidatorHarness.exposed_getSubmodules(smartAccount, sigData);

        assertEq(stxModeVerifier, address(simpleModeSubmodule));
        assertEq(statelessValidator, address(p256StatelessValidator));
        assertEq(parsedSigData, bytes("test signature data"));
    }

    // ==================== SIG_TYPE_NO_STX_VANILLA_1271_P256 (0x177eee11) Tests ====================

    /// @notice Test SIG_TYPE_NO_STX_VANILLA_1271_P256 routes to address(0) + P256StatelessValidator (vanilla 1271)
    function test_getSubmodules_sigTypeNoStxVanilla1271P256_routesToZeroAddressAndP256() public view {
        bytes memory sigData = abi.encodePacked(SIG_TYPE_NO_STX_VANILLA_1271_P256, bytes("test signature data"));

        (address stxModeVerifier, address statelessValidator, bytes memory parsedSigData) =
            stxValidatorHarness.exposed_getSubmodules(smartAccount, sigData);

        assertEq(stxModeVerifier, address(0));
        assertEq(statelessValidator, address(p256StatelessValidator));
        assertEq(parsedSigData, bytes("test signature data"));
    }

    // ==================== SIG_TYPE_NO_STX_P256 (0x177eee12) Tests ====================

    /// @notice Test SIG_TYPE_NO_STX_P256 routes to NoStxModeVerifier + P256StatelessValidator
    function test_getSubmodules_sigTypeNoStxP256_routesToNoStxModeAndP256() public view {
        bytes memory sigData = abi.encodePacked(SIG_TYPE_NO_STX_P256, bytes("test signature data"));

        (address stxModeVerifier, address statelessValidator, bytes memory parsedSigData) =
            stxValidatorHarness.exposed_getSubmodules(smartAccount, sigData);

        assertEq(stxModeVerifier, address(noStxModeVerifier));
        assertEq(statelessValidator, address(p256StatelessValidator));
        assertEq(parsedSigData, bytes("test signature data"));
    }

    // ==================== SIG_TYPE_CUSTOM (0x177eeeff) Tests ====================

    /// @notice Test SIG_TYPE_CUSTOM routes to custom config's stxModeVerifier and statelessValidator
    function test_getSubmodules_sigTypeCustom_routesToCustomConfig() public {
        // Add custom config for the smart account
        vm.prank(smartAccount);
        stxValidatorHarness.addConfig(customConfigId, customStxModeVerifier, customStatelessValidator);

        // Build sig data: [4 bytes sigType][32 bytes configId][rest is parsed sig data]
        bytes memory sigData = abi.encodePacked(SIG_TYPE_CUSTOM, customConfigId, bytes("test signature data"));

        (address stxModeVerifier, address statelessValidator, bytes memory parsedSigData) =
            stxValidatorHarness.exposed_getSubmodules(smartAccount, sigData);

        assertEq(stxModeVerifier, customStxModeVerifier);
        assertEq(statelessValidator, customStatelessValidator);
        assertEq(parsedSigData, bytes("test signature data"));
    }

    /// @notice Test SIG_TYPE_CUSTOM with non-existent config returns zero addresses
    function test_getSubmodules_sigTypeCustom_nonExistentConfigReturnsZeroAddresses() public view {
        // Build sig data with a config that doesn't exist
        bytes32 nonExistentConfigId = keccak256("non-existent-config");
        bytes memory sigData = abi.encodePacked(SIG_TYPE_CUSTOM, nonExistentConfigId, bytes("test signature data"));

        (address stxModeVerifier, address statelessValidator, bytes memory parsedSigData) =
            stxValidatorHarness.exposed_getSubmodules(smartAccount, sigData);

        // Non-existent config returns zero addresses (no revert, but will fail validation later)
        assertEq(stxModeVerifier, address(0));
        assertEq(statelessValidator, address(0));
        assertEq(parsedSigData, bytes("test signature data"));
    }

    /// @notice Test SIG_TYPE_CUSTOM reverts when sigData length is too short (< 36 bytes)
    function test_getSubmodules_sigTypeCustom_revertWhen_sigDataTooShort() public {
        // sigData needs: 4 bytes sigType + 32 bytes configId = 36 bytes minimum
        // 35 bytes should revert
        bytes memory shortSigData = abi.encodePacked(SIG_TYPE_CUSTOM, bytes31(0));
        assertEq(shortSigData.length, 35);

        vm.expectRevert(ConfigManager.InvalidSignatureDataLength.selector);
        stxValidatorHarness.exposed_getSubmodules(smartAccount, shortSigData);
    }

    /// @notice Test SIG_TYPE_CUSTOM with exactly 36 bytes returns empty parsedSigData
    function test_getSubmodules_sigTypeCustom_exactly36Bytes_returnsEmptySigData() public {
        // Add custom config
        vm.prank(smartAccount);
        stxValidatorHarness.addConfig(customConfigId, customStxModeVerifier, customStatelessValidator);

        // sigData: 4 bytes sigType + 32 bytes configId = 36 bytes exactly
        bytes memory sigData = abi.encodePacked(SIG_TYPE_CUSTOM, customConfigId);
        assertEq(sigData.length, 36);

        (address stxModeVerifier, address statelessValidator, bytes memory parsedSigData) =
            stxValidatorHarness.exposed_getSubmodules(smartAccount, sigData);

        assertEq(stxModeVerifier, customStxModeVerifier);
        assertEq(statelessValidator, customStatelessValidator);
        assertEq(parsedSigData.length, 0);
        assertEq(parsedSigData, "");
    }

    // ==================== Fallback (No MEE prefix) Tests ====================

    /// @notice Test fallback to NoStxModeVerifier + EOAStatelessValidator for non-MEE signatures
    function test_getSubmodules_fallback_routesToNoStxModeAndEOA() public view {
        // A regular signature without MEE prefix (e.g., standard ECDSA signature)
        bytes memory sigData = abi.encodePacked(bytes4(0x12345678), bytes("test signature data"));

        (address stxModeVerifier, address statelessValidator, bytes memory parsedSigData) =
            stxValidatorHarness.exposed_getSubmodules(smartAccount, sigData);

        assertEq(stxModeVerifier, address(noStxModeVerifier));
        assertEq(statelessValidator, address(eoaStatelessValidator));
        // Fallback returns the entire sigData (not stripped)
        assertEq(parsedSigData, sigData);
    }

    /// @notice Test fallback with signature starting with different prefix
    function test_getSubmodules_fallback_differentPrefix_routesToNoStxModeAndEOA() public view {
        // Signature starting with 0xaabbccdd (not MEE prefix)
        bytes memory sigData = abi.encodePacked(bytes4(0xaabbccdd), bytes("some data"));

        (address stxModeVerifier, address statelessValidator, bytes memory parsedSigData) =
            stxValidatorHarness.exposed_getSubmodules(smartAccount, sigData);

        assertEq(stxModeVerifier, address(noStxModeVerifier));
        assertEq(statelessValidator, address(eoaStatelessValidator));
        assertEq(parsedSigData, sigData);
    }

    // ==================== Unrecognized MEE Signature Type Tests ====================

    /// @notice Test unrecognized MEE signature type reverts
    function test_getSubmodules_unrecognizedMeeSigType_reverts() public {
        // MEE prefix (0x177eee) but unrecognized suffix (e.g., 0x177eee99)
        bytes memory sigData = abi.encodePacked(bytes4(0x177eee99), bytes("test signature data"));

        vm.expectRevert(ConfigManager.UnrecognizedSignatureType.selector);
        stxValidatorHarness.exposed_getSubmodules(smartAccount, sigData);
    }

    /// @notice Test another unrecognized MEE signature type reverts
    function test_getSubmodules_anotherUnrecognizedMeeSigType_reverts() public {
        // MEE prefix with 0x03 suffix (reserved but not implemented)
        bytes memory sigData = abi.encodePacked(bytes4(0x177eee03), bytes("test signature data"));

        vm.expectRevert(ConfigManager.UnrecognizedSignatureType.selector);
        stxValidatorHarness.exposed_getSubmodules(smartAccount, sigData);
    }

    // ==================== Invalid Signature Data Length Tests ====================

    /// @notice Test reverts when sigData length is less than 4 bytes
    function test_getSubmodules_revertWhen_sigDataLengthLessThan4Bytes() public {
        bytes memory shortSigData = abi.encodePacked(bytes3(0x177eee));

        vm.expectRevert(ConfigManager.InvalidSignatureDataLength.selector);
        stxValidatorHarness.exposed_getSubmodules(smartAccount, shortSigData);
    }

    /// @notice Test reverts when sigData is empty
    function test_getSubmodules_revertWhen_sigDataEmpty() public {
        bytes memory emptySigData = "";

        vm.expectRevert(ConfigManager.InvalidSignatureDataLength.selector);
        stxValidatorHarness.exposed_getSubmodules(smartAccount, emptySigData);
    }

    // ==================== Parsed Signature Data Correctness Tests ====================

    /// @notice Test that parsedSigData correctly strips the 4-byte prefix for preconfigured types
    function test_getSubmodules_parsedSigDataCorrectlyStripsPrefix() public view {
        bytes memory originalSigPayload = abi.encodePacked(
            bytes32(keccak256("some hash")),
            bytes32(uint256(27)), // v
            bytes32(keccak256("r")), // r
            bytes32(keccak256("s")) // s
        );
        bytes memory sigData = abi.encodePacked(SIG_TYPE_SIMPLE, originalSigPayload);

        (,, bytes memory parsedSigData) = stxValidatorHarness.exposed_getSubmodules(smartAccount, sigData);

        assertEq(parsedSigData, originalSigPayload);
    }

    /// @notice Test that parsedSigData correctly strips 4-byte prefix + 32-byte configId for custom type
    function test_getSubmodules_customType_parsedSigDataCorrectlyStripsConfigId() public {
        // Add custom config
        vm.prank(smartAccount);
        stxValidatorHarness.addConfig(customConfigId, customStxModeVerifier, customStatelessValidator);

        bytes memory originalSigPayload = abi.encodePacked(
            bytes32(keccak256("some hash")), bytes32(uint256(27)), bytes32(keccak256("r")), bytes32(keccak256("s"))
        );
        bytes memory sigData = abi.encodePacked(SIG_TYPE_CUSTOM, customConfigId, originalSigPayload);

        (,, bytes memory parsedSigData) = stxValidatorHarness.exposed_getSubmodules(smartAccount, sigData);

        assertEq(parsedSigData, originalSigPayload);
    }

    // ==================== Account Isolation Tests ====================

    /// @notice Test that custom config routing is account-specific
    function test_getSubmodules_customConfig_isAccountSpecific() public {
        // Add config for smartAccount
        vm.prank(smartAccount);
        stxValidatorHarness.addConfig(customConfigId, customStxModeVerifier, customStatelessValidator);

        // Query for smartAccount - should return the custom config
        bytes memory sigData = abi.encodePacked(SIG_TYPE_CUSTOM, customConfigId, bytes("test"));

        (address stxModeVerifier1, address statelessValidator1,) =
            stxValidatorHarness.exposed_getSubmodules(smartAccount, sigData);
        assertEq(stxModeVerifier1, customStxModeVerifier);
        assertEq(statelessValidator1, customStatelessValidator);

        // Query for anotherSmartAccount - should return zero addresses (config not added for this account)
        (address stxModeVerifier2, address statelessValidator2,) =
            stxValidatorHarness.exposed_getSubmodules(anotherSmartAccount, sigData);
        assertEq(stxModeVerifier2, address(0));
        assertEq(statelessValidator2, address(0));
    }

    // ==================== Edge Cases ====================

    /// @notice Test minimum valid sigData (exactly 4 bytes) for preconfigured types
    function test_getSubmodules_minimumValidSigData_4Bytes() public view {
        bytes memory sigData = abi.encodePacked(SIG_TYPE_SIMPLE);
        assertEq(sigData.length, 4);

        (address stxModeVerifier, address statelessValidator, bytes memory parsedSigData) =
            stxValidatorHarness.exposed_getSubmodules(smartAccount, sigData);

        assertEq(stxModeVerifier, address(simpleModeSubmodule));
        assertEq(statelessValidator, address(eoaStatelessValidator));
        assertEq(parsedSigData.length, 0);
    }

    /// @notice Test custom type with 37 bytes returns 1 byte of parsedSigData
    function test_getSubmodules_customType_37Bytes_returns1ByteSigData() public {
        vm.prank(smartAccount);
        stxValidatorHarness.addConfig(customConfigId, customStxModeVerifier, customStatelessValidator);

        bytes memory sigData = abi.encodePacked(SIG_TYPE_CUSTOM, customConfigId, bytes1(0xab));
        assertEq(sigData.length, 37);

        (address stxModeVerifier, address statelessValidator, bytes memory parsedSigData) =
            stxValidatorHarness.exposed_getSubmodules(smartAccount, sigData);

        assertEq(stxModeVerifier, customStxModeVerifier);
        assertEq(statelessValidator, customStatelessValidator);
        assertEq(parsedSigData.length, 1);
        assertEq(parsedSigData, abi.encodePacked(bytes1(0xab)));
    }
}
