// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { P256Verifier } from "./P256Verifier.sol";
import {
    IStatelessValidator,
    InvalidErc7780DataLength
} from "../../../../interfaces/standard/erc-7780/IStatelessValidator.sol";
import { MODULE_TYPE_STATELESS_VALIDATOR } from "../../../../types/Constants.sol";

/**
 * @dev A very simple ERC-7780 stateless validator for pure secp256r1 signatures
 *      No webauthn payload is verified, just hash, r, s, x, y are expected
 *      Uses RIP-7212 precompile, fallbacks to Daimo's P256 solidity verification library.
 *      Since this contracts preserves the fallback interface (see inherited P256Verifier contract),
 *      it can be used as a fallback for the EIP-7212 precompile.
 *      It will be deployed to all Biconomy MEE supported chains at a deterministic address.
 */

contract P256StatelessValidator is IStatelessValidator, P256Verifier {
    /// @dev The precompiled contract address to use for signature verification in the “secp256r1” elliptic curve.
    ///      See https://github.com/ethereum/RIPs/blob/master/RIPS/rip-7212.md.
    address private constant _VERIFIER = address(0x100);

    uint256 constant P256_N_DIV_2 =
        57_896_044_605_178_124_381_348_723_474_703_786_764_998_477_612_067_880_171_211_129_530_534_256_022_184;

    error InvalidP256SignatureLength();

    /**
     * @dev Parses the expected signer pubkey from data
     *      validates a signature over the hash.
     * @param hash The hash of the data to validate the signature over.
     * @param signature The signature to validate.
     * @param data The data to validate the signature against.
     *        should contain pubkey x and y components.
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
        uint256 r;
        uint256 s;
        uint256 x;
        uint256 y;

        require(signature.length == 64, InvalidP256SignatureLength());
        require(data.length == 64, InvalidErc7780DataLength());

        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 0x20))
            x := calldataload(data.offset)
            y := calldataload(add(data.offset, 0x20))
        }

        if (s > P256_N_DIV_2) {
            return false;
        }

        // Below code is borrowed from Base's webauthn library and slightly modified
        bytes memory args = abi.encode(hash, r, s, x, y);
        // try the RIP-7212 precompile address
        (bool success, bytes memory ret) = _VERIFIER.staticcall(args);
        // staticcall will not revert if address has no code
        // check return length
        // note that even if precompile exists, ret.length is 0 when verification returns false
        // so an invalid signature will be checked twice: once by the precompile and once by FCL.
        // Ideally this signature failure is simulated offchain and no one actually pay this gas.
        bool valid = ret.length > 0;
        if (success && valid) return abi.decode(ret, (uint256)) == 1;

        return ecdsa_verify(hash, r, s, [x, y]);
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
