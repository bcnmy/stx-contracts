// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.27;

/**
 * @title IStxModeVerifier
 * @notice Interface for the StxModeVerifier module
 * @dev This module is responsible for validating the userOp with regards of a given Stx
 */
interface IStxModeVerifier {
    /**
     * @dev This error is thrown when the Merkle proof verification fails
     */
    error MerkleVerificationFailed();

    /**
     * @dev This method is responsible for validating the userOp entry of a given Stx
     * It should verify the given UserOp is the part of the given Stx (via merkl tree or a simple list)
     * and it should properly parse the signatureData according to the Stx Mode it implements
     * @return returnData packed data for the further signature validation
     * via erc-7780. It should include timestamps, signed hash, and a clean signature
     */
    function processStxUserOpData(
        address account,
        bytes32 userOpHash,
        bytes calldata signatureData
    )
        external
        returns (bytes memory returnData);

    /**
     * @dev This method is responsible for validating the data object entry of a given Stx
     * It should verify the given data object is the part of the given Stx (via merkl tree or a simple list)
     * and it should properly parse the signatureData according to the Stx Mode it implements
     * @param account the smart account that requested data object processing
     * @param dataHash the hash of the data object
     * @param signatureData the signature data for the data object
     *
     * Returns data for erc-7780 signature validation
     * @return meeHash the hash of some data object required by a given stx mode: it can be erc2612 permit object,
     * on-chain tx object, merkle tree root, SuperTx() eip712 data struct, etc.
     * @return cleanSignature the clean signature that was used to sign the data
     */
    function processStxDataObject(
        address account,
        address sender,
        bytes32 dataHash,
        bytes calldata signatureData
    )
        external
        view
        returns (bytes32 meeHash, bytes calldata cleanSignature);

    /**
     * @dev This method is responsible for validating the data object for the 7780 flow
     * @param account the smart account that requested data object processing
     * @param dataHash The hash of the data object
     * @param signatureData The signature data for the data object
     * @return meeHash The hash of the data object
     * @return cleanSignature The signature data for the data object
     */
    function processStxDataObjectFor7780Flow(
        address account,
        bytes32 dataHash,
        bytes calldata signatureData
    )
        external
        view
        returns (bytes32 meeHash, bytes calldata cleanSignature);
}

