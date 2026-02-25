// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { MerkleProofLib } from "solady/utils/MerkleProofLib.sol";
import { EcdsaHelperLib } from "../../../lib/util/EcdsaHelperLib.sol";
import { MeeUserOpHashLib } from "../../../lib/stx-validator/MeeUserOpHashLib.sol";
import { ERC20 } from "solady/tokens/ERC20.sol";
import { IStxModeVerifier } from "contracts/interfaces/stx-validator/IStxModeVerifier.sol";
import { EfficientHashLib } from "solady/utils/EfficientHashLib.sol";
import { HashLib } from "contracts/lib/stx-validator/HashLib.sol";

/**
 * @dev Submodule to validate the UserOp/Stx for the MEE ERC-2612 Permit mode
 *      This is the mode where superTx hash is pasted into deadline field of the ERC-2612 Permit
 *      So the whole permit is signed along with the superTx hash
 *      For more details see Fusion docs:
 *      - https://ethresear.ch/t/fusion-module-7702-alternative-with-no-protocol-changes/20949
 *      - https://docs.biconomy.io/explained/eoa#fusion-module
 *
 *      @dev Important: since ERC20 permit token knows nothing about the MEE,
 *      it will treat the superTx hash as a deadline:
 *      -  if (very unlikely) the superTx hash being converted to uint256 is a timestamp
 *         that is in the past, the permit will fail
 *      -  the deadline with most superTx hashes will be very far in the future
 */

//keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
bytes32 constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

struct DecodedErc20PermitSig {
    ERC20 token;
    address owner;
    address spender;
    bytes32 domainSeparator;
    uint256 amount;
    uint256 nonce;
    bool isPermitTx;
    bytes32 superTxHash;
    uint48 lowerBoundTimestamp;
    uint48 upperBoundTimestamp;
    bytes signature;
    bytes32[] proof;
}

struct DecodedErc20PermitSigShort {
    address owner;
    address spender;
    bytes32 domainSeparator;
    uint256 amount;
    uint256 nonce;
    bytes32 superTxHash;
    bytes signature;
    bytes32[] proof;
}

