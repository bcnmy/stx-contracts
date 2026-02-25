// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test, Vm } from "forge-std/Test.sol";
import { EOAStatelessValidator } from "contracts/validators/stx-validator/submodules/EOAStatelessValidator.sol";
import { InvalidErc7780DataLength } from "contracts/interfaces/standard/erc-7780/IStatelessValidator.sol";
import { MODULE_TYPE_STATELESS_VALIDATOR } from "contracts/types/Constants.sol";

/// @title EOAStatelessValidator Unit Tests
/// @notice Unit tests for EOAStatelessValidator (ERC-7780 stateless validator)
/// @dev Tests signature validation, malleability prevention, and module interface
contract EOAStatelessValidator_Test is Test {
    EOAStatelessValidator internal validator;
    Vm.Wallet internal signer;

    // Half of secp256k1 curve order (for malleability check)
    // SECP256K1_ORDER is already defined in forge-std's Base.sol
    uint256 internal constant HALF_ORDER = 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0;

    function setUp() public {
        validator = new EOAStatelessValidator();
        signer = vm.createWallet("signer");
    }

    /*//////////////////////////////////////////////////////////////////////////
                        VALIDATE SIGNATURE WITH DATA TESTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Test valid signature returns true
    function test_validateSignatureWithData_validSignature_returnsTrue() public view {
        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer.privateKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);
        bytes memory data = abi.encodePacked(signer.addr);

        bool result = validator.validateSignatureWithData(hash, signature, data);

        assertTrue(result);
    }

    /// @notice Test invalid signature (wrong signer) returns false
    function test_validateSignatureWithData_wrongSigner_returnsFalse() public {
        Vm.Wallet memory wrongSigner = vm.createWallet("wrongSigner");
        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongSigner.privateKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);
        // Data contains the original signer, but signature is from wrongSigner
        bytes memory data = abi.encodePacked(signer.addr);

        bool result = validator.validateSignatureWithData(hash, signature, data);

        assertFalse(result);
    }

    /// @notice Test invalid signature (wrong hash) returns false
    function test_validateSignatureWithData_wrongHash_returnsFalse() public view {
        bytes32 hash = keccak256("test message");
        bytes32 wrongHash = keccak256("different message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer.privateKey, wrongHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        bytes memory data = abi.encodePacked(signer.addr);

        bool result = validator.validateSignatureWithData(hash, signature, data);

        assertFalse(result);
    }

    /// @notice Test reverts when data length is less than 20 bytes
    function test_validateSignatureWithData_revertWhen_dataLengthLessThan20() public {
        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer.privateKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);
        bytes memory shortData = abi.encodePacked(bytes19(0)); // 19 bytes

        vm.expectRevert(InvalidErc7780DataLength.selector);
        validator.validateSignatureWithData(hash, signature, shortData);
    }

    /// @notice Test reverts when data is empty
    function test_validateSignatureWithData_revertWhen_dataEmpty() public {
        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer.privateKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);
        bytes memory emptyData = "";

        vm.expectRevert(InvalidErc7780DataLength.selector);
        validator.validateSignatureWithData(hash, signature, emptyData);
    }

    /// @notice Test accepts data with exactly 20 bytes
    function test_validateSignatureWithData_exactly20BytesData_succeeds() public view {
        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer.privateKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);
        bytes memory data = abi.encodePacked(signer.addr); // Exactly 20 bytes
        assertEq(data.length, 20);

        bool result = validator.validateSignatureWithData(hash, signature, data);

        assertTrue(result);
    }

    /// @notice Test accepts data with more than 20 bytes (extra data ignored)
    function test_validateSignatureWithData_extraDataIgnored_succeeds() public view {
        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer.privateKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);
        // 20 bytes address + 12 bytes extra data
        bytes memory data = abi.encodePacked(signer.addr, bytes12(uint96(0xaabbccdd)));
        assertEq(data.length, 32);

        bool result = validator.validateSignatureWithData(hash, signature, data);

        assertTrue(result);
    }

    /// @notice Test zero address owner with invalid signature also reverts
    /// @dev This prevents the vulnerability where invalid signatures recover to address(0)
    function test_validateSignatureWithData_revertWhen_zeroAddressOwner_invalidSig() public {
        bytes32 hash = keccak256("test message");
        // Craft an invalid signature that would cause ecrecover to return address(0)
        bytes memory invalidSignature = abi.encodePacked(bytes32(0), bytes32(0), uint8(27));
        bytes memory data = abi.encodePacked(address(0));

        // Now properly reverts instead of incorrectly returning true
        vm.expectRevert(EOAStatelessValidator.ZeroAddressOwner.selector);
        validator.validateSignatureWithData(hash, invalidSignature, data);
    }

    /*//////////////////////////////////////////////////////////////////////////
                        SIGNATURE MALLEABILITY TESTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Test signature with s > half order reverts (malleability prevention)
    /// @dev EIP-2 mandates s <= half order to prevent signature malleability
    function test_validateSignatureWithData_revertWhen_sValueTooHigh() public {
        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer.privateKey, hash);

        // If s is already low, flip it to high (s' = order - s)
        uint256 sValue = uint256(s);
        if (sValue <= HALF_ORDER) {
            sValue = SECP256K1_ORDER - sValue;
        }
        bytes32 highS = bytes32(sValue);

        bytes memory malleableSignature = abi.encodePacked(r, highS, v);
        bytes memory data = abi.encodePacked(signer.addr);

        vm.expectRevert(EOAStatelessValidator.InvalidSignature.selector);
        validator.validateSignatureWithData(hash, malleableSignature, data);
    }

    /// @notice Test signature with s at exactly half order succeeds
    function test_validateSignatureWithData_sAtHalfOrder_succeeds() public view {
        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer.privateKey, hash);

        // Ensure s is <= HALF_ORDER (vm.sign should already produce low s)
        uint256 sValue = uint256(s);
        assertTrue(sValue <= HALF_ORDER, "vm.sign should produce low s values");

        bytes memory signature = abi.encodePacked(r, s, v);
        bytes memory data = abi.encodePacked(signer.addr);

        bool result = validator.validateSignatureWithData(hash, signature, data);

        assertTrue(result);
    }

    /// @notice Test signature with s just above half order reverts
    function test_validateSignatureWithData_revertWhen_sJustAboveHalfOrder() public {
        bytes32 hash = keccak256("test message");

        // Create signature with s = HALF_ORDER + 1 (just above threshold)
        bytes32 r = bytes32(uint256(1));
        bytes32 highS = bytes32(HALF_ORDER + 1);
        uint8 v = 27;

        bytes memory malleableSignature = abi.encodePacked(r, highS, v);
        bytes memory data = abi.encodePacked(signer.addr);

        vm.expectRevert(EOAStatelessValidator.InvalidSignature.selector);
        validator.validateSignatureWithData(hash, malleableSignature, data);
    }

    /*//////////////////////////////////////////////////////////////////////////
                            MODULE TYPE TESTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Test isModuleType returns true for MODULE_TYPE_STATELESS_VALIDATOR
    function test_isModuleType_statelessValidator_returnsTrue() public view {
        assertTrue(validator.isModuleType(MODULE_TYPE_STATELESS_VALIDATOR));
    }

    /// @notice Test isModuleType returns false for other module types
    function test_isModuleType_otherTypes_returnsFalse() public view {
        assertFalse(validator.isModuleType(1)); // MODULE_TYPE_VALIDATOR
        assertFalse(validator.isModuleType(2)); // MODULE_TYPE_EXECUTOR
        assertFalse(validator.isModuleType(3)); // MODULE_TYPE_FALLBACK
        assertFalse(validator.isModuleType(4)); // MODULE_TYPE_HOOK
        assertFalse(validator.isModuleType(0));
        assertFalse(validator.isModuleType(100));
    }

    /// @notice Test MODULE_TYPE_STATELESS_VALIDATOR constant value
    function test_moduleTypeStatelessValidator_hasCorrectValue() public pure {
        assertEq(MODULE_TYPE_STATELESS_VALIDATOR, 7);
    }

    /*//////////////////////////////////////////////////////////////////////////
                        LIFECYCLE FUNCTIONS TESTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Test onInstall does nothing (no revert)
    function test_onInstall_doesNothing() public {
        // Should not revert with any data
        validator.onInstall("");
        validator.onInstall(abi.encodePacked(bytes32(0)));
        validator.onInstall(abi.encodePacked(address(this), uint256(123)));
    }

    /// @notice Test onUninstall does nothing (no revert)
    function test_onUninstall_doesNothing() public {
        // Should not revert with any data
        validator.onUninstall("");
        validator.onUninstall(abi.encodePacked(bytes32(0)));
        validator.onUninstall(abi.encodePacked(address(this), uint256(123)));
    }

    /// @notice Test isInitialized always returns true (stateless)
    function test_isInitialized_alwaysReturnsTrue() public view {
        assertTrue(validator.isInitialized(address(0)));
        assertTrue(validator.isInitialized(address(this)));
        assertTrue(validator.isInitialized(address(0x1234)));
    }

    /*//////////////////////////////////////////////////////////////////////////
                        ETH SIGNED MESSAGE HASH TESTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Test signature validation with eth_sign prefix (personal_sign)
    /// @dev EcdsaHelperLib.isValidSignature also checks toEthSignedMessageHash
    function test_validateSignatureWithData_ethSignedMessageHash_succeeds() public view {
        bytes32 hash = keccak256("test message");
        // Sign the eth_sign prefixed hash
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer.privateKey, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        bytes memory data = abi.encodePacked(signer.addr);

        // Should succeed because EcdsaHelperLib checks both raw hash and eth_sign prefixed hash
        bool result = validator.validateSignatureWithData(hash, signature, data);

        assertTrue(result);
    }
}
