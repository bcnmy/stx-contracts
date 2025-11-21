// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { MerkleProofLib } from "solady/utils/MerkleProofLib.sol";
import { MEEUserOpHashLib } from "../MEEUserOpHashLib.sol";
import { SIG_VALIDATION_FAILED, _packValidationData } from "account-abstraction/core/Helpers.sol";

import { ISafe } from "../../../interfaces/external/safe-smart-account/ISafe.sol";
import { SafeEnumLib } from "../../../interfaces/external/safe-smart-account/SafeEnumLib.sol";

struct SafeTxnData {
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
 * @dev Library to validate the signature for Safe account mode
 *      In this mode, Safe account is the master account instead of EOA
 *      and is used to validate the signature
 */
library SafeAccountValidatorLib {
    /**
     * @dev Error thrown when the safe transaction execution fails
     */
    error SafeTransactionExecutionFailed();

    /**
     * @dev Validate the user operation for the Safe account mode
     *      This function will validate the user operation using the Safe account mode
     *      In this mode, Safe account is the master account instead of EOA
     *      and is used to validate the signature
     *      The function will:
     *      1. Decode the signature data
     *      2. Get the superTx hash from the safeTxnData
     *      3. Make sure the user operation is part of the merkle tree
     *      4. Make sure the Safe transaction is properly signed by the safe account signers
     *      5. Execute the Safe transaction if the executeTrigger is true
     *      6. Return the validation data
     * @param userOpHash the hash of the user operation
     * @param signatureData the signature data to validate
     * @param safeAccount the safe account to validate the signature for
     */
    function validateUserOp(
        bytes32 userOpHash,
        bytes calldata signatureData,
        address safeAccount
    )
        internal
        returns (uint256)
    {
        DecodedSafeAccountSignatureFull calldata decodedSignature;
        assembly {
            decodedSignature := add(signatureData.offset, 0x20)
        }

        SafeTxnData calldata safeTxnData = decodedSignature.safeTxnData;
        bytes32 superTxHash = _getSuperTxHash(safeTxnData);

        bytes32 meeUserOpHash = MEEUserOpHashLib.getMEEUserOpHash(
            userOpHash, decodedSignature.lowerBoundTimestamp, decodedSignature.upperBoundTimestamp
        );

        if (!MerkleProofLib.verify(decodedSignature.proof, superTxHash, meeUserOpHash)) {
            return SIG_VALIDATION_FAILED;
        }

        if (decodedSignature.executeTrigger) {
            // Execute the Safe transaction by calling ISafe.execTransaction function
            // In this case we do not need to rehash the safe txn data
            // and make sure this hash properly signed by the safe account signers
            // because this is already done within the ISafe.execTransaction function
            try ISafe(safeAccount)
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
                    // but failed to execute the transaction
                    revert SafeTransactionExecutionFailed();
                }
            } catch {
                // Safe transaction execution reverts in case of invalid signature
                // which according to ERC-4337 requires returning SIG_VALIDATION_FAILED,
                // not a revert
                return SIG_VALIDATION_FAILED;
            }
        } else {
            // We do not need to execute the transaction, so we only need to validate the signatures
            // So we validate safe txn data hash is properly signed by the safe account signers
            // by calling ISafe.checkSignatures function
            if (!_areValidSafeAccountSignatures(safeAccount, safeTxnData)) {
                return SIG_VALIDATION_FAILED;
            }
        }

        // if we're here, all is good, return the validation data with `sigValidationFailed` set to false
        return _packValidationData(false, decodedSignature.upperBoundTimestamp, decodedSignature.lowerBoundTimestamp);
    }

    /**
     * @dev Validate the signature is a valid signature of
     * a Safe Smart Account which is the master account in this mode
     * @param safeAccount the safe account to validate the signature for
     * @param dataHash the hash of the data to validate
     * @param signatureData the signature data to validate
     * @return true if the signature is valid, false otherwise
     */
    function validateSignatureForOwner(
        address safeAccount,
        bytes32 dataHash,
        bytes calldata signatureData
    )
        internal
        view
        returns (bool)
    {
        DecodedSafeAccountSignatureShort calldata decodedSignature;
        assembly {
            decodedSignature := add(signatureData.offset, 0x20)
        }
        bytes32 superTxHash = _getSuperTxHash(decodedSignature.safeTxnData);

        if (!MerkleProofLib.verify(decodedSignature.proof, superTxHash, dataHash)) {
            return false;
        }

        return _areValidSafeAccountSignatures(safeAccount, decodedSignature.safeTxnData);
    }

    /**
     * @dev Check if the safe account signatures are valid
     * @param safeAccount the safe account to check the signatures for
     * @param safeTxnData the safe txn data to check the signatures for
     * @return true if the signatures are valid, false otherwise
     */
    function _areValidSafeAccountSignatures(
        address safeAccount,
        SafeTxnData calldata safeTxnData
    )
        private
        view
        returns (bool)
    {
        bytes32 safeTxnDataHash = ISafe(safeAccount)
            .getTransactionHash({
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

        try ISafe(safeAccount).checkSignatures(safeAccount, safeTxnDataHash, safeTxnData.signatures) {
            return true;
        } catch {
            return false;
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
}
