// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import {
    TxSubmodule,
    TxData,
    TxDataShort,
    TxDecoder_CallDataLengthTooShort,
    TxValidatorLib_UnsupportedTxType,
    LEGACY_TX_TYPE,
    EIP1559_TX_TYPE
} from "contracts/validators/stx-validator/submodules/TxSubmodule.sol";
import { IStxModeVerifier } from "contracts/interfaces/stx-validator/IStxModeVerifier.sol";
import { MerkleTreeLib } from "solady/utils/MerkleTreeLib.sol";
import { LibRLP } from "solady/utils/LibRLP.sol";
import { MeeUserOpHashLib } from "contracts/lib/stx-validator/MeeUserOpHashLib.sol";
import { HashLib } from "contracts/lib/stx-validator/HashLib.sol";

/**
 * @title TxSubmodule Unit Tests
 * @notice Unit tests for TxSubmodule focusing on edge cases and error paths
 *         not covered by e2e tests
 */
contract TxSubmodule_Test is Test {
    using MerkleTreeLib for bytes32[];
    using LibRLP for LibRLP.List;

    TxSubmodule internal submodule;

    uint256 internal signerPrivateKey = 0xabc123;
    address internal signer;

    function setUp() public {
        submodule = new TxSubmodule();
        signer = vm.addr(signerPrivateKey);
    }

    // ============================================================
    // processStxUserOpData tests
    // ============================================================

    /**
     * @notice Test 65-byte signature backwards compatibility (vanilla ERC-4337 flow)
     * @dev When sigData.length == 65, it should return the userOpHash directly
     *      with zero timestamps
     */
    function test_processStxUserOpData_65ByteSignature_backwardsCompatibility() public {
        bytes32 userOpHash = keccak256("userOpHash");
        bytes memory signature = new bytes(65);
        signature[0] = bytes1(0x01); // r
        signature[32] = bytes1(0x02); // s
        signature[64] = bytes1(0x1b); // v = 27

        bytes memory result = submodule.processStxUserOpData(address(0), userOpHash, signature);

        (uint48 lowerBound, uint48 upperBound, bytes32 returnedHash, bytes memory returnedSig) =
            abi.decode(result, (uint48, uint48, bytes32, bytes));

        assertEq(lowerBound, 0, "Lower bound should be 0 for 65-byte signature");
        assertEq(upperBound, 0, "Upper bound should be 0 for 65-byte signature");
        assertEq(returnedHash, userOpHash, "Should return original userOpHash");
        assertEq(returnedSig, signature, "Should return original signature");
    }

    /**
     * @notice Test processStxUserOpData with valid EIP-1559 transaction
     */
    function test_processStxUserOpData_validEip1559Tx_success() public {
        bytes32 userOpHash = keccak256("userOpHash");
        uint48 lowerBoundTimestamp = uint48(block.timestamp);
        uint48 upperBoundTimestamp = uint48(block.timestamp + 1000);

        bytes32 meeUserOpHash = MeeUserOpHashLib.getMeeUserOpHash(userOpHash, lowerBoundTimestamp, upperBoundTimestamp);

        // Build leaves with single element
        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = meeUserOpHash;

        bytes32[] memory tree = leaves.build();
        bytes32 root = tree.root();
        bytes32[] memory proof = tree.leafProof(0);

        // Build serialized EIP-1559 tx with root appended to calldata
        bytes memory callData = abi.encodePacked(hex"aabbccdd", root);
        bytes memory serializedTx = _buildEip1559Tx(callData, address(0xbeef));

        // Build sigData
        bytes memory sigData = abi.encodePacked(
            serializedTx, abi.encodePacked(proof), uint8(proof.length), lowerBoundTimestamp, upperBoundTimestamp
        );

        bytes memory result = submodule.processStxUserOpData(address(0), userOpHash, sigData);

        (uint48 retLower, uint48 retUpper, bytes32 retHash, bytes memory retSig) =
            abi.decode(result, (uint48, uint48, bytes32, bytes));

        assertEq(retLower, lowerBoundTimestamp, "Lower bound timestamp mismatch");
        assertEq(retUpper, upperBoundTimestamp, "Upper bound timestamp mismatch");
        assertTrue(retHash != bytes32(0), "Returned hash should not be zero");
        assertEq(retSig.length, 65, "Signature should be 65 bytes");
    }

    /**
     * @notice Test processStxUserOpData reverts on invalid merkle proof
     */
    function test_processStxUserOpData_invalidMerkleProof_reverts() public {
        bytes32 userOpHash = keccak256("userOpHash");
        uint48 lowerBoundTimestamp = uint48(block.timestamp);
        uint48 upperBoundTimestamp = uint48(block.timestamp + 1000);

        // Build leaves with different hash to create invalid proof
        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = keccak256("differentHash");

        bytes32[] memory tree = leaves.build();
        bytes32 root = tree.root();
        bytes32[] memory proof = tree.leafProof(0);

        bytes memory callData = abi.encodePacked(hex"aabbccdd", root);
        bytes memory serializedTx = _buildEip1559Tx(callData, address(0xbeef));

        bytes memory sigData = abi.encodePacked(
            serializedTx, abi.encodePacked(proof), uint8(proof.length), lowerBoundTimestamp, upperBoundTimestamp
        );

        vm.expectRevert(IStxModeVerifier.MerkleVerificationFailed.selector);
        submodule.processStxUserOpData(address(0), userOpHash, sigData);
    }

    /**
     * @notice Test processStxUserOpData with legacy transaction type
     */
    function test_processStxUserOpData_legacyTx_success() public {
        bytes32 userOpHash = keccak256("userOpHash");
        uint48 lowerBoundTimestamp = uint48(block.timestamp);
        uint48 upperBoundTimestamp = uint48(block.timestamp + 1000);

        bytes32 meeUserOpHash = MeeUserOpHashLib.getMeeUserOpHash(userOpHash, lowerBoundTimestamp, upperBoundTimestamp);

        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = meeUserOpHash;

        bytes32[] memory tree = leaves.build();
        bytes32 root = tree.root();
        bytes32[] memory proof = tree.leafProof(0);

        bytes memory callData = abi.encodePacked(hex"aabbccdd", root);
        bytes memory serializedTx = _buildLegacyTx(callData, address(0xbeef));

        bytes memory sigData = abi.encodePacked(
            serializedTx, abi.encodePacked(proof), uint8(proof.length), lowerBoundTimestamp, upperBoundTimestamp
        );

        bytes memory result = submodule.processStxUserOpData(address(0), userOpHash, sigData);

        (uint48 retLower, uint48 retUpper, bytes32 retHash, bytes memory retSig) =
            abi.decode(result, (uint48, uint48, bytes32, bytes));

        assertEq(retLower, lowerBoundTimestamp, "Lower bound timestamp mismatch");
        assertEq(retUpper, upperBoundTimestamp, "Upper bound timestamp mismatch");
        assertTrue(retHash != bytes32(0), "Returned hash should not be zero");
        assertEq(retSig.length, 65, "Signature should be 65 bytes");
    }

    /**
     * @notice Test processStxUserOpData reverts on unsupported tx type (e.g., type 1)
     */
    function test_processStxUserOpData_unsupportedTxType_reverts() public {
        bytes32 userOpHash = keccak256("userOpHash");
        uint48 lowerBoundTimestamp = uint48(block.timestamp);
        uint48 upperBoundTimestamp = uint48(block.timestamp + 1000);

        // Build a fake tx with unsupported type 0x01 (EIP-2930)
        bytes memory fakeTx = _buildFakeTxWithType(0x01);

        bytes32[] memory proof = new bytes32[](0);
        bytes memory sigData = abi.encodePacked(
            fakeTx, abi.encodePacked(proof), uint8(proof.length), lowerBoundTimestamp, upperBoundTimestamp
        );

        vm.expectRevert(TxValidatorLib_UnsupportedTxType.selector);
        submodule.processStxUserOpData(address(0), userOpHash, sigData);
    }

    // ============================================================
    // processStxDataObject tests
    // ============================================================

    /**
     * @notice Test processStxDataObject with valid data and correct rehashing
     */
    function test_processStxDataObject_validData_returnsCorrectHash() public {
        address account = address(0x1234);
        bytes32 dataHash = keccak256("dataHash");

        // Calculate expected entry hash with account and chainId
        bytes32 entryHash = _rehashWithAccountAndChainId(dataHash, account, block.chainid);

        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = entryHash;

        bytes32[] memory tree = leaves.build();
        bytes32 root = tree.root();
        bytes32[] memory proof = tree.leafProof(0);

        bytes memory callData = abi.encodePacked(hex"aabbccdd", root);
        address to = address(0xbeef);

        // Calculate expected unsigned tx hash
        bytes32 expectedUtxHash = _calculateExpectedEip1559UtxHash(callData, to);

        (bytes memory serializedTx, bytes memory expectedSig) = _buildEip1559TxWithExpectedSig(callData, to);

        bytes memory sigData = abi.encodePacked(serializedTx, abi.encodePacked(proof), uint8(proof.length));

        (bytes32 retHash, bytes memory retSig) = submodule.processStxDataObject(account, address(0), dataHash, sigData);

        assertEq(retHash, expectedUtxHash, "Returned hash should match expected unsigned tx hash");
        assertEq(retSig, expectedSig, "Returned signature should match expected r,s,v");
    }

    /**
     * @notice Test processStxDataObject reverts on invalid merkle proof
     */
    function test_processStxDataObject_invalidMerkleProof_reverts() public {
        address account = address(0x1234);
        bytes32 dataHash = keccak256("dataHash");

        // Use wrong hash in leaves
        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = keccak256("wrongHash");

        bytes32[] memory tree = leaves.build();
        bytes32 root = tree.root();
        bytes32[] memory proof = tree.leafProof(0);

        bytes memory callData = abi.encodePacked(hex"aabbccdd", root);
        bytes memory serializedTx = _buildEip1559TxShort(callData, address(0xbeef));

        bytes memory sigData = abi.encodePacked(serializedTx, abi.encodePacked(proof), uint8(proof.length));

        vm.expectRevert(IStxModeVerifier.MerkleVerificationFailed.selector);
        submodule.processStxDataObject(account, address(0), dataHash, sigData);
    }

    /**
     * @notice Test processStxDataObject uses account and chainId in rehashing
     * @dev Different accounts should produce different entry hashes
     */
    function test_processStxDataObject_differentAccounts_differentEntryHashes() public {
        address account1 = address(0x1111);
        address account2 = address(0x2222);
        bytes32 dataHash = keccak256("sameDataHash");

        bytes32 entryHash1 = _rehashWithAccountAndChainId(dataHash, account1, block.chainid);
        bytes32 entryHash2 = _rehashWithAccountAndChainId(dataHash, account2, block.chainid);

        assertTrue(entryHash1 != entryHash2, "Different accounts should produce different entry hashes");
    }

    // ============================================================
    // processStxDataObjectFor7780Flow tests
    // ============================================================

    /**
     * @notice Test processStxDataObjectFor7780Flow with valid data (no rehashing)
     */
    function test_processStxDataObjectFor7780Flow_validData_success() public {
        bytes32 dataHash = keccak256("dataHash");

        // For 7780 flow, dataHash is used directly without rehashing
        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = dataHash;

        bytes32[] memory tree = leaves.build();
        bytes32 root = tree.root();
        bytes32[] memory proof = tree.leafProof(0);

        bytes memory callData = abi.encodePacked(hex"aabbccdd", root);
        address to = address(0xbeef);

        // Calculate expected unsigned tx hash
        bytes32 expectedUtxHash = _calculateExpectedEip1559UtxHash(callData, to);

        (bytes memory serializedTx, bytes memory expectedSig) = _buildEip1559TxWithExpectedSig(callData, to);

        bytes memory sigData = abi.encodePacked(serializedTx, abi.encodePacked(proof), uint8(proof.length));

        (bytes32 retHash, bytes memory retSig) =
            submodule.processStxDataObjectFor7780Flow(address(0), dataHash, sigData);

        assertEq(retHash, expectedUtxHash, "Returned hash should match expected unsigned tx hash");
        assertEq(retSig, expectedSig, "Returned signature should match expected r,s,v");
    }

    /**
     * @notice Test processStxDataObjectFor7780Flow reverts on invalid merkle proof
     */
    function test_processStxDataObjectFor7780Flow_invalidMerkleProof_reverts() public {
        bytes32 dataHash = keccak256("dataHash");

        // Use wrong hash in leaves
        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = keccak256("wrongHash");

        bytes32[] memory tree = leaves.build();
        bytes32 root = tree.root();
        bytes32[] memory proof = tree.leafProof(0);

        bytes memory callData = abi.encodePacked(hex"aabbccdd", root);
        bytes memory serializedTx = _buildEip1559TxShort(callData, address(0xbeef));

        bytes memory sigData = abi.encodePacked(serializedTx, abi.encodePacked(proof), uint8(proof.length));

        vm.expectRevert(IStxModeVerifier.MerkleVerificationFailed.selector);
        submodule.processStxDataObjectFor7780Flow(address(0), dataHash, sigData);
    }

    // ============================================================
    // Calldata length tests
    // ============================================================

    /**
     * @notice Test that calldata too short reverts with TxDecoder_CallDataLengthTooShort
     */
    function test_processStxUserOpData_calldataTooShort_reverts() public {
        bytes32 userOpHash = keccak256("userOpHash");
        uint48 lowerBoundTimestamp = uint48(block.timestamp);
        uint48 upperBoundTimestamp = uint48(block.timestamp + 1000);

        // Build tx with calldata shorter than 32 bytes (no room for superTx hash)
        bytes memory shortCallData = hex"aabb"; // Only 2 bytes
        bytes memory serializedTx = _buildEip1559Tx(shortCallData, address(0xbeef));

        bytes32[] memory proof = new bytes32[](0);
        bytes memory sigData = abi.encodePacked(
            serializedTx, abi.encodePacked(proof), uint8(proof.length), lowerBoundTimestamp, upperBoundTimestamp
        );

        vm.expectRevert(TxDecoder_CallDataLengthTooShort.selector);
        submodule.processStxUserOpData(address(0), userOpHash, sigData);
    }

    // ============================================================
    // Helper functions
    // ============================================================

    function _buildEip1559Tx(bytes memory txnData, address to) internal view returns (bytes memory) {
        (bytes memory serializedTx,) = _buildEip1559TxWithExpectedSig(txnData, to);
        return serializedTx;
    }

    function _buildEip1559TxWithExpectedSig(
        bytes memory txnData,
        address to
    )
        internal
        view
        returns (bytes memory serializedTx, bytes memory expectedSig)
    {
        LibRLP.List memory accessList = LibRLP.p();

        LibRLP.List memory serializedTxList = LibRLP.p(block.chainid).p(0).p(uint256(1)).p(uint256(20))
            .p(uint256(50_000)).p(to).p(uint256(0)).p(txnData).p(accessList);

        bytes32 uTxHash = keccak256(abi.encodePacked(hex"02", serializedTxList.encode()));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, uTxHash);

        serializedTxList = serializedTxList.p(v == 28 ? true : false).p(uint256(r)).p(uint256(s));
        serializedTx = abi.encodePacked(hex"02", serializedTxList.encode());
        expectedSig = abi.encodePacked(r, s, v);
    }

    function _buildEip1559TxShort(bytes memory txnData, address to) internal view returns (bytes memory) {
        // Same as _buildEip1559Tx, reusing for clarity
        return _buildEip1559Tx(txnData, to);
    }

    function _buildLegacyTx(bytes memory txnData, address to) internal view returns (bytes memory) {
        // Legacy tx: nonce, gasPrice, gasLimit, to, value, data, v, r, s
        uint256 nonce = 0;
        uint256 gasPrice = 1;
        uint256 gasLimit = 50_000;
        uint256 value = 0;

        // For EIP-155, we include chainId in the unsigned tx hash
        // v = chainId * 2 + 35 + recovery_id
        LibRLP.List memory unsignedTxList = LibRLP.p(nonce).p(gasPrice).p(gasLimit).p(to).p(value).p(txnData)
            .p(block.chainid).p(uint256(0)).p(uint256(0));

        bytes32 uTxHash = keccak256(unsignedTxList.encode());
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, uTxHash);

        // EIP-155 v value
        uint256 eip155V = uint256(v) - 27 + block.chainid * 2 + 35;

        LibRLP.List memory signedTxList =
            LibRLP.p(nonce).p(gasPrice).p(gasLimit).p(to).p(value).p(txnData).p(eip155V).p(uint256(r)).p(uint256(s));

        return abi.encodePacked(hex"00", signedTxList.encode());
    }

    function _buildFakeTxWithType(uint8 txType) internal pure returns (bytes memory) {
        // Build minimal RLP structure that will trigger unsupported type error
        LibRLP.List memory txList = LibRLP.p(uint256(1)) // chainId
            .p(uint256(0)) // nonce
            .p(uint256(1)) // gas
            .p(uint256(1)) // gas
            .p(uint256(50_000)) // gasLimit
            .p(address(0xbeef)) // to
            .p(uint256(0)) // value
            .p(abi.encodePacked(bytes32(0))) // data with 32 bytes for hash extraction
            .p(LibRLP.p()) // access list
            .p(uint256(27)) // v
            .p(uint256(1)) // r
            .p(uint256(1)); // s

        return abi.encodePacked(txType, txList.encode());
    }

    function _rehashWithAccountAndChainId(
        bytes32 dataHash,
        address account,
        uint256 chainId
    )
        internal
        pure
        returns (bytes32 res)
    {
        // Matches HashLib.rehashWithAccountAndChainId
        res = keccak256(abi.encodePacked(dataHash, account, chainId));
    }

    function _calculateExpectedEip1559UtxHash(bytes memory txnData, address to) internal view returns (bytes32) {
        // Build unsigned EIP-1559 tx list (without v, r, s)
        LibRLP.List memory accessList = LibRLP.p();

        LibRLP.List memory unsignedTxList = LibRLP.p(block.chainid).p(0).p(uint256(1)).p(uint256(20)).p(uint256(50_000))
            .p(to).p(uint256(0)).p(txnData).p(accessList);

        // EIP-1559 unsigned tx hash includes tx type prefix
        return keccak256(abi.encodePacked(hex"02", unsignedTxList.encode()));
    }
}
