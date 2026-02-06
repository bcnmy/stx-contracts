// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { StxValidator_Unit_Base_Test } from "./StxValidator_Unit_Base_Test.t.sol";
import { IERC5267 } from "@openzeppelin/contracts/interfaces/IERC5267.sol";

/// @title Minimal mock account implementing ERC5267 for ERC-7739 tests
contract MockERC5267Account is IERC5267 {
    function eip712Domain()
        external
        view
        returns (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        )
    {
        return (bytes1(0x0f), "MockAccount", "1.0", block.chainid, address(this), bytes32(0), new uint256[](0));
    }
}

/// @title StxValidator ERC-7739 Multiplexer Interface Tests
/// @notice Unit tests for getErc7739HashAndSignature functionality
/// @dev Tests safe caller bypass and nested EIP-712 processing
contract StxValidator_ERC7739Multiplexer_Test is StxValidator_Unit_Base_Test {
    // MulticallerWithSigner canonical address (always safe)
    address internal constant MULTICALLER_WITH_SIGNER = 0x000000000000D9ECebf3C23529de49815Dac1c4c;

    MockERC5267Account internal mockAccount;

    function setUp() public override {
        super.setUp();
        mockAccount = new MockERC5267Account();
    }

    /*//////////////////////////////////////////////////////////////////////////
                              SAFE CALLER TESTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Test that safe caller (MulticallerWithSigner) returns hash and signature unchanged
    function test_getErc7739HashAndSignature_safeCaller_returnsUnchanged() public view {
        bytes32 originalHash = keccak256("test data");
        bytes memory originalSig = abi.encodePacked(bytes32(uint256(1)), bytes32(uint256(2)), uint8(27));

        (bytes32 returnedHash, bytes memory returnedSig) =
            stxValidator.getErc7739HashAndSignature(smartAccount, MULTICALLER_WITH_SIGNER, originalHash, originalSig);

        assertEq(returnedHash, originalHash);
        assertEq(returnedSig, originalSig);
    }

    /// @notice Test that safe caller (account itself) returns hash and signature unchanged
    function test_getErc7739HashAndSignature_accountIsSafeSender_returnsUnchanged() public view {
        bytes32 originalHash = keccak256("test data");
        bytes memory originalSig = abi.encodePacked(bytes32(uint256(1)), bytes32(uint256(2)), uint8(27));

        // Account calling itself is safe (sender == account)
        (bytes32 returnedHash, bytes memory returnedSig) =
            stxValidator.getErc7739HashAndSignature(smartAccount, smartAccount, originalHash, originalSig);

        assertEq(returnedHash, originalHash);
        assertEq(returnedSig, originalSig);
    }

    /// @notice Test that added safe sender returns hash and signature unchanged
    function test_getErc7739HashAndSignature_addedSafeSender_returnsUnchanged() public {
        address safeSender = makeAddr("safeSender");

        // Add safe sender for smartAccount
        vm.prank(smartAccount);
        stxValidator.addSafeSender(safeSender);

        bytes32 originalHash = keccak256("test data");
        bytes memory originalSig = abi.encodePacked(bytes32(uint256(1)), bytes32(uint256(2)), uint8(27));

        (bytes32 returnedHash, bytes memory returnedSig) =
            stxValidator.getErc7739HashAndSignature(smartAccount, safeSender, originalHash, originalSig);

        assertEq(returnedHash, originalHash);
        assertEq(returnedSig, originalSig);
    }

    /*//////////////////////////////////////////////////////////////////////////
                              UNSAFE CALLER TESTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Test that unsafe caller triggers ERC-7739 processing (hash rehashed, signature trimmed)
    /// @dev ERC-7739 signature format for TypedDataSign:
    ///      [actual_signature][APP_DOMAIN_SEPARATOR (32)][contents_hash (32)][contentsDescription][length (2)]
    function test_getErc7739HashAndSignature_unsafeCaller_processesNestedEIP712() public {
        address unsafeSender = makeAddr("unsafeSender");

        // Build a valid ERC-7739 TypedDataSign signature
        bytes memory actualSignature = abi.encodePacked(bytes32(uint256(1)), bytes32(uint256(2)), uint8(27)); // 65
        // bytes

        // ERC-7739 appended data
        bytes32 appDomainSeparator = keccak256("app domain");
        bytes32 contentsHash = keccak256("contents");
        bytes memory contentsDescription = "bytes32 contents"; // 16 bytes
        uint16 contentsDescriptionLength = uint16(contentsDescription.length);

        // Build the full signature with ERC-7739 appended data
        bytes memory fullSignature = abi.encodePacked(
            actualSignature, appDomainSeparator, contentsHash, contentsDescription, contentsDescriptionLength
        );

        // The original hash should be the hash of "\x19\x01" + appDomainSeparator + contentsHash
        bytes32 originalHash = keccak256(abi.encodePacked(bytes2(0x1901), appDomainSeparator, contentsHash));

        // Use mockAccount which implements ERC5267
        (bytes32 returnedHash, bytes memory returnedSig) =
            stxValidator.getErc7739HashAndSignature(address(mockAccount), unsafeSender, originalHash, fullSignature);

        // Hash should be different (rehashed via ERC-7739)
        assertNotEq(returnedHash, originalHash);

        // Signature should be trimmed (appended data removed)
        // Trimmed length = fullSignature.length - (32 + 32 + contentsDescription.length + 2)
        uint256 appendedDataLength = 32 + 32 + contentsDescription.length + 2; // 82 bytes
        assertEq(returnedSig.length, fullSignature.length - appendedDataLength);
        assertEq(returnedSig.length, actualSignature.length);
    }

    /// @notice Test that unsafe caller with invalid appended data falls back to PersonalSign workflow
    /// @dev When appended data is invalid, PersonalSign workflow is used (hash = _hashTypedData(hash))
    function test_getErc7739HashAndSignature_unsafeCaller_invalidAppendedData_fallsBackToPersonalSign() public {
        address unsafeSender = makeAddr("unsafeSender");

        // Simple signature without valid ERC-7739 appended data
        bytes memory simpleSignature = abi.encodePacked(bytes32(uint256(1)), bytes32(uint256(2)), uint8(27));
        bytes32 originalHash = keccak256("test data");

        // Use mockAccount which implements ERC5267
        (bytes32 returnedHash, bytes memory returnedSig) =
            stxValidator.getErc7739HashAndSignature(address(mockAccount), unsafeSender, originalHash, simpleSignature);

        // Hash should be different (PersonalSign workflow rehashes it)
        assertNotEq(returnedHash, originalHash);

        // Signature should remain unchanged in PersonalSign workflow (no trimming)
        assertEq(returnedSig.length, simpleSignature.length);
    }
}
