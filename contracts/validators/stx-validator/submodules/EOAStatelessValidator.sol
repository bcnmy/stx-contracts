// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { MerkleProofLib } from "solady/utils/MerkleProofLib.sol";
import { EcdsaHelperLib } from "../../../lib/util/EcdsaHelperLib.sol";
import { MEEUserOpHashLib } from "../../../lib/stx-validator/MEEUserOpHashLib.sol";
import { ERC20 } from "solady/tokens/ERC20.sol";
import { IStatelessValidator } from "contracts/interfaces/standard/erc-7780/IStatelessValidator.sol";
import { IStxModeVerifier } from "contracts/interfaces/stx-validator/IStxModeVerifier.sol";
import { EfficientHashLib } from "solady/utils/EfficientHashLib.sol";
import { MODULE_TYPE_STATELESS_VALIDATOR } from "contracts/types/Constants.sol";

/**
 * @dev A very simple ERC-7780 stateless validator that expects 65-bytes
 *      EOA (secp256k1) signature over the userOpHash.
 */

contract EOAStatelessValidator is IStatelessValidator {
    error InvalidSignature();
    error InvalidDataLength();

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
        require(data.length >= 20, InvalidDataLength());
        address expectedSigner = address(bytes20(data[:20]));

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
