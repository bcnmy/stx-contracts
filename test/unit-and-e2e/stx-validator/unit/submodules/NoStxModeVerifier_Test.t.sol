// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { NoStxModeVerifier } from "contracts/validators/stx-validator/submodules/NoStxModeVerifier.sol";
import { IERC7739Multiplexer } from "contracts/interfaces/stx-validator/IERC7739Multiplexer.sol";

/// @title Mock ERC7739 Multiplexer for testing processStxDataObject
contract MockERC7739Multiplexer is IERC7739Multiplexer {
    bytes32 public returnHash;
    bytes public returnSignature;

    function setReturn(bytes32 _hash, bytes memory _sig) external {
        returnHash = _hash;
        returnSignature = _sig;
    }

    function getErc7739HashAndSignature(
        address,
        address,
        bytes32,
        bytes calldata
    )
        external
        view
        returns (bytes32, bytes memory)
    {
        return (returnHash, returnSignature);
    }
}

/// @title NoStxModeVerifier Unit Tests
/// @notice Unit tests for NoStxModeVerifier (fallback for non-STX flows)
contract NoStxModeVerifier_Test is Test {
    NoStxModeVerifier internal verifier;
    MockERC7739Multiplexer internal mockMultiplexer;

    function setUp() public {
        verifier = new NoStxModeVerifier();
        mockMultiplexer = new MockERC7739Multiplexer();
    }

    /*//////////////////////////////////////////////////////////////////////////
                        PROCESS STX USER OP DATA TESTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Test processStxUserOpData returns hash and signature unchanged with zero timestamps
    function test_processStxUserOpData_returnsUnchangedWithZeroTimestamps() public {
        bytes32 userOpHash = keccak256("userOpHash");
        bytes memory sigData = abi.encodePacked(bytes32(uint256(1)), bytes32(uint256(2)), uint8(27));

        bytes memory result = verifier.processStxUserOpData(address(0), userOpHash, sigData);

        (uint48 lowerBound, uint48 upperBound, bytes32 returnedHash, bytes memory returnedSig) =
            abi.decode(result, (uint48, uint48, bytes32, bytes));

        assertEq(lowerBound, 0);
        assertEq(upperBound, 0);
        assertEq(returnedHash, userOpHash);
        assertEq(returnedSig, sigData);
    }

    /// @notice Test processStxUserOpData with empty signature
    function test_processStxUserOpData_emptySignature() public {
        bytes32 userOpHash = keccak256("userOpHash");
        bytes memory sigData = "";

        bytes memory result = verifier.processStxUserOpData(address(0), userOpHash, sigData);

        (uint48 lowerBound, uint48 upperBound, bytes32 returnedHash, bytes memory returnedSig) =
            abi.decode(result, (uint48, uint48, bytes32, bytes));

        assertEq(lowerBound, 0);
        assertEq(upperBound, 0);
        assertEq(returnedHash, userOpHash);
        assertEq(returnedSig.length, 0);
    }

    /*//////////////////////////////////////////////////////////////////////////
                        PROCESS STX DATA OBJECT TESTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Test processStxDataObject delegates to ERC7739 multiplexer (msg.sender)
    function test_processStxDataObject_delegatesToErc7739Multiplexer() public {
        bytes32 dataHash = keccak256("dataHash");
        bytes memory sigData = abi.encodePacked(bytes32(uint256(1)), bytes32(uint256(2)), uint8(27));

        // Set expected return values from the mock
        bytes32 expectedHash = keccak256("7739 processed hash");
        bytes memory expectedSig = abi.encodePacked(bytes32(uint256(99)));
        mockMultiplexer.setReturn(expectedHash, expectedSig);

        // Call via the mock (which becomes msg.sender)
        vm.prank(address(mockMultiplexer));
        (bytes32 returnedHash, bytes memory returnedSig) =
            verifier.processStxDataObject(address(0x1234), address(0x5678), dataHash, sigData);

        assertEq(returnedHash, expectedHash);
        assertEq(returnedSig, expectedSig);
    }

    /*//////////////////////////////////////////////////////////////////////////
                    PROCESS STX DATA OBJECT FOR 7780 FLOW TESTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Test processStxDataObjectFor7780Flow returns hash and signature unchanged
    function test_processStxDataObjectFor7780Flow_returnsUnchanged() public view {
        bytes32 dataHash = keccak256("dataHash");
        bytes memory sigData = abi.encodePacked(bytes32(uint256(1)), bytes32(uint256(2)), uint8(27));

        (bytes32 returnedHash, bytes memory returnedSig) =
            verifier.processStxDataObjectFor7780Flow(address(0), dataHash, sigData);

        assertEq(returnedHash, dataHash);
        assertEq(returnedSig, sigData);
    }

    /// @notice Test processStxDataObjectFor7780Flow with empty signature
    function test_processStxDataObjectFor7780Flow_emptySignature() public view {
        bytes32 dataHash = keccak256("dataHash");
        bytes memory sigData = "";

        (bytes32 returnedHash, bytes memory returnedSig) =
            verifier.processStxDataObjectFor7780Flow(address(0), dataHash, sigData);

        assertEq(returnedHash, dataHash);
        assertEq(returnedSig.length, 0);
    }

    /*//////////////////////////////////////////////////////////////////////////
                            FUZZ TESTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Fuzz test processStxUserOpData always returns input unchanged
    function testFuzz_processStxUserOpData(bytes32 userOpHash, bytes calldata sigData) public {
        bytes memory result = verifier.processStxUserOpData(address(0), userOpHash, sigData);

        (uint48 lowerBound, uint48 upperBound, bytes32 returnedHash, bytes memory returnedSig) =
            abi.decode(result, (uint48, uint48, bytes32, bytes));

        assertEq(lowerBound, 0);
        assertEq(upperBound, 0);
        assertEq(returnedHash, userOpHash);
        assertEq(returnedSig, sigData);
    }

    /// @notice Fuzz test processStxDataObjectFor7780Flow always returns input unchanged
    function testFuzz_processStxDataObjectFor7780Flow(bytes32 dataHash, bytes calldata sigData) public view {
        (bytes32 returnedHash, bytes memory returnedSig) =
            verifier.processStxDataObjectFor7780Flow(address(0), dataHash, sigData);

        assertEq(returnedHash, dataHash);
        assertEq(returnedSig, sigData);
    }
}
