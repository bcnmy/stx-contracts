// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.27;

interface IStatelessValidator {
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

    /**
     * Returns boolean value if module is a certain type
     *
     * @param moduleTypeId the module type ID according the ERC-7579 spec
     *
     * MUST return true if the module is of the given type and false otherwise
     */
    function isModuleType(uint256 moduleTypeId) external view returns (bool);
}
