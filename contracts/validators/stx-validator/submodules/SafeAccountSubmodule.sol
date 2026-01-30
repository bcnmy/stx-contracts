// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { MerkleProofLib } from "solady/utils/MerkleProofLib.sol";
import { MEEUserOpHashLib } from "../../../lib/stx-validator/MEEUserOpHashLib.sol";
import { ISafe, SAFE_TX_TYPEHASH } from "../../../interfaces/external/safe-smart-account/ISafe.sol";
import { SafeEnumLib } from "../../../interfaces/external/safe-smart-account/SafeEnumLib.sol";
import { IERC7739Multiplexer } from "../../../interfaces/stx-validator/IERC7739Multiplexer.sol";
import { IStxModeVerifier } from "../../../interfaces/stx-validator/IStxModeVerifier.sol";
import { MODULE_TYPE_STATELESS_VALIDATOR } from "../../../types/Constants.sol";
import {
    IStatelessValidator,
    InvalidErc7780DataLength
} from "../../../interfaces/standard/erc-7780/IStatelessValidator.sol";

struct SafeTxnData {
    bytes32 ogDomainSeparator;
    address to;
    uint256 value;
    bytes data;
    SafeEnumLib.Operation operation;
    uint256 safeTxGas;
    uint256 baseGas;
    uint256 gasPrice;
    address gasToken;
    address payable refundReceiver;
    uint256 nonce;
    bytes signatures;
}

struct DecodedSafeAccountSignatureFull {
    address safeAccount;
    SafeTxnData safeTxnData;
    bytes32[] proof;
    bool executeTrigger;
    uint48 lowerBoundTimestamp;
    uint48 upperBoundTimestamp;
}

struct DecodedSafeAccountSignatureShort {
    SafeTxnData safeTxnData;
    bytes32[] proof;
}

/**
 * @title SafeAccountSubmodule
 * @notice This module is responsible for validating the signature of a given Safe transaction
 *         data object using the Safe account mode.
 * @dev This module implements both the IStxModeVerifier and IStatelessValidator interfaces
 *      so it does both parts of the modular stx verification flow
 */

