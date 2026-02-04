// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { MerkleProofLib } from "solady/utils/MerkleProofLib.sol";
import { EcdsaHelperLib } from "../../../lib/util/EcdsaHelperLib.sol";
import { MEEUserOpHashLib } from "../../../lib/stx-validator/MEEUserOpHashLib.sol";
import { ERC20 } from "solady/tokens/ERC20.sol";
import { IStxModeVerifier } from "contracts/interfaces/stx-validator/IStxModeVerifier.sol";
import { EfficientHashLib } from "solady/utils/EfficientHashLib.sol";
import { IERC7739Multiplexer } from "contracts/interfaces/stx-validator/IERC7739Multiplexer.sol";
import { HashLib } from "contracts/lib/stx-validator/HashLib.sol";

/**
 * @dev Fallback submodule for the no stx mode.
 *      So Stx Validator can act as a default validator for Non-stx
 *      flows. Such as pure 4337, pure 1271 (via both 7739 and vanilla 1271).
 */

contract NoStxModeVerifier is IStxModeVerifier {
    /**
     * @dev Just return the original userOpHash and signature
     */
    function processStxUserOpData(address, bytes32 userOpHash, bytes calldata sigData) external returns (bytes memory) {
        return abi.encode(uint48(0), uint48(0), userOpHash, sigData); // empty timestamps => valid forever
    }

    /**
     * @dev Use ERC-7739 for no stx mode by default.
     *      This function will return the hash and signature for the ERC-7739 validation.
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
        // Use ERC-7739 for no stx mode by default
        (bytes32 meeHash, bytes memory cleanSignature) =
            IERC7739Multiplexer(msg.sender).getErc7739HashAndSignature(account, sender, dataHash, sigData);
        return (meeHash, cleanSignature);
    }

    /**
     * @dev Return the original dataHash and signature
     *      No 7739 is needed
     */
    function processStxDataObjectFor7780Flow(
        address, /* account is not used in the No Stx mode */
        bytes32 dataHash,
        bytes calldata sigData
    )
        external
        view
        returns (bytes32, bytes memory)
    {
        return (dataHash, sigData);
    }
}
