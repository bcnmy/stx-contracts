// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test, Vm } from "forge-std/Test.sol";
import {
    SafeAccountSubmodule,
    SafeTxnData,
    DecodedSafeAccountSignatureFull,
    DecodedSafeAccountSignatureShort
} from "contracts/validators/stx-validator/submodules/SafeAccountSubmodule.sol";
import { ISafe, SAFE_TX_TYPEHASH } from "contracts/interfaces/external/safe-smart-account/ISafe.sol";
import { SafeEnumLib } from "contracts/interfaces/external/safe-smart-account/SafeEnumLib.sol";
import { MeeUserOpHashLib } from "contracts/lib/stx-validator/MeeUserOpHashLib.sol";
import { HashLib } from "contracts/lib/stx-validator/HashLib.sol";
import { MerkleTreeLib } from "solady/utils/MerkleTreeLib.sol";
import { InvalidErc7780DataLength } from "contracts/interfaces/standard/erc-7780/IStatelessValidator.sol";
import { MODULE_TYPE_STATELESS_VALIDATOR } from "contracts/types/Constants.sol";
import { IStxModeVerifier } from "contracts/interfaces/stx-validator/IStxModeVerifier.sol";

/// @title Mock Safe Account for unit testing
contract MockSafeAccount {
    bytes32 public domainSeparatorValue;
    uint256 public nonceValue;
    bool public execTransactionShouldSucceed = true;
    bool public execTransactionShouldRevert = false;
    bool public defaultCheckShouldRevert = false;
    bool public fallbackCheckShouldRevert = false;

    bytes public lastExecTransactionData;
    bytes public lastCheckSignaturesData;

    function setDomainSeparator(bytes32 _domainSeparator) external {
        domainSeparatorValue = _domainSeparator;
    }

    function setNonce(uint256 _nonce) external {
        nonceValue = _nonce;
    }

    function setExecTransactionBehavior(bool shouldSucceed, bool shouldRevert) external {
        execTransactionShouldSucceed = shouldSucceed;
        execTransactionShouldRevert = shouldRevert;
    }

    function setCheckSignaturesBehavior(bool defaultRevert, bool fallbackRevert) external {
        defaultCheckShouldRevert = defaultRevert;
        fallbackCheckShouldRevert = fallbackRevert;
    }

    function domainSeparator() external view returns (bytes32) {
        return domainSeparatorValue;
    }

    function nonce() external view returns (uint256) {
        return nonceValue;
    }

    function execTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        SafeEnumLib.Operation operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes memory signatures
    )
        external
        payable
        returns (bool success)
    {
        lastExecTransactionData =
            abi.encode(to, value, data, operation, safeTxGas, baseGas, gasPrice, gasToken, refundReceiver, signatures);

        if (execTransactionShouldRevert) {
            revert("Safe transaction reverted");
        }
        return execTransactionShouldSucceed;
    }

    function checkSignatures(bytes32, bytes memory, bytes memory) external {
        if (defaultCheckShouldRevert) {
            revert("default checkSignatures failed");
        }
    }

    function checkSignatures(address, bytes32, bytes memory) external {
        if (fallbackCheckShouldRevert) {
            revert("fallback checkSignatures failed");
        }
    }

    function getTransactionHash(
        address to,
        uint256 value,
        bytes calldata data,
        SafeEnumLib.Operation operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address refundReceiver,
        uint256 _nonce
    )
        external
        view
        returns (bytes32)
    {
        bytes32 safeTxHash = keccak256(
            abi.encode(
                SAFE_TX_TYPEHASH,
                to,
                value,
                keccak256(data),
                operation,
                safeTxGas,
                baseGas,
                gasPrice,
                gasToken,
                refundReceiver,
                _nonce
            )
        );
        return keccak256(abi.encodePacked(bytes1(0x19), bytes1(0x01), domainSeparatorValue, safeTxHash));
    }
}

