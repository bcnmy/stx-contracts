// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { EcdsaHelperLib } from "../../../lib/util/EcdsaHelperLib.sol";
import {
    IStatelessValidator,
    InvalidErc7780DataLength
} from "../../../interfaces/standard/erc-7780/IStatelessValidator.sol";
import { MODULE_TYPE_STATELESS_VALIDATOR } from "../../../types/Constants.sol";

/**
 * @dev A very simple ERC-7780 stateless validator that expects 65-bytes
 *      EOA (secp256k1) signature over the userOpHash.
 */

contract EOAStatelessValidator is IStatelessValidator {
    error InvalidSignature();
    error ZeroAddressOwner();

    using EcdsaHelperLib for bytes32;

    /**
     * @dev Parses the expected signer from data and
     *      validates a signature over the userOpHash.
     * @param hash The userOpHash to validate the signature over.
     * @param signature The signature to validate. Should be a simple 65-bytes EOA signature.
     * @param data The data to validate the signature against.
     * @return True if the signature is valid, false otherwise.
     */
    function validateSignatureWithData(
        bytes32 hash,
        bytes calldata signature,
        bytes calldata data
    )
        external
        view
        returns (bool)
    {
        require(data.length >= 20, InvalidErc7780DataLength());
        address expectedSigner = address(bytes20(data[:20]));
        require(expectedSigner != address(0), ZeroAddressOwner());

        // sig malleability prevention
        bytes32 s;
        assembly {
            // same as `s := mload(add(signature, 0x40))` but for calldata
            s := calldataload(add(signature.offset, 0x20))
        }
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            revert InvalidSignature();
        }

        return EcdsaHelperLib.isValidSignature(expectedSigner, hash, signature);
    }

    function isModuleType(uint256 typeId) external view returns (bool) {
        return typeId == MODULE_TYPE_STATELESS_VALIDATOR;
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