contract SafeAccountSubmodule is IStxModeVerifier, IStatelessValidator {
    error SafeTransactionExecutionFailed();
    error SafeTransactionInvalidSignature();

    /**
     * @dev Processes the userOp data for the Safe account mode
     *      This function will decode the signature data and verify
     *      the Merkle proof for the superTx hash.
     *      If required, it will execute a Safe transaction.
     * param address account The account that requested userOp processing
     * @param userOpHash The hash of the userOp
     * @param sigData The signature data for the userOp
     * @return bytes The encoded data : timestamps, meeHash, and a clean signature
     */
    function processStxUserOpData(address, bytes32 userOpHash, bytes calldata sigData) external returns (bytes memory) {
        DecodedSafeAccountSignatureFull calldata decodedSignature;
        assembly {
            decodedSignature := add(sigData.offset, 0x20)
        }

        SafeTxnData calldata safeTxnData = decodedSignature.safeTxnData;
        bytes32 superTxHash = _getSuperTxHash(safeTxnData);

        bytes32 meeUserOpHash = MEEUserOpHashLib.getMEEUserOpHash(
            userOpHash, decodedSignature.lowerBoundTimestamp, decodedSignature.upperBoundTimestamp
        );

        if (!MerkleProofLib.verify(decodedSignature.proof, superTxHash, meeUserOpHash)) {
            revert MerkleVerificationFailed();
        }

        bytes memory cleanedSigData;
        bytes32 safeTxHash;

        if (decodedSignature.executeTrigger) {
            // Execute the Safe transaction by calling ISafe.execTransaction function
            // In this case we do not need to rehash the safe txn data
            // and make sure this hash properly signed by the safe account signers
            // because this is already done within the ISafe.execTransaction function
            try ISafe(decodedSignature.safeAccount)
                .execTransaction(
                    safeTxnData.to,
                    safeTxnData.value,
                    safeTxnData.data,
                    safeTxnData.operation,
                    safeTxnData.safeTxGas,
                    safeTxnData.baseGas,
                    safeTxnData.gasPrice,
                    safeTxnData.gasToken,
                    safeTxnData.refundReceiver,
                    safeTxnData.signatures
                ) returns (
                bool success
            ) {
                if (!success) {
                    // execTransaction returns false in case of valid signatures
                    // but failed to execute the transaction, means no reason to proceed
                    // because the trigger was not executed => the whole stx makes no sense
                    revert SafeTransactionExecutionFailed();
                }
                // if the SafeTxn has been executed successfully, that means it
                // was properly signed by the safe account signers =>
                // the only thing we have to do is to further compare the safe account
                // provided here to the actual owner retrieved from the multiplexer storage config
                cleanedSigData = abi.encodePacked(decodedSignature.safeAccount);
                safeTxHash = bytes32(0);
            } catch {
                // Safe transaction execution reverts in case of invalid signature
                // which according to ERC-4337 requires returning SIG_VALIDATION_FAILED,
                // not a revert
                revert SafeTransactionInvalidSignature();
            }
        } else {
            cleanedSigData = safeTxnData.signatures;
            safeTxHash = _getSignedSafeTxnHash(safeTxnData);
        }

        return (abi.encode(
                decodedSignature.lowerBoundTimestamp, decodedSignature.upperBoundTimestamp, safeTxHash, cleanedSigData
            ));
    }

    /**
     * @dev Processes the data object for the SafeAccount fusion mode
     *      This function will decode the signature data and verify
     *      the Merkle proof for the superTx hash.
     *      It will return the data required for the further 1271/7739 signature validation:
     *      proper hash, and a signature.
     * @param dataHash The hash of the data object
     * @param sigData The signature data for the data object
     * @return bytes32 The hash, that was signed
     * @return bytes The clean signature
     */
    function processStxDataObject(
        address account,
        address sender,
        bytes32 dataHash,
        bytes calldata sigData
    )
        external
        view
        returns (bytes32, bytes memory)
    {
        DecodedSafeAccountSignatureShort calldata decodedSignature;
        assembly {
            decodedSignature := add(sigData.offset, 0x20)
        }

        SafeTxnData calldata safeTxnData = decodedSignature.safeTxnData;
        bytes32 superTxHash = _getSuperTxHash(safeTxnData);

        // Add measures against the `two accounts, same owner` attack vector
        // because technically safe txn object doesn't contain the smart account address
        //
        // in theory the smart account address may be present in the calldata
        // since safeTxn is a trigger here, so replaying will lead to funds being transferred to the
        // og smart account, not replaying one, and the replayed stx may fail, however
        // 1) smart account address is not guaranteed to be present in the calldata
        // 2) replayed stx may not fail even if trigger fails because replaying SA may
        //    posess enough balance to execute Stx even w/o trigger being executed
        //
        // we protect against this by rehashing the data hash with the account address
        // we can do that instead of erc-7739 because:
        // 1) Stx hash is injected into the SafeTxn as a blind hash, not as an erc-712 object
        //    so the entries can also be represented as just hashes
        // 2) We could've applied erc-7739 to the full SafeTxn object,
        //    but since erc-7739 involves the full domain separator with the chainId,
        //    it would make end signature to fail on all the destination chains.
        //
        // we also include the chainid to make sure the data struct is not replayable across chains.
        bytes32 entryHash = keccak256(abi.encodePacked(dataHash, account, block.chainid));

        if (!MerkleProofLib.verify(decodedSignature.proof, superTxHash, entryHash)) {
            revert MerkleVerificationFailed();
        }

        return (_getSignedSafeTxnHash(safeTxnData), safeTxnData.signatures);
    }

    /**
     * @dev This function is used to process the data object for the 7780 flow
     * @param dataHash The hash of the data object
     * @param sigData The signature data for the data object
     * @return bytes32 The hash of the data object
     * @return bytes The signature data for the data object
     */
    function processStxDataObjectFor7780Flow(
        address, /* account is not used in the Permit fusion mode */
        bytes32 dataHash,
        bytes calldata sigData
    )
        external
        view
        returns (bytes32, bytes memory)
    {
        DecodedSafeAccountSignatureShort calldata decodedSignature;
        assembly {
            decodedSignature := add(sigData.offset, 0x20)
        }

        SafeTxnData calldata safeTxnData = decodedSignature.safeTxnData;
        bytes32 superTxHash = _getSuperTxHash(safeTxnData);

        if (!MerkleProofLib.verify(decodedSignature.proof, superTxHash, dataHash)) {
            revert MerkleVerificationFailed();
        }

        return (_getSignedSafeTxnHash(safeTxnData), safeTxnData.signatures);
    }

    // ======= ERC - 7780 Interface ===========================

    /**
     * @dev Parses the expected signer from data and
     *      validates a signature over the userOpHash.
     * @param hash The userOpHash to validate the signature over.
     * @param signatures Safe owners' signatures
     * @param data The data to validate the signature against.
     * @return True if the signature is valid, false otherwise.
     */
    function validateSignatureWithData(
        bytes32 hash,
        bytes calldata signatures,
        bytes calldata data
    )
        external
        view
        returns (bool)
    {
        require(data.length >= 40, InvalidErc7780DataLength());
        address safeAccountOwningSmartAccount = address(bytes20(data[:20]));
        address smartAccount = address(bytes20(data[20:40]));

        if (signatures.length == 20) {
            // if signature.length == 20, it means signature was implictly verified by safe account
            // that executed the trigger SafeTxn (see processStxUserOpData function)
            // the only thing we need to make sure is that the safe account owning smart account
            //  is the same as the one that executed the trigger SafeTxn before
            // This is gas saving flow to avoid double signature checking which may be
            // gas heavy for Safe accounts with many signers

            /// forge-lint:disable-next-line(unsafe-typecast)
            return address(bytes20(signatures)) == safeAccountOwningSmartAccount;
        }

        // otherwise, call safe account to validate signature
        try ISafe(safeAccountOwningSmartAccount).checkSignatures(hash, hex"", signatures) {
            return true;
        } catch {
            // if it reverts, try the legacy interface
            try ISafe(safeAccountOwningSmartAccount).checkSignatures(smartAccount, hash, signatures) {
                return true;
            } catch {
                return false;
            }
        }
    }

    function isModuleType(uint256 typeId) external view returns (bool) {
        return typeId == MODULE_TYPE_STATELESS_VALIDATOR;
    }

    // ========================================================

    function _getSignedSafeTxnHash(SafeTxnData calldata safeTxnData) private pure returns (bytes32) {
        return _getSafeTxHashWithDomainSeparator({
            domainSeparator: safeTxnData.ogDomainSeparator,
            to: safeTxnData.to,
            value: safeTxnData.value,
            data: safeTxnData.data,
            operation: safeTxnData.operation,
            safeTxGas: safeTxnData.safeTxGas,
            baseGas: safeTxnData.baseGas,
            gasPrice: safeTxnData.gasPrice,
            gasToken: safeTxnData.gasToken,
            refundReceiver: safeTxnData.refundReceiver,
            _nonce: safeTxnData.nonce
        });
    }

    /**
     * @dev Get the safe tx hash with the provided domain separator
     * @param domainSeparator the domain separator to use
     * @param to the to address
     * @param value the value
     * @param data the data
     * @param operation the operation
     * @param safeTxGas the safe tx gas
     * @param baseGas the base gas
     * @param gasPrice the gas price
     * @param gasToken the gas token
     * @param refundReceiver the refund receiver
     * @param _nonce the nonce
     * @return safeTxHash the safe tx hash
     */
    function _getSafeTxHashWithDomainSeparator(
        bytes32 domainSeparator,
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
        private
        pure
        returns (bytes32 safeTxHash)
    {
        // Mimics the ISafe.getTransactionHash function
        // except it uses the provided domain separator
        assembly {
            // Get the free memory pointer.
            let ptr := mload(0x40)

            // Step 1: Hash the transaction data.
            // Copy transaction data to memory and hash it.
            calldatacopy(ptr, data.offset, data.length)
            let calldataHash := keccak256(ptr, data.length)

            // Step 2: Prepare the SafeTX struct for hashing.
            // Layout in memory:
            // ptr +   0: `SAFE_TX_TYPEHASH` (constant defining the Safe transaction struct hash)
            // ptr +  32: `to`
            // ptr +  64: `value`
            // ptr +  96: `calldataHash = keccak256(data)`
            // ptr + 128: `operation`
            // ptr + 160: `safeTxGas`
            // ptr + 192: `baseGas`
            // ptr + 224: `gasPrice`
            // ptr + 256: `gasToken`
            // ptr + 288: `refundReceiver`
            // ptr + 320: `nonce`
            mstore(ptr, SAFE_TX_TYPEHASH)
            mstore(add(ptr, 32), to)
            mstore(add(ptr, 64), value)
            mstore(add(ptr, 96), calldataHash)
            mstore(add(ptr, 128), operation)
            mstore(add(ptr, 160), safeTxGas)
            mstore(add(ptr, 192), baseGas)
            mstore(add(ptr, 224), gasPrice)
            mstore(add(ptr, 256), gasToken)
            mstore(add(ptr, 288), refundReceiver)
            mstore(add(ptr, 320), _nonce)

            // Step 3: Calculate the final EIP-712 hash.
            // First, hash the SafeTX struct (352 bytes total length).
            mstore(add(ptr, 64), keccak256(ptr, 352))
            // Store the EIP-712 prefix (`0x1901`), note that integers are left-padded with 0's,
            // so the EIP-712 encoded data starts at `add(ptr, 30)`.
            mstore(ptr, 0x1901)
            // Store the domain separator.
            mstore(add(ptr, 32), domainSeparator)
            // Calculate the hash.
            safeTxHash := keccak256(add(ptr, 30), 66)
        }
    }

    /**
     * @dev Get the superTx hash from the safeTxnData
     * it is located at the last 32 bytes of the safeTxnData.data
     * @param safeTxnData the safeTxnData to get the superTx hash from
     * @return superTxHash the superTx hash
     */
    function _getSuperTxHash(SafeTxnData calldata safeTxnData) private pure returns (bytes32 superTxHash) {
        bytes calldata safeTxnCalldata = safeTxnData.data;
        assembly {
            // Get the length of the calldata bytes
            let len := safeTxnCalldata.length
            // Load the last 32 bytes: offset + length - 32
            superTxHash := calldataload(add(safeTxnCalldata.offset, sub(len, 0x20)))
        }
    }

    // =========== REQUIRED BY ERC-7579 SPEC ===========

    function onInstall(bytes calldata data) external override {
        // do nothing
    }

    function onUninstall(bytes calldata data) external override {
        // do nothing
    }

    function isInitialized(address smartAccount) external view returns (bool) {
        // stateless validator is always initialized
        return true;
    }
}
