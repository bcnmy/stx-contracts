// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { MerkleProofLib } from "solady/utils/MerkleProofLib.sol";
import { EcdsaHelperLib } from "../../../lib/util/EcdsaHelperLib.sol";
import { MeeUserOpHashLib } from "../../../lib/stx-validator/MeeUserOpHashLib.sol";
import { IStxModeVerifier } from "contracts/interfaces/stx-validator/IStxModeVerifier.sol";
import { EfficientHashLib } from "solady/utils/EfficientHashLib.sol";
import { SIG_VALIDATION_FAILED, _packValidationData } from "account-abstraction/core/Helpers.sol";
import { UserOperationLib } from "account-abstraction/core/UserOperationLib.sol";
// solhint-disable-next-line no-unused-import
import { HashLib, STATIC_HEAD_LENGTH } from "../../../lib/stx-validator/HashLib.sol";
import { IERC7739Multiplexer } from "contracts/interfaces/stx-validator/IERC7739Multiplexer.sol";

/**
 * @dev Submodule to validate the signature for Simple Stx mode
 *      In this mode, Fusion is not involved and just the eip712 hash
 *      of the superTx(...) data struct is signed
 */

contract SimpleModeSubmodule is IStxModeVerifier {
    /**
     * @dev
     *
     * @param userOpHash The hash of the userOp
     * @param sigData The signature data for the userOp
     * @return bytes The encoded data : timestamps, meeHash, and a clean signature
     */
    function processStxUserOpData(
        address account,
        bytes32 userOpHash,
        bytes calldata sigData
    )
        external
        returns (bytes memory)
    {
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
            MeeUserOpHashLib.getMeeUserOpEip712Hash(userOpHash, lowerBoundTimestamp, upperBoundTimestamp);

        bytes32 superTxEip712Hash =
            HashLib.compareAndGetFinalHashForAccount(account, outerTypeHash, currentItemHash, itemIndex, itemHashes);

        return (abi.encode(lowerBoundTimestamp, upperBoundTimestamp, superTxEip712Hash, signature));
    }

    /**
     * @dev
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
        (bytes32 outerTypeHash, uint256 itemIndex, bytes32[] calldata itemHashes, bytes calldata signature) =
            HashLib.parsePackedSigDataHead(sigData);

        // expect stx entries which are not userOps are not safe and apply 7739 to them
        // because domain separator doesn't include verifying
        // contract address in our case (see HashLib.hashTypedDataForAccount)
        // to allow potenitally different address on different chains
        // so to protect agains `two accounts, same owner` attack vector
        // we apply 7739 to the each potentially unsafe entry hash
        // so off-chain, every data struct hash should be hashes as per erc-7739
        // and only then included into the SuperTx
        // so the signature, provided to isValidSignature should include erc-7739 required payload
        // if the SuperTx struct included mixed data structs and userOps,
        // signature for userOps should not include erc-7739 required payload
        // because userOps are already safe and don't need erc-7739 thus they are not
        // processed via erc-7739 (see `processStxUserOpData` method above)
        //
        // integration note: since erc-7739 TypedDataSign includes the chainid,
        // make sure to use the correct 712 domain details when building the hash
        // user is going to sign on the off-chain side.
        // so if a given data struct is intended for the chain A, use 712 domain details
        // of the account on chain A for erc-7739 hash building.
        (bytes32 expectedIncludedErc7739Hash, bytes memory erc7739Signature) =
            IERC7739Multiplexer(msg.sender).getErc7739HashAndSignature(account, sender, dataHash, signature);

        bytes32 superTxEip712Hash = HashLib.compareAndGetFinalHashForAccount(
            account, outerTypeHash, expectedIncludedErc7739Hash, itemIndex, itemHashes
        );

        return (superTxEip712Hash, erc7739Signature);
    }

    /**
     * @dev This function is used to process the data object for the 7780 flow
     *      In this erc-7739 is not required
     * @param dataHash The hash of the data object
     * @param sigData The signature data for the data object
     * @return bytes32 The hash of the data object
     * @return bytes The signature data for the data object
     */
    function processStxDataObjectFor7780Flow(
        address account,
        bytes32 dataHash,
        bytes calldata sigData
    )
        external
        view
        returns (bytes32, bytes memory)
    {
        (bytes32 outerTypeHash, uint256 itemIndex, bytes32[] calldata itemHashes, bytes calldata signature) =
            HashLib.parsePackedSigDataHead(sigData);

        bytes32 superTxEip712Hash =
            HashLib.compareAndGetFinalHashForAccount(account, outerTypeHash, dataHash, itemIndex, itemHashes);

        return (superTxEip712Hash, signature);
    }
}