contract PermitSubmodule is IStxModeVerifier {
    error PermitFailed();

    using EcdsaHelperLib for bytes32;

    /**
     * @dev Processes the userOp data for the Permit fusion mode
     *      This function will decode the signature data and verify
     *      the Merkle proof for the superTx hash.
     *      If required, it will perform the Permit approval on the given token.
     * param address account The account that requested userOp processing
     * @param userOpHash The hash of the userOp
     * @param sigData The signature data for the userOp
     * @return bytes The encoded data : timestamps, meeHash, and a clean signature
     */
    function processStxUserOpData(address, bytes32 userOpHash, bytes calldata sigData) external returns (bytes memory) {
        // AA-4337 backwards compatibility flow
        if (sigData.length == 65) {
            // if sigData.length == 65, this is a simple EOA signature for the vanilla ERC-4337 flow
            // in this case, we just have to verify the og userOp.signature against the userOpHash
            return (abi.encode(uint48(0), uint48(0), userOpHash, sigData));
        }

        // otherwise, we consider the sigData = userOp.signature is properly encoded
        // to provide all the data required for the Permit fusion mode validation
        DecodedErc20PermitSig calldata decodedSig = _decodeFullPermitSig(sigData);

        // Verify Merkle proof for the superTx hash
        bytes32 meeUserOpHash = MeeUserOpHashLib.getMeeUserOpHash(
            userOpHash, decodedSig.lowerBoundTimestamp, decodedSig.upperBoundTimestamp
        );
        if (!MerkleProofLib.verify(decodedSig.proof, decodedSig.superTxHash, meeUserOpHash)) {
            revert MerkleVerificationFailed();
        }

        // cut the decodeSig.signature into r,s,v
        bytes32 r = bytes32(decodedSig.signature[0:32]);
        bytes32 s = bytes32(decodedSig.signature[32:64]);
        uint8 v = uint8(decodedSig.signature[64]);

        if (decodedSig.isPermitTx) {
            try decodedSig.token
                .permit(
                    decodedSig.owner, decodedSig.spender, decodedSig.amount, uint256(decodedSig.superTxHash), v, r, s
                ) {
            // all good
            }
            catch {
                // check if by some reason this permit was already successfully used (and not spent yet)
                if (
                    ERC20(address(decodedSig.token)).allowance(decodedSig.owner, decodedSig.spender) < decodedSig.amount
                ) {
                    // if the above expectationis not true, revert
                    revert PermitFailed();
                }
            }
        }

        return (abi.encode(
                decodedSig.lowerBoundTimestamp,
                decodedSig.upperBoundTimestamp,
                _getSignedDataHash(decodedSig),
                decodedSig.signature
            ));
    }

    /**
     * @dev Processes the data object for the Permit fusion mode
     *      This function will decode the signature data and verify
     *      the Merkle proof for the superTx hash.
     *      It will return the data required for the further 1271/7739 signature validation:
     *      proper hash, and a signature.
     * @param dataHash The hash of the data object
     * @param sigData The signature data for the data object
     * @return bytes32 The hash, that was signed
     * @return bytes The clean signature
     */
    function processStxDataObject(
        address account,
        address,
        /* sender */
        bytes32 dataHash,
        bytes calldata sigData
    )
        external
        view
        returns (bytes32, bytes memory)
    {
        DecodedErc20PermitSigShort calldata decodedSig = _decodeShortPermitSig(sigData);

        // To protect from the `two accounts, same owner` attack vector, we just rehash the
        // entry hash with the account address. Since user signs the permit anyways, which just has
        // the superTx root hash in the deadline field of the permit, the entry hash can also be blind,
        // thus we just rehash it with the account address.
        // We also include the chainid to make sure the data struct is not replayable across chains.
        //
        // Attention: importnat integration note: when building Stx entries to build an Stx hash
        // you need to include the chainid of the chain, this data struct is going to be used on!
        // Same applies to the account address in case it varies depending on the chain
        bytes32 entryHash = HashLib.rehashWithAccountAndChainId(dataHash, account, block.chainid);

        if (!MerkleProofLib.verify(decodedSig.proof, decodedSig.superTxHash, entryHash)) {
            revert MerkleVerificationFailed();
        }

        // because of the above rehashing, erc7739 is not needed here
        return (_getSignedDataHash(decodedSig), decodedSig.signature);
    }

    /**
     * @dev This function is used to process the data object for the 7780 flow
     * @param dataHash The hash of the data object
     * @param sigData The signature data for the data object
     * @return bytes32 The hash of the data object
     * @return bytes The signature data for the data object
     */
    function processStxDataObjectFor7780Flow(
        address, /* account is not used in the Permit fusion mode */
        bytes32 dataHash,
        bytes calldata sigData
    )
        external
        view
        returns (bytes32, bytes memory)
    {
        DecodedErc20PermitSigShort calldata decodedSig = _decodeShortPermitSig(sigData);

        if (!MerkleProofLib.verify(decodedSig.proof, decodedSig.superTxHash, dataHash)) {
            revert MerkleVerificationFailed();
        }

        return (_getSignedDataHash(decodedSig), decodedSig.signature);
    }

    // ========================================================

    function _decodeFullPermitSig(bytes calldata parsedSignature)
        private
        pure
        returns (DecodedErc20PermitSig calldata decodedSig)
    {
        assembly {
            decodedSig := add(parsedSignature.offset, 0x20)
        }
    }

    function _decodeShortPermitSig(bytes calldata parsedSignature)
        private
        pure
        returns (DecodedErc20PermitSigShort calldata)
    {
        DecodedErc20PermitSigShort calldata decodedSig;
        assembly {
            decodedSig := add(parsedSignature.offset, 0x20)
        }
        return decodedSig;
    }

    function _getSignedDataHash(DecodedErc20PermitSig memory decodedSig) private pure returns (bytes32) {
        return _hashTypedData(
            _hashPermitDataStruct(
                decodedSig.owner, decodedSig.spender, decodedSig.amount, decodedSig.nonce, decodedSig.superTxHash
            ),
            decodedSig.domainSeparator
        );
    }

    function _getSignedDataHash(DecodedErc20PermitSigShort memory decodedSig) private pure returns (bytes32) {
        return _hashTypedData(
            _hashPermitDataStruct(
                decodedSig.owner, decodedSig.spender, decodedSig.amount, decodedSig.nonce, decodedSig.superTxHash
            ),
            decodedSig.domainSeparator
        );
    }

    function _hashPermitDataStruct(
        address expectedSigner,
        address spender,
        uint256 amount,
        uint256 nonce,
        bytes32 superTxHash
    )
        private
        pure
        returns (bytes32)
    {
        return EfficientHashLib.hash(
            uint256(PERMIT_TYPEHASH),
            uint256(uint160(expectedSigner)),
            uint256(uint160(spender)),
            amount,
            nonce,
            uint256(superTxHash)
        );
    }

    function _hashTypedData(bytes32 structHash, bytes32 domainSeparator) private pure returns (bytes32) {
        return EcdsaHelperLib.toTypedDataHash(domainSeparator, structHash);
    }
}
