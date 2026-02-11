// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test, Vm } from "forge-std/Test.sol";
import { SimpleModeSubmodule } from "contracts/validators/stx-validator/submodules/SimpleModeSubmodule.sol";
import { MeeUserOpHashLib } from "contracts/lib/stx-validator/MeeUserOpHashLib.sol";
import { HashLib, SUPER_TX_MEE_USER_OP_ARRAY_TYPEHASH } from "contracts/lib/stx-validator/HashLib.sol";
import { IERC7739Multiplexer } from "contracts/interfaces/stx-validator/IERC7739Multiplexer.sol";
import { _DOMAIN_TYPEHASH } from "contracts/lib/stx-validator/HashLib.sol";

/// @title Mock ERC5267 for testing hashTypedDataForAccount
contract MockERC5267 {
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
        return (bytes1(0x0f), "MockAccount", "1", block.chainid, address(this), bytes32(0), new uint256[](0));
    }
}

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

error UnexpectedSuperTxEntry(bytes32 occurredItemHash, bytes32 expectedItemHash);

/// @title SimpleModeSubmodule Unit Tests
/// @notice Unit tests for SimpleModeSubmodule error cases and edge cases
/// @dev Full happy path flows are tested in e2e tests (StxValidator_Simple_Mode_Test)
contract SimpleModeSubmodule_Test is Test {
    SimpleModeSubmodule internal submodule;
    MockERC5267 internal mockAccount;
    MockERC7739Multiplexer internal mockMultiplexer;

    function setUp() public {
        submodule = new SimpleModeSubmodule();
        mockAccount = new MockERC5267();
        mockMultiplexer = new MockERC7739Multiplexer();
    }

    /*//////////////////////////////////////////////////////////////////////////
                        PROCESS STX USER OP DATA TESTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Test processStxUserOpData reverts when item hash doesn't match
    function test_processStxUserOpData_revertWhen_itemHashMismatch() public {
        bytes32 userOpHash = keccak256("userOpHash");
        uint48 lowerBound = 100;
        uint48 upperBound = 200;

        // Calculate actual MEE userOp hash
        bytes32 actualMeeHash = MeeUserOpHashLib.getMeeUserOpEip712Hash(userOpHash, lowerBound, upperBound);

        // Create itemHashes with a DIFFERENT hash at index 0
        bytes32[] memory itemHashes = new bytes32[](1);
        itemHashes[0] = keccak256("wrong hash");

        // Pack timestamps: lower in upper 128 bits, upper in lower 128 bits
        uint256 packedTimestamps = (uint256(lowerBound) << 128) | uint256(upperBound);

        bytes memory signature = abi.encodePacked(bytes32(uint256(1)), bytes32(uint256(2)), uint8(27));

        bytes memory sigData = abi.encode(
            SUPER_TX_MEE_USER_OP_ARRAY_TYPEHASH, // outerTypeHash
            uint256(0), // itemIndex
            itemHashes,
            signature,
            packedTimestamps
        );

        vm.expectRevert(abi.encodeWithSelector(UnexpectedSuperTxEntry.selector, actualMeeHash, itemHashes[0]));
        submodule.processStxUserOpData(address(mockAccount), userOpHash, sigData);
    }

    /// @notice Test processStxUserOpData correctly unpacks timestamps and returns expected hash
    function test_processStxUserOpData_unpacksTimestampsCorrectly() public {
        bytes32 userOpHash = keccak256("userOpHash");
        uint48 lowerBound = 12_345;
        uint48 upperBound = 67_890;

        // Calculate actual MEE userOp hash
        bytes32 meeHash = MeeUserOpHashLib.getMeeUserOpEip712Hash(userOpHash, lowerBound, upperBound);

        // Create itemHashes with matching hash
        bytes32[] memory itemHashes = new bytes32[](1);
        itemHashes[0] = meeHash;

        // Pack timestamps
        uint256 packedTimestamps = (uint256(lowerBound) << 128) | uint256(upperBound);

        bytes memory signature = abi.encodePacked(bytes32(uint256(1)), bytes32(uint256(2)), uint8(27));

        bytes memory sigData =
            abi.encode(SUPER_TX_MEE_USER_OP_ARRAY_TYPEHASH, uint256(0), itemHashes, signature, packedTimestamps);

        // Calculate expected superTxEip712Hash
        bytes32 expectedHash =
            _calculateExpectedSuperTxHash(address(mockAccount), SUPER_TX_MEE_USER_OP_ARRAY_TYPEHASH, itemHashes);

        bytes memory result = submodule.processStxUserOpData(address(mockAccount), userOpHash, sigData);

        (uint256 retLower, uint256 retUpper, bytes32 retHash, bytes memory retSig) =
            abi.decode(result, (uint256, uint256, bytes32, bytes));

        assertEq(retLower, lowerBound);
        assertEq(retUpper, upperBound);
        assertEq(retHash, expectedHash);
        assertEq(retSig, signature);
    }

    /// @notice Test processStxUserOpData with zero timestamps
    function test_processStxUserOpData_zeroTimestamps() public {
        bytes32 userOpHash = keccak256("userOpHash");
        uint48 lowerBound = 0;
        uint48 upperBound = 0;

        bytes32 meeHash = MeeUserOpHashLib.getMeeUserOpEip712Hash(userOpHash, lowerBound, upperBound);

        bytes32[] memory itemHashes = new bytes32[](1);
        itemHashes[0] = meeHash;

        uint256 packedTimestamps = 0;

        bytes memory signature = abi.encodePacked(bytes32(uint256(1)), bytes32(uint256(2)), uint8(27));

        bytes memory sigData =
            abi.encode(SUPER_TX_MEE_USER_OP_ARRAY_TYPEHASH, uint256(0), itemHashes, signature, packedTimestamps);

        bytes memory result = submodule.processStxUserOpData(address(mockAccount), userOpHash, sigData);

        (uint256 retLower, uint256 retUpper,,) = abi.decode(result, (uint256, uint256, bytes32, bytes));

        assertEq(retLower, 0);
        assertEq(retUpper, 0);
    }

    /// @notice Test processStxUserOpData with item at non-zero index
    function test_processStxUserOpData_itemAtNonZeroIndex() public {
        bytes32 userOpHash = keccak256("userOpHash");
        uint48 lowerBound = 100;
        uint48 upperBound = 200;

        bytes32 meeHash = MeeUserOpHashLib.getMeeUserOpEip712Hash(userOpHash, lowerBound, upperBound);

        // Create itemHashes with our hash at index 2
        bytes32[] memory itemHashes = new bytes32[](3);
        itemHashes[0] = keccak256("other entry 0");
        itemHashes[1] = keccak256("other entry 1");
        itemHashes[2] = meeHash;

        uint256 packedTimestamps = (uint256(lowerBound) << 128) | uint256(upperBound);
        bytes memory signature = abi.encodePacked(bytes32(uint256(1)), bytes32(uint256(2)), uint8(27));

        // Use a custom typeHash for mixed entries (not the pure array typehash)
        bytes32 mixedTypeHash = keccak256("SuperTx(EntryA a,EntryB b,MeeUserOp c)");

        // Calculate expected hash for mixed struct (uses abi.encodePacked path)
        bytes32 expectedHash = _calculateExpectedSuperTxHash(address(mockAccount), mixedTypeHash, itemHashes);

        bytes memory sigData = abi.encode(
            mixedTypeHash,
            uint256(2), // itemIndex = 2
            itemHashes,
            signature,
            packedTimestamps
        );

        bytes memory result = submodule.processStxUserOpData(address(mockAccount), userOpHash, sigData);

        (,, bytes32 retHash, bytes memory retSig) = abi.decode(result, (uint256, uint256, bytes32, bytes));

        assertEq(retHash, expectedHash);
        assertEq(retSig, signature);
    }

    /*//////////////////////////////////////////////////////////////////////////
                        PROCESS STX DATA OBJECT TESTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Test processStxDataObject reverts when item hash doesn't match
    function test_processStxDataObject_revertWhen_itemHashMismatch() public {
        bytes32 dataHash = keccak256("dataHash");

        // Set up mock to return a specific ERC7739 hash
        bytes32 erc7739Hash = keccak256("erc7739 hash");
        bytes memory erc7739Sig = abi.encodePacked(bytes32(uint256(99)));
        mockMultiplexer.setReturn(erc7739Hash, erc7739Sig);

        // Create itemHashes with a DIFFERENT hash
        bytes32[] memory itemHashes = new bytes32[](1);
        itemHashes[0] = keccak256("wrong hash");

        bytes memory signature = abi.encodePacked(bytes32(uint256(1)), bytes32(uint256(2)), uint8(27));

        bytes memory sigData = abi.encode(SUPER_TX_MEE_USER_OP_ARRAY_TYPEHASH, uint256(0), itemHashes, signature);

        vm.prank(address(mockMultiplexer));
        vm.expectRevert(abi.encodeWithSelector(UnexpectedSuperTxEntry.selector, erc7739Hash, itemHashes[0]));
        submodule.processStxDataObject(address(mockAccount), address(0x1234), dataHash, sigData);
    }

    /// @notice Test processStxDataObject delegates to ERC7739 multiplexer and returns expected hash
    function test_processStxDataObject_delegatesToErc7739Multiplexer() public {
        bytes32 dataHash = keccak256("dataHash");

        // Set up mock to return expected values
        bytes32 erc7739Hash = keccak256("erc7739 hash");
        bytes memory erc7739Sig = abi.encodePacked(bytes32(uint256(99)));
        mockMultiplexer.setReturn(erc7739Hash, erc7739Sig);

        // Create itemHashes with the ERC7739 hash
        bytes32[] memory itemHashes = new bytes32[](1);
        itemHashes[0] = erc7739Hash;

        bytes memory signature = abi.encodePacked(bytes32(uint256(1)), bytes32(uint256(2)), uint8(27));

        bytes memory sigData = abi.encode(SUPER_TX_MEE_USER_OP_ARRAY_TYPEHASH, uint256(0), itemHashes, signature);

        // Calculate expected superTxEip712Hash
        bytes32 expectedHash =
            _calculateExpectedSuperTxHash(address(mockAccount), SUPER_TX_MEE_USER_OP_ARRAY_TYPEHASH, itemHashes);

        vm.prank(address(mockMultiplexer));
        (bytes32 retHash, bytes memory retSig) =
            submodule.processStxDataObject(address(mockAccount), address(0x1234), dataHash, sigData);

        // Should return the superTx EIP712 hash
        assertEq(retHash, expectedHash);
        // Signature should be the one from ERC7739 multiplexer
        assertEq(retSig, erc7739Sig);
    }

    /*//////////////////////////////////////////////////////////////////////////
                    PROCESS STX DATA OBJECT FOR 7780 FLOW TESTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Test processStxDataObjectFor7780Flow reverts when item hash doesn't match
    function test_processStxDataObjectFor7780Flow_revertWhen_itemHashMismatch() public {
        bytes32 dataHash = keccak256("dataHash");

        // Create itemHashes with a DIFFERENT hash
        bytes32[] memory itemHashes = new bytes32[](1);
        itemHashes[0] = keccak256("wrong hash");

        bytes memory signature = abi.encodePacked(bytes32(uint256(1)), bytes32(uint256(2)), uint8(27));

        bytes memory sigData = abi.encode(SUPER_TX_MEE_USER_OP_ARRAY_TYPEHASH, uint256(0), itemHashes, signature);

        vm.expectRevert(abi.encodeWithSelector(UnexpectedSuperTxEntry.selector, dataHash, itemHashes[0]));
        submodule.processStxDataObjectFor7780Flow(address(mockAccount), dataHash, sigData);
    }

    /// @notice Test processStxDataObjectFor7780Flow returns correct values when hash matches
    function test_processStxDataObjectFor7780Flow_returnsCorrectValues() public view {
        bytes32 dataHash = keccak256("dataHash");

        // Create itemHashes with matching hash
        bytes32[] memory itemHashes = new bytes32[](1);
        itemHashes[0] = dataHash;

        bytes memory signature = abi.encodePacked(bytes32(uint256(1)), bytes32(uint256(2)), uint8(27));

        bytes memory sigData = abi.encode(SUPER_TX_MEE_USER_OP_ARRAY_TYPEHASH, uint256(0), itemHashes, signature);

        // Calculate expected superTxEip712Hash
        bytes32 expectedHash =
            _calculateExpectedSuperTxHash(address(mockAccount), SUPER_TX_MEE_USER_OP_ARRAY_TYPEHASH, itemHashes);

        (bytes32 retHash, bytes memory retSig) =
            submodule.processStxDataObjectFor7780Flow(address(mockAccount), dataHash, sigData);

        assertEq(retHash, expectedHash);
        assertEq(retSig, signature);
    }

    /// @notice Test processStxDataObjectFor7780Flow with multiple items
    function test_processStxDataObjectFor7780Flow_multipleItems() public view {
        bytes32 dataHash = keccak256("dataHash");

        // Create itemHashes with our hash at index 1
        bytes32[] memory itemHashes = new bytes32[](3);
        itemHashes[0] = keccak256("entry 0");
        itemHashes[1] = dataHash;
        itemHashes[2] = keccak256("entry 2");

        bytes memory signature = abi.encodePacked(bytes32(uint256(1)), bytes32(uint256(2)), uint8(27));

        bytes32 mixedTypeHash = keccak256("SuperTx(EntryA a,DataObject b,EntryC c)");

        // Calculate expected superTxEip712Hash
        bytes32 expectedHash = _calculateExpectedSuperTxHash(address(mockAccount), mixedTypeHash, itemHashes);

        bytes memory sigData = abi.encode(
            mixedTypeHash,
            uint256(1), // itemIndex = 1
            itemHashes,
            signature
        );

        (bytes32 retHash, bytes memory retSig) =
            submodule.processStxDataObjectFor7780Flow(address(mockAccount), dataHash, sigData);

        assertEq(retHash, expectedHash);
        assertEq(retSig, signature);
    }

    /*//////////////////////////////////////////////////////////////////////////
                        FUZZ TESTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Fuzz test timestamp unpacking
    function testFuzz_processStxUserOpData_timestampUnpacking(uint48 lowerBound, uint48 upperBound) public {
        bytes32 userOpHash = keccak256("userOpHash");

        bytes32 meeHash = MeeUserOpHashLib.getMeeUserOpEip712Hash(userOpHash, lowerBound, upperBound);

        bytes32[] memory itemHashes = new bytes32[](1);
        itemHashes[0] = meeHash;

        uint256 packedTimestamps = (uint256(lowerBound) << 128) | uint256(upperBound);
        bytes memory signature = abi.encodePacked(bytes32(uint256(1)), bytes32(uint256(2)), uint8(27));

        bytes memory sigData =
            abi.encode(SUPER_TX_MEE_USER_OP_ARRAY_TYPEHASH, uint256(0), itemHashes, signature, packedTimestamps);

        bytes memory result = submodule.processStxUserOpData(address(mockAccount), userOpHash, sigData);

        (uint256 retLower, uint256 retUpper,,) = abi.decode(result, (uint256, uint256, bytes32, bytes));

        assertEq(retLower, lowerBound);
        assertEq(retUpper, upperBound);
    }

    /// @notice Fuzz test item index bounds
    function testFuzz_processStxDataObjectFor7780Flow_itemIndex(uint8 numItems, uint8 targetIndex) public view {
        vm.assume(numItems > 0 && numItems <= 10);
        vm.assume(targetIndex < numItems);

        bytes32 dataHash = keccak256("dataHash");

        bytes32[] memory itemHashes = new bytes32[](numItems);
        for (uint256 i = 0; i < numItems; i++) {
            if (i == targetIndex) {
                itemHashes[i] = dataHash;
            } else {
                itemHashes[i] = keccak256(abi.encode("entry", i));
            }
        }

        bytes memory signature = abi.encodePacked(bytes32(uint256(1)), bytes32(uint256(2)), uint8(27));
        bytes32 typeHash = keccak256("SuperTx(...)");

        // Calculate expected hash
        bytes32 expectedHash = _calculateExpectedSuperTxHash(address(mockAccount), typeHash, itemHashes);

        bytes memory sigData = abi.encode(typeHash, uint256(targetIndex), itemHashes, signature);

        (bytes32 retHash, bytes memory retSig) =
            submodule.processStxDataObjectFor7780Flow(address(mockAccount), dataHash, sigData);

        assertEq(retHash, expectedHash);
        assertEq(retSig, signature);
    }

    /*//////////////////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Calculates expected superTxEip712Hash matching HashLib.compareAndGetFinalHashForAccount logic
    function _calculateExpectedSuperTxHash(
        address account,
        bytes32 outerTypeHash,
        bytes32[] memory itemHashes
    )
        internal
        view
        returns (bytes32)
    {
        bytes32 structHash;
        if (outerTypeHash == SUPER_TX_MEE_USER_OP_ARRAY_TYPEHASH) {
            // For pure MeeUserOps array: hash the concatenation of itemHashes
            bytes32 encodedData = keccak256(abi.encodePacked(itemHashes));
            structHash = keccak256(abi.encode(outerTypeHash, encodedData));
        } else {
            // For mixed struct: concat typeHash with all itemHashes
            structHash = keccak256(abi.encodePacked(outerTypeHash, itemHashes));
        }

        // Get account's EIP-712 domain name
        (, string memory name,,,,,) = MockERC5267(account).eip712Domain();

        // Build domain separator: keccak256(_DOMAIN_TYPEHASH, keccak256(name))
        bytes32 domainSeparator = keccak256(abi.encode(_DOMAIN_TYPEHASH, keccak256(bytes(name))));

        // Final EIP-712 hash
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }
}
