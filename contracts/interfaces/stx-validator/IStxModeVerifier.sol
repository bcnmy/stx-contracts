// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.27;

/**
 * @title IStxModeVerifier
 * @notice Interface for the StxModeVerifier module
 * @dev This module is responsible for validating the userOp with regards of a given Stx
 */
interface IStxModeVerifier {
    /**
     * @dev This method is responsible for validating the userOp with regards of a given Stx
     * It should verify the given UserOp is the part of the given Stx (via merkl tree or a simple list)
     * and it should properly parse the signatureData according to the Stx Mode it implements
     *
     * @return bool sigValidationRequired
     *      indicates whether the furthersignature validation is required
     * @return bytes return data: packed data for the further signature validation
     * via erc-7780. It should include timestamps, signed hash, and a clean signature
     */
    function validateStxUserOp(bytes32 userOpHash, bytes calldata signatureData) external returns (bool, bytes memory);
}
