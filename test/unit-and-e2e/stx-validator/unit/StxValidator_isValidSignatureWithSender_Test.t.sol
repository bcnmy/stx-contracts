// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { StxValidator_Unit_Base_Test } from "./StxValidator_Unit_Base_Test.t.sol";
import { ERC1271_FAILED } from "contracts/types/Constants.sol";

/// @title StxValidator isValidSignatureWithSender Tests
/// @notice Unit tests for isValidSignatureWithSender functionality
/// @dev Tests ERC-7739 detection and basic routing. Full signature validation is tested in e2e tests.
contract StxValidator_isValidSignatureWithSender_Test is StxValidator_Unit_Base_Test {
    // ERC-7739 detection constant
    bytes4 internal constant SUPPORTS_ERC7739_V1 = 0x77390001;

    /*//////////////////////////////////////////////////////////////////////////
                              ERC-7739 DETECTION TESTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Test that empty signature with special hash returns SUPPORTS_ERC7739_V1
    /// @dev This is the ERC-7739 detection mechanism
    function test_isValidSignatureWithSender_erc7739Detection_returnsSupportsV1() public {
        _initializeValidator();

        // The special hash for ERC-7739 detection: ~signature.length / 0xffff * 0x7739
        // When signature.length == 0: ~0 / 0xffff * 0x7739 = type(uint256).max / 0xffff * 0x7739
        bytes32 detectionHash = bytes32(~uint256(0) / 0xffff * 0x7739);

        vm.prank(smartAccount);
        bytes4 result = stxValidator.isValidSignatureWithSender(address(0), detectionHash, "");

        assertEq(result, SUPPORTS_ERC7739_V1);
    }

    /*//////////////////////////////////////////////////////////////////////////
                          SIGNATURE VALIDATION ROUTING TESTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Test that signature validation uses msg.sender as account
    /// @dev The function gets submodules based on msg.sender, not sender parameter
    function test_isValidSignatureWithSender_usesCallerAsAccount() public {
        _initializeValidator();

        // Even if sender is different, the account (msg.sender) is used for routing
        address differentSender = address(0x1234);
        bytes32 dataHash = keccak256("test data");

        // Create a minimal valid signature with SIG_TYPE_NO_STX_VANILLA_1271_EOA
        // This type returns stxModeVerifier = address(0), so it uses vanilla 1271 flow
        bytes4 sigType = bytes4(0x177eee05); // SIG_TYPE_NO_STX_VANILLA_1271_EOA
        bytes memory signature = abi.encodePacked(sigType, bytes("dummy sig data"));

        // This should not revert - it will fail signature validation but proves routing works
        vm.prank(smartAccount);
        bytes4 result = stxValidator.isValidSignatureWithSender(differentSender, dataHash, signature);

        // Should return failed (invalid signature) but not revert
        assertEq(result, ERC1271_FAILED);
    }

    /*//////////////////////////////////////////////////////////////////////////
                          VANILLA 1271 FLOW TESTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Test vanilla 1271 flow with SIG_TYPE_NO_STX_VANILLA_1271_EOA
    /// @dev When stxModeVerifierAddress is address(0), vanilla 1271 is used
    function test_isValidSignatureWithSender_vanilla1271Flow_withEOA() public {
        _initializeValidator();

        bytes32 dataHash = keccak256("test data");
        bytes4 sigType = bytes4(0x177eee05); // SIG_TYPE_NO_STX_VANILLA_1271_EOA

        // Invalid signature should return ERC1271_FAILED
        bytes memory invalidSig = abi.encodePacked(sigType, bytes32(0), bytes32(0), uint8(27));

        vm.prank(smartAccount);
        bytes4 result = stxValidator.isValidSignatureWithSender(address(0), dataHash, invalidSig);

        assertEq(result, ERC1271_FAILED);
    }

    /// @notice Test vanilla 1271 flow with SIG_TYPE_NO_STX_VANILLA_1271_P256
    function test_isValidSignatureWithSender_vanilla1271Flow_withP256() public {
        // Initialize with P256 validator
        bytes memory p256PublicKey = abi.encodePacked(bytes32(uint256(1)), bytes32(uint256(2)));
        bytes memory installData = abi.encodePacked(address(p256StatelessValidator), uint8(0), p256PublicKey);

        vm.prank(smartAccount);
        stxValidator.onInstall(installData);

        bytes32 dataHash = keccak256("test data");
        bytes4 sigType = bytes4(0x177eee11); // SIG_TYPE_NO_STX_VANILLA_1271_P256

        // Invalid signature should return ERC1271_FAILED
        bytes memory invalidSig = abi.encodePacked(sigType, bytes32(0), bytes32(0));

        vm.prank(smartAccount);
        bytes4 result = stxValidator.isValidSignatureWithSender(address(0), dataHash, invalidSig);

        assertEq(result, ERC1271_FAILED);
    }

    // NOTE: Error handling tests (InvalidSignatureDataLength, UnrecognizedSignatureType) are covered
    // in StxValidator_SignatureTypeRouting_Test.t.sol via _getSubmodules tests
}
