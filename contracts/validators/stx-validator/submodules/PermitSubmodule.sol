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
 * @dev Submodule to validate the UserOp/Stx for the MEE ERC-2612 Permit mode
 *      This is the mode where superTx hash is pasted into deadline field of the ERC-2612 Permit
 *      So the whole permit is signed along with the superTx hash
 *      For more details see Fusion docs:
 *      - https://ethresear.ch/t/fusion-module-7702-alternative-with-no-protocol-changes/20949
 *      - https://docs.biconomy.io/explained/eoa#fusion-module
 *
 *      @dev Important: since ERC20 permit token knows nothing about the MEE, it will treat the superTx hash as a
 * deadline:
 *      -  if (very unlikely) the superTx hash being converted to uint256 is a timestamp in the past, the permit will
 * fail
 *      -  the deadline with most superTx hashes will be very far in the future
 *
 *      @dev Since at this point bytes32 superTx hash is a blind hash, users and wallets should pay attention if
 *           the permit2 deadline field does not make sense as the timestamp. In this case, it can be a sign of a
 *           phishing attempt (injecting super txn hash as the deadline) and the user should not sign the permit.
 *           This is going to be mitigated in the future by making superTx hash a EIP-712 hash.
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
    // TODO: REPLACE THIS WITH JUST THE BYTES SIGNATURE FIELD
    // - in processStxUserOpData mode, it will be just encodePacked(r, s, v) coz no 7739 is applicable, so to call
    // erc20.permit() we just cust the signature into v,r,s
    // - in processStxUserOpData (1271/7739) it may be decoded as per 7739.but we do not need to decode it here in this
    // module anyways we just return it back to the StxValidator to be used with 7739 functions that know how to handle
    // it.
    // uint8 v;
    // bytes32 r;
    // bytes32 s;
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
    /*
    uint8 v;
    bytes32 r;
    bytes32 s;
    */
    bytes signature;
    bytes32[] proof;
}

error InvalidDataLength();
error MerkleVerificationFailed();

contract PermitSubmodule is IStatelessValidator, IStxModeVerifier {
    error PermitFailed();

    using EcdsaHelperLib for bytes32;

    function processStxUserOpData(bytes32 userOpHash, bytes calldata sigData) external returns (bool, bytes memory) {
        // AA-4337 backwards compatibility flow
        if (sigData.length == 65) {
            // if sigData.length == 65, this is a simple EOA signature for the vanilla ERC-4337 flow
            // in this case, we just have to verify the og userOp.signature against the userOpHash
            return (true, abi.encode(uint48(0), uint48(0), userOpHash, sigData));
        }

        // otherwise, we consider the sigData = userOp.signature is properly encoded
        // to provide all the data required for the Permit fusion mode validation
        DecodedErc20PermitSig calldata decodedSig = _decodeFullPermitSig(sigData);

        // Verify Merkle proof for the superTx hash
        bytes32 meeUserOpHash = MEEUserOpHashLib.getMEEUserOpHash(
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

            // if this is a permit tx, we do not need to verify the signature later,
            // because this is already done within the ERC20.permit function

            // TODO: implement a test case for this, that shows that if isPermitTx is true, the wrong signature will
            // revert even w/o the separate signature validation with erc-7780 step
            return (
                false, // means no further signature validation is required
                abi.encode(decodedSig.lowerBoundTimestamp, decodedSig.upperBoundTimestamp, bytes32(0), sigData)
            );
        }

        return (
            true,
            abi.encode(
                decodedSig.lowerBoundTimestamp,
                decodedSig.upperBoundTimestamp,
                _getSignedDataHash(decodedSig),
                decodedSig.signature
            )
        );
    }

    function processStxDataObject(
        bytes32 dataHash,
        bytes calldata sigData
    )
        external
        view
        returns (bool, bytes32, bytes memory)
    {
        if (sigData.length == 65) {
            // !!!!!!!!!!!!!!!!!!!!!
            // THIS CHECK IS NOT CORRECT BECAUSE IN  CASE OF 7739,
            // THE SIGN WILL BE 65bytes + appended 7739 specific data
            // !!!!!!!!!
            // TODO: fix this check

            // if sigData.length == 65, this is a simple EOA signature over the data object,
            // not a stx flow. ERC-7739 is required in this case.
            return (true, dataHash, sigData);
        }

        DecodedErc20PermitSigShort calldata decodedSig = _decodeShortPermitSig(sigData);

        if (!MerkleProofLib.verify(decodedSig.proof, decodedSig.superTxHash, dataHash)) {
            revert MerkleVerificationFailed();
        }

        // still return first value (isErc7739Required) as true,
        // because technically smart accoiunt address is not always present in the data object
        // (in most cases Permit.spender is the smart account address, but it can be any other address as well)
        // so we have to use ERC-7739 to keep the transparent EIP-712 data struct to be signed by the user
        // and still be protected from the `two accounts, same owner` attack vector.
        return (true, _getSignedDataHash(decodedSig), decodedSig.signature);
    }

    // ERC2612.permit() function expects a simple EOA signature for most implementations
    // So this method can be used to validate the signature over the Permit data structure
    // In case your ERC-2612.permit() function features other potential types of signature verification,
    // for example, ERC-1271, please use another ERC-7780 validator as a stateless validator in the StxValidator
    // config instead of this one.
    function validateSignatureWithData(
        bytes32 hash,
        bytes calldata sig,
        bytes calldata data
    )
        external
        view
        returns (bool)
    {
        require(data.length >= 20, InvalidDataLength());
        address expectedSigner = address(bytes20(data[:20]));
        return EcdsaHelperLib.isValidSignature(expectedSigner, hash, sig);
    }

    function isModuleType(uint256 typeId) external view returns (bool) {
        return typeId == MODULE_TYPE_STATELESS_VALIDATOR;
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

    // =========== REQUIRED BY ERC-7780/ERC-7579 SPEC ===========

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
