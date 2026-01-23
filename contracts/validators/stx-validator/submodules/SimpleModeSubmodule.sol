// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { MerkleProofLib } from "solady/utils/MerkleProofLib.sol";
import { EcdsaHelperLib } from "../../../lib/util/EcdsaHelperLib.sol";
import { MEEUserOpHashLib } from "../../../lib/stx-validator/MEEUserOpHashLib.sol";
import { IStxModeVerifier } from "contracts/interfaces/stx-validator/IStxModeVerifier.sol";
import { EfficientHashLib } from "solady/utils/EfficientHashLib.sol";
import { SIG_VALIDATION_FAILED, _packValidationData } from "account-abstraction/core/Helpers.sol";
import { UserOperationLib } from "account-abstraction/core/UserOperationLib.sol";
// solhint-disable-next-line no-unused-import
import { HashLib, STATIC_HEAD_LENGTH } from "../../../lib/stx-validator/HashLib.sol";

/**
 * @dev Submodule to validate the signature for Simple Stx mode
 *      In this mode, Fusion is not involved and just the superTx hash is signed
 */

contract SimpleModeSubmodule is IStxModeVerifier {
    error UnexpectedSuperTxEntry(bytes32 occurredItemHash, bytes32 expectedItemHash);

    /**
     * @dev
     *
     * @param userOpHash The hash of the userOp
     * @param sigData The signature data for the userOp
     * @return bytes The encoded data : timestamps, meeHash, and a clean signature
     */
    function processStxUserOpData(bytes32 userOpHash, bytes calldata sigData) external returns (bytes memory) {
        /*
         * packedSignatureData layout :
         * ======== static head part : 0x80 (128) bytes========
         * ... static head part ...
         * ======== static tail for simple mode =====
         * uint256 = 32 bytes : packedTimestamps
         * packedTimestamps is expected to be in the following format:
         * lowerBoundTimestamp in the most significant 128 bits (left)
         * upperBoundTimestamp in the least significant 128 bits (right)
         * ======== dynamic tail  ==========
         * ... dynamic tail ...
         */
        (bytes32 outerTypeHash, uint256 itemIndex, bytes32[] calldata itemHashes, bytes calldata signature) =
            HashLib.parsePackedSigDataHead(sigData);

        bytes32 packedTimestamps;
        assembly {
            packedTimestamps := calldataload(add(sigData.offset, STATIC_HEAD_LENGTH))
        }
        (uint256 lowerBoundTimestamp, uint256 upperBoundTimestamp) = UserOperationLib.unpackUints(packedTimestamps);

        bytes32 currentItemHash =
            MEEUserOpHashLib.getMeeUserOpEip712Hash(userOpHash, lowerBoundTimestamp, upperBoundTimestamp);

        bytes32 superTxEip712Hash =
            HashLib.compareAndGetFinalHash(outerTypeHash, currentItemHash, itemIndex, itemHashes);
        if (superTxEip712Hash == bytes32(0)) {
            revert UnexpectedSuperTxEntry(currentItemHash, itemHashes[itemIndex]);
        }

        return (abi.encode(lowerBoundTimestamp, upperBoundTimestamp, superTxEip712Hash, signature));
    }

    /**
     * @dev
     * @param dataHash The hash of the data object
     * @param sigData The signature data for the data object
     * @return bool isErc7739Required True if the erc-7739 is required for the signature validation,
     *         in the StxValidator contract, false otherwise
     * @return bytes32 The hash, that was signed
     * @return bytes The clean signature
     */
    function processStxDataObject(
        address, // account is not used in the Permit fusion mode
        bytes32 dataHash,
        bytes calldata sigData
    )
        external
        view
        returns (bool, bytes32, bytes memory)
    {
        (bytes32 outerTypeHash, uint256 itemIndex, bytes32[] calldata itemHashes, bytes calldata signature) =
            HashLib.parsePackedSigDataHead(sigData);

        bytes32 superTxEip712Hash = HashLib.compareAndGetFinalHash(outerTypeHash, dataHash, itemIndex, itemHashes);
        if (superTxEip712Hash == bytes32(0)) {
            revert UnexpectedSuperTxEntry(dataHash, itemHashes[itemIndex]);
        }

        // still return first value (isErc7739Required) as true,
        // because the domain separator doesn't include verifying
        // contract address in our case (see HashLib.hashTypedDataForAccount)
        return (true, superTxEip712Hash, signature);
    }
}
