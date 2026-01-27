// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.27;

import { IModule } from "erc7579/interfaces/IERC7579Module.sol";

/**
 * @dev This error is thrown when the data length is invalid for the ERC-7780 signature validation
 */
error InvalidErc7780DataLength();

/**
 * @title IStatelessValidator
 * @notice Interface for the StatelessValidator module
 * @dev This module is responsible for validating the signature of a given data object
 *      using the ERC-7780 standard
 */
interface IStatelessValidator is IModule {
    /**
     * Validates a signature given some data
     *
     * @param hash The data that was signed over
     * @param signature The signature to verify
     * @param data The data to validate the verified signature against
     *
     * MUST validate that the signature is a valid signature of the hash
     * MUST compare the validated signature against the data provided
     * MUST return true if the signature is valid and false otherwise
     */
    function validateSignatureWithData(
        bytes32 hash,
        bytes calldata signature,
        bytes calldata data
    )
        external
        view
        returns (bool);
}