/// @title SafeAccountSubmodule Unit Tests
/// @notice Unit tests for SafeAccountSubmodule (Safe account fusion mode)
/// @dev Tests merkle verification, signature validation, and Safe transaction execution
contract SafeAccountSubmodule_Test is Test {
    using MerkleTreeLib for bytes32[];

    SafeAccountSubmodule internal submodule;
    MockSafeAccount internal mockSafe;

    bytes32 internal constant MOCK_DOMAIN_SEPARATOR = keccak256("mock domain separator");

    address internal smartAccount;
    address internal sender;

    function setUp() public {
        submodule = new SafeAccountSubmodule();
        mockSafe = new MockSafeAccount();
        mockSafe.setDomainSeparator(MOCK_DOMAIN_SEPARATOR);
        mockSafe.setNonce(0);

        smartAccount = makeAddr("smartAccount");
        sender = makeAddr("sender");
    }

    /*//////////////////////////////////////////////////////////////////////////
                        PROCESS STX USER OP DATA TESTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Test processStxUserOpData with executeTrigger=true executes Safe transaction
    function test_processStxUserOpData_executeTrigger_executesSafeTxn() public {
        bytes32 userOpHash = keccak256("userOpHash");
        uint48 lowerBound = 100;
        uint48 upperBound = 200;

        // Build merkle tree with single leaf
        bytes32 meeUserOpHash = MeeUserOpHashLib.getMeeUserOpHash(userOpHash, lowerBound, upperBound);
        bytes32[] memory leaves = new bytes32[](1);

        // Create SafeTxnData with superTxHash as last 32 bytes of data
        SafeTxnData memory safeTxnData = _createSafeTxnData(meeUserOpHash);
        bytes32 superTxHash = _getSuperTxHash(safeTxnData);
        leaves[0] = meeUserOpHash;

        bytes32[] memory tree = leaves.build();
        bytes32 root = tree.root();

        // Update safeTxnData.data to include the root
        safeTxnData.data = abi.encodePacked(safeTxnData.data, root);

        // Recalculate superTxHash after updating data
        superTxHash = _getSuperTxHash(safeTxnData);
        assertEq(superTxHash, root, "superTxHash should equal root");

        bytes32[] memory proof = tree.leafProof(0);

        DecodedSafeAccountSignatureFull memory decoded = DecodedSafeAccountSignatureFull({
            safeAccount: address(mockSafe),
            safeTxnData: safeTxnData,
            proof: proof,
            executeTrigger: true,
            lowerBoundTimestamp: lowerBound,
            upperBoundTimestamp: upperBound
        });

        bytes memory sigData = abi.encode(decoded);

        bytes memory result = submodule.processStxUserOpData(smartAccount, userOpHash, sigData);

        (uint48 retLower, uint48 retUpper, bytes32 retHash, bytes memory retSig) =
            abi.decode(result, (uint48, uint48, bytes32, bytes));

        assertEq(retLower, lowerBound);
        assertEq(retUpper, upperBound);
        // When executeTrigger=true and succeeds, safeTxHash is bytes32(0)
        assertEq(retHash, bytes32(0));
        // cleanedSigData is just the safe account address
        assertEq(retSig, abi.encodePacked(address(mockSafe)));
    }

    /// @notice Test processStxUserOpData with executeTrigger=false returns signature and hash
    function test_processStxUserOpData_noExecuteTrigger_returnsSignatureAndHash() public {
        bytes32 userOpHash = keccak256("userOpHash");
        uint48 lowerBound = 100;
        uint48 upperBound = 200;

        bytes32 meeUserOpHash = MeeUserOpHashLib.getMeeUserOpHash(userOpHash, lowerBound, upperBound);
        bytes32[] memory leaves = new bytes32[](1);

        SafeTxnData memory safeTxnData = _createSafeTxnData(meeUserOpHash);
        leaves[0] = meeUserOpHash;

        bytes32[] memory tree = leaves.build();
        bytes32 root = tree.root();

        safeTxnData.data = abi.encodePacked(safeTxnData.data, root);

        // Calculate expected safe txn hash
        bytes32 expectedSafeTxHash = _getSignedSafeTxnHash(safeTxnData);

        bytes32[] memory proof = tree.leafProof(0);

        DecodedSafeAccountSignatureFull memory decoded = DecodedSafeAccountSignatureFull({
            safeAccount: address(mockSafe),
            safeTxnData: safeTxnData,
            proof: proof,
            executeTrigger: false,
            lowerBoundTimestamp: lowerBound,
            upperBoundTimestamp: upperBound
        });

        bytes memory sigData = abi.encode(decoded);

        bytes memory result = submodule.processStxUserOpData(smartAccount, userOpHash, sigData);

        (uint48 retLower, uint48 retUpper, bytes32 retHash, bytes memory retSig) =
            abi.decode(result, (uint48, uint48, bytes32, bytes));

        assertEq(retLower, lowerBound);
        assertEq(retUpper, upperBound);
        // When executeTrigger=false, returns the signed safe txn hash
        assertEq(retHash, expectedSafeTxHash);
        // cleanedSigData is the original signatures
        assertEq(retSig, safeTxnData.signatures);
    }

    /// @notice Test processStxUserOpData reverts when merkle proof is invalid
    function test_processStxUserOpData_revertWhen_merkleProofInvalid() public {
        bytes32 userOpHash = keccak256("userOpHash");
        uint48 lowerBound = 100;
        uint48 upperBound = 200;

        bytes32 meeUserOpHash = MeeUserOpHashLib.getMeeUserOpHash(userOpHash, lowerBound, upperBound);

        // Create tree with different leaf
        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = keccak256("different leaf");

        bytes32[] memory tree = leaves.build();
        bytes32 root = tree.root();

        SafeTxnData memory safeTxnData = _createSafeTxnData(meeUserOpHash);
        safeTxnData.data = abi.encodePacked(safeTxnData.data, root);

        bytes32[] memory proof = tree.leafProof(0);

        DecodedSafeAccountSignatureFull memory decoded = DecodedSafeAccountSignatureFull({
            safeAccount: address(mockSafe),
            safeTxnData: safeTxnData,
            proof: proof,
            executeTrigger: false,
            lowerBoundTimestamp: lowerBound,
            upperBoundTimestamp: upperBound
        });

        bytes memory sigData = abi.encode(decoded);

        vm.expectRevert(IStxModeVerifier.MerkleVerificationFailed.selector);
        submodule.processStxUserOpData(smartAccount, userOpHash, sigData);
    }

    /// @notice Test processStxUserOpData reverts when Safe transaction execution fails (returns false)
    function test_processStxUserOpData_revertWhen_safeTxnExecutionFails() public {
        bytes32 userOpHash = keccak256("userOpHash");
        uint48 lowerBound = 100;
        uint48 upperBound = 200;

        bytes32 meeUserOpHash = MeeUserOpHashLib.getMeeUserOpHash(userOpHash, lowerBound, upperBound);
        bytes32[] memory leaves = new bytes32[](1);

        SafeTxnData memory safeTxnData = _createSafeTxnData(meeUserOpHash);
        leaves[0] = meeUserOpHash;

        bytes32[] memory tree = leaves.build();
        bytes32 root = tree.root();

        safeTxnData.data = abi.encodePacked(safeTxnData.data, root);

        bytes32[] memory proof = tree.leafProof(0);

        // Set mock to return false (execution failed but didn't revert)
        mockSafe.setExecTransactionBehavior(false, false);

        DecodedSafeAccountSignatureFull memory decoded = DecodedSafeAccountSignatureFull({
            safeAccount: address(mockSafe),
            safeTxnData: safeTxnData,
            proof: proof,
            executeTrigger: true,
            lowerBoundTimestamp: lowerBound,
            upperBoundTimestamp: upperBound
        });

        bytes memory sigData = abi.encode(decoded);

        vm.expectRevert(SafeAccountSubmodule.SafeTransactionExecutionFailed.selector);
        submodule.processStxUserOpData(smartAccount, userOpHash, sigData);
    }

    /// @notice Test processStxUserOpData reverts when Safe transaction reverts (invalid signature)
    function test_processStxUserOpData_revertWhen_safeTxnReverts() public {
        bytes32 userOpHash = keccak256("userOpHash");
        uint48 lowerBound = 100;
        uint48 upperBound = 200;

        bytes32 meeUserOpHash = MeeUserOpHashLib.getMeeUserOpHash(userOpHash, lowerBound, upperBound);
        bytes32[] memory leaves = new bytes32[](1);

        SafeTxnData memory safeTxnData = _createSafeTxnData(meeUserOpHash);
        leaves[0] = meeUserOpHash;

        bytes32[] memory tree = leaves.build();
        bytes32 root = tree.root();

        safeTxnData.data = abi.encodePacked(safeTxnData.data, root);

        bytes32[] memory proof = tree.leafProof(0);

        // Set mock to revert (simulates invalid signature)
        mockSafe.setExecTransactionBehavior(false, true);

        DecodedSafeAccountSignatureFull memory decoded = DecodedSafeAccountSignatureFull({
            safeAccount: address(mockSafe),
            safeTxnData: safeTxnData,
            proof: proof,
            executeTrigger: true,
            lowerBoundTimestamp: lowerBound,
            upperBoundTimestamp: upperBound
        });

        bytes memory sigData = abi.encode(decoded);

        vm.expectRevert(SafeAccountSubmodule.SafeTransactionInvalidSignature.selector);
        submodule.processStxUserOpData(smartAccount, userOpHash, sigData);
    }

    /*//////////////////////////////////////////////////////////////////////////
                        PROCESS STX DATA OBJECT TESTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Test processStxDataObject rehashes with account and chainId
    function test_processStxDataObject_rehashesWithAccountAndChainId() public view {
        bytes32 dataHash = keccak256("dataHash");

        // Calculate expected entry hash (rehashed with account and chainId)
        bytes32 entryHash = HashLib.rehashWithAccountAndChainId(dataHash, smartAccount, block.chainid);

        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = entryHash;

        bytes32[] memory tree = leaves.build();
        bytes32 root = tree.root();

        SafeTxnData memory safeTxnData = _createSafeTxnDataWithRoot(root);
        bytes32 expectedSafeTxHash = _getSignedSafeTxnHash(safeTxnData);
        bytes32[] memory proof = tree.leafProof(0);

        DecodedSafeAccountSignatureShort memory decoded =
            DecodedSafeAccountSignatureShort({ safeTxnData: safeTxnData, proof: proof });

        bytes memory sigData = abi.encode(decoded);

        (bytes32 retHash, bytes memory retSig) = submodule.processStxDataObject(smartAccount, sender, dataHash, sigData);

        // Returns the signed safe txn hash
        assertEq(retHash, expectedSafeTxHash);
        assertEq(retSig, safeTxnData.signatures);
    }

    /// @notice Test processStxDataObject reverts when merkle proof is invalid
    function test_processStxDataObject_revertWhen_merkleProofInvalid() public {
        bytes32 dataHash = keccak256("dataHash");

        // Create tree with different leaf (not rehashed properly)
        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = dataHash; // Wrong - should be rehashed

        bytes32[] memory tree = leaves.build();
        bytes32 root = tree.root();

        SafeTxnData memory safeTxnData = _createSafeTxnDataWithRoot(root);
        bytes32[] memory proof = tree.leafProof(0);

        DecodedSafeAccountSignatureShort memory decoded =
            DecodedSafeAccountSignatureShort({ safeTxnData: safeTxnData, proof: proof });

        bytes memory sigData = abi.encode(decoded);

        vm.expectRevert(IStxModeVerifier.MerkleVerificationFailed.selector);
        submodule.processStxDataObject(smartAccount, sender, dataHash, sigData);
    }

    /// @notice Test processStxDataObject is chain-specific (different chainId fails)
    function test_processStxDataObject_chainSpecific_differentChainIdFails() public {
        bytes32 dataHash = keccak256("dataHash");

        // Rehash with different chainId
        uint256 differentChainId = block.chainid + 1;
        bytes32 entryHash = HashLib.rehashWithAccountAndChainId(dataHash, smartAccount, differentChainId);

        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = entryHash;

        bytes32[] memory tree = leaves.build();
        bytes32 root = tree.root();

        SafeTxnData memory safeTxnData = _createSafeTxnDataWithRoot(root);
        bytes32[] memory proof = tree.leafProof(0);

        DecodedSafeAccountSignatureShort memory decoded =
            DecodedSafeAccountSignatureShort({ safeTxnData: safeTxnData, proof: proof });

        bytes memory sigData = abi.encode(decoded);

        // Should fail because current chain's chainId doesn't match
        vm.expectRevert(IStxModeVerifier.MerkleVerificationFailed.selector);
        submodule.processStxDataObject(smartAccount, sender, dataHash, sigData);
    }

    /*//////////////////////////////////////////////////////////////////////////
                    PROCESS STX DATA OBJECT FOR 7780 FLOW TESTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Test processStxDataObjectFor7780Flow does NOT rehash (uses dataHash directly)
    function test_processStxDataObjectFor7780Flow_noRehashing() public view {
        bytes32 dataHash = keccak256("dataHash");

        // For 7780 flow, use dataHash directly (no rehashing)
        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = dataHash;

        bytes32[] memory tree = leaves.build();
        bytes32 root = tree.root();

        SafeTxnData memory safeTxnData = _createSafeTxnDataWithRoot(root);
        bytes32 expectedSafeTxHash = _getSignedSafeTxnHash(safeTxnData);
        bytes32[] memory proof = tree.leafProof(0);

        DecodedSafeAccountSignatureShort memory decoded =
            DecodedSafeAccountSignatureShort({ safeTxnData: safeTxnData, proof: proof });

        bytes memory sigData = abi.encode(decoded);

        (bytes32 retHash, bytes memory retSig) =
            submodule.processStxDataObjectFor7780Flow(smartAccount, dataHash, sigData);

        assertEq(retHash, expectedSafeTxHash);
        assertEq(retSig, safeTxnData.signatures);
    }

    /// @notice Test processStxDataObjectFor7780Flow reverts when merkle proof is invalid
    function test_processStxDataObjectFor7780Flow_revertWhen_merkleProofInvalid() public {
        bytes32 dataHash = keccak256("dataHash");

        // Create tree with different leaf
        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = keccak256("different data");

        bytes32[] memory tree = leaves.build();
        bytes32 root = tree.root();

        SafeTxnData memory safeTxnData = _createSafeTxnDataWithRoot(root);
        bytes32[] memory proof = tree.leafProof(0);

        DecodedSafeAccountSignatureShort memory decoded =
            DecodedSafeAccountSignatureShort({ safeTxnData: safeTxnData, proof: proof });

        bytes memory sigData = abi.encode(decoded);

        vm.expectRevert(IStxModeVerifier.MerkleVerificationFailed.selector);
        submodule.processStxDataObjectFor7780Flow(smartAccount, dataHash, sigData);
    }

    /*//////////////////////////////////////////////////////////////////////////
                    VALIDATE SIGNATURE WITH DATA TESTS (ERC-7780)
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Test validateSignatureWithData with 20-byte signature (shortcut flow)
    function test_validateSignatureWithData_20ByteSignature_shortcutFlow() public view {
        bytes32 hash = keccak256("hash");
        address safeAccount = address(mockSafe);

        // 20-byte signature = just the safe account address (shortcut after executeTrigger)
        bytes memory signature = abi.encodePacked(safeAccount);
        assertEq(signature.length, 20);

        // Data: safeAccount (20 bytes)
        bytes memory data = abi.encodePacked(safeAccount);

        bool result = submodule.validateSignatureWithData(hash, signature, data);

        assertTrue(result);
    }

    /// @notice Test validateSignatureWithData with 20-byte signature fails when address mismatch
    function test_validateSignatureWithData_20ByteSignature_addressMismatch_returnsFalse() public {
        bytes32 hash = keccak256("hash");
        address safeAccount = address(mockSafe);
        address differentSafe = address(0xdead);

        // Signature contains different safe address
        bytes memory signature = abi.encodePacked(differentSafe);

        // Data expects the original safe account
        bytes memory data = abi.encodePacked(safeAccount);

        bool result = submodule.validateSignatureWithData(hash, signature, data);

        assertFalse(result);
    }

    /// @notice Test validateSignatureWithData with full signature calls checkSignatures
    function test_validateSignatureWithData_fullSignature_callsDefaultCheckSignatures() public {
        bytes32 hash = keccak256("hash");
        address safeAccount = address(mockSafe);

        mockSafe.setCheckSignaturesBehavior({ defaultRevert: false, fallbackRevert: true });

        // Full signature (> 20 bytes)
        bytes memory signature = abi.encodePacked(bytes32(uint256(1)), bytes32(uint256(2)), uint8(27));

        bytes memory data = abi.encodePacked(safeAccount);

        bool result = submodule.validateSignatureWithData(hash, signature, data);

        assertTrue(result);
    }

    /// @notice Test validateSignatureWithData returns false when both checkSignatures methods revert
    function test_validateSignatureWithData_bothCheckSignaturesFail_returnsFalse() public {
        bytes32 hash = keccak256("hash");
        address safeAccount = address(mockSafe);

        // Set both check methods to revert
        mockSafe.setCheckSignaturesBehavior({ defaultRevert: true, fallbackRevert: true });

        bytes memory signature = abi.encodePacked(bytes32(uint256(1)), bytes32(uint256(2)), uint8(27));
        bytes memory data = abi.encodePacked(safeAccount);

        // Both checks should revert
        bool result = submodule.validateSignatureWithData(hash, signature, data);

        assertFalse(result);
    }

    /// @notice Test validateSignatureWithData falls back to fallback checkSignatures when default fails
    function test_validateSignatureWithData_fallsBackToFallbackCheckSignatures_whenDefaultFails() public {
        bytes32 hash = keccak256("hash");
        address safeAccount = address(mockSafe);

        // Default check reverts, fallback succeeds
        mockSafe.setCheckSignaturesBehavior({ defaultRevert: true, fallbackRevert: false });

        bytes memory signature = abi.encodePacked(bytes32(uint256(1)), bytes32(uint256(2)), uint8(27));
        bytes memory data = abi.encodePacked(safeAccount);

        // Fallback check should succeed
        bool result = submodule.validateSignatureWithData(hash, signature, data);
        assertTrue(result);
    }

    /// @notice Test validateSignatureWithData reverts when data length < 20 bytes
    function test_validateSignatureWithData_revertWhen_dataLengthLessThan20() public {
        bytes32 hash = keccak256("hash");
        bytes memory signature = abi.encodePacked(bytes32(uint256(1)), bytes32(uint256(2)), uint8(27));

        // Only 20 bytes (missing smartAccount)
        bytes memory shortData = abi.encodePacked(bytes19(0));
        assertEq(shortData.length, 19);

        vm.expectRevert(InvalidErc7780DataLength.selector);
        submodule.validateSignatureWithData(hash, signature, shortData);
    }

    /// @notice Test validateSignatureWithData reverts when data is empty
    function test_validateSignatureWithData_revertWhen_dataEmpty() public {
        bytes32 hash = keccak256("hash");
        bytes memory signature = abi.encodePacked(bytes32(uint256(1)), bytes32(uint256(2)), uint8(27));
        bytes memory emptyData = "";

        vm.expectRevert(InvalidErc7780DataLength.selector);
        submodule.validateSignatureWithData(hash, signature, emptyData);
    }

    /*//////////////////////////////////////////////////////////////////////////
                            MODULE TYPE TESTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Test isModuleType returns true for MODULE_TYPE_STATELESS_VALIDATOR
    function test_isModuleType_statelessValidator_returnsTrue() public view {
        assertTrue(submodule.isModuleType(MODULE_TYPE_STATELESS_VALIDATOR));
    }

    /// @notice Test isModuleType returns false for other module types
    function test_isModuleType_otherTypes_returnsFalse() public view {
        assertFalse(submodule.isModuleType(1)); // MODULE_TYPE_VALIDATOR
        assertFalse(submodule.isModuleType(2)); // MODULE_TYPE_EXECUTOR
        assertFalse(submodule.isModuleType(3)); // MODULE_TYPE_FALLBACK
        assertFalse(submodule.isModuleType(4)); // MODULE_TYPE_HOOK
        assertFalse(submodule.isModuleType(0));
    }

    /*//////////////////////////////////////////////////////////////////////////
                        LIFECYCLE FUNCTIONS TESTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Test onInstall does nothing (no revert)
    function test_onInstall_doesNothing() public {
        submodule.onInstall("");
        submodule.onInstall(abi.encodePacked(bytes32(0)));
    }

    /// @notice Test onUninstall does nothing (no revert)
    function test_onUninstall_doesNothing() public {
        submodule.onUninstall("");
        submodule.onUninstall(abi.encodePacked(bytes32(0)));
    }

    /// @notice Test isInitialized always returns true (stateless)
    function test_isInitialized_alwaysReturnsTrue() public view {
        assertTrue(submodule.isInitialized(address(0)));
        assertTrue(submodule.isInitialized(address(this)));
        assertTrue(submodule.isInitialized(smartAccount));
    }

    /*//////////////////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    function _createSafeTxnData(bytes32) internal view returns (SafeTxnData memory) {
        return SafeTxnData({
            ogDomainSeparator: MOCK_DOMAIN_SEPARATOR,
            to: address(0x1234),
            value: 0,
            data: abi.encodeWithSignature("transfer(address,uint256)", address(0xdead), 100),
            operation: SafeEnumLib.Operation.Call,
            safeTxGas: 0,
            baseGas: 0,
            gasPrice: 0,
            gasToken: address(0),
            refundReceiver: payable(address(0)),
            nonce: 0,
            signatures: abi.encodePacked(bytes32(uint256(1)), bytes32(uint256(2)), uint8(27))
        });
    }

    function _createSafeTxnDataWithRoot(bytes32 root) internal view returns (SafeTxnData memory) {
        return SafeTxnData({
            ogDomainSeparator: MOCK_DOMAIN_SEPARATOR,
            to: address(0x1234),
            value: 0,
            data: abi.encodePacked(abi.encodeWithSignature("transfer(address,uint256)", address(0xdead), 100), root),
            operation: SafeEnumLib.Operation.Call,
            safeTxGas: 0,
            baseGas: 0,
            gasPrice: 0,
            gasToken: address(0),
            refundReceiver: payable(address(0)),
            nonce: 0,
            signatures: abi.encodePacked(bytes32(uint256(1)), bytes32(uint256(2)), uint8(27))
        });
    }

    function _getSuperTxHash(SafeTxnData memory safeTxnData) internal pure returns (bytes32 superTxHash) {
        bytes memory data = safeTxnData.data;
        uint256 len = data.length;
        assembly {
            superTxHash := mload(add(data, len))
        }
    }

    /// @dev Mirrors the contract's _getSignedSafeTxnHash logic
    function _getSignedSafeTxnHash(SafeTxnData memory safeTxnData) internal pure returns (bytes32) {
        bytes32 safeTxStructHash = keccak256(
            abi.encode(
                SAFE_TX_TYPEHASH,
                safeTxnData.to,
                safeTxnData.value,
                keccak256(safeTxnData.data),
                safeTxnData.operation,
                safeTxnData.safeTxGas,
                safeTxnData.baseGas,
                safeTxnData.gasPrice,
                safeTxnData.gasToken,
                safeTxnData.refundReceiver,
                safeTxnData.nonce
            )
        );
        return keccak256(abi.encodePacked(bytes1(0x19), bytes1(0x01), safeTxnData.ogDomainSeparator, safeTxStructHash));
    }
}
