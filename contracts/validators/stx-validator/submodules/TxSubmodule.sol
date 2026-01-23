// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { MerkleProofLib } from "solady/utils/MerkleProofLib.sol";
import { EcdsaHelperLib } from "../../../lib/util/EcdsaHelperLib.sol";
import { MEEUserOpHashLib } from "../../../lib/stx-validator/MEEUserOpHashLib.sol";
import { IStatelessValidator } from "contracts/interfaces/standard/erc-7780/IStatelessValidator.sol";
import { IStxModeVerifier } from "contracts/interfaces/stx-validator/IStxModeVerifier.sol";
import { RLPReader as RLPDecoder } from "rlp-reader/RLPReader.sol";
import { RLPEncoder } from "../../../lib/stx-validator/rlp/RLPEncoder.sol";
import { BytesLib } from "byteslib/BytesLib.sol";
import { EfficientHashLib } from "solady/utils/EfficientHashLib.sol";

/**
 * @dev Submodule to validate the signature for MEE on-chain Txn mode
 *      This is the mode where superTx hash is appended to a regular txn (legacy or 1559) calldata
 *      Type 1 (EIP-2930) transactions are not supported.
 *      The whole txn is signed along with the superTx hash
 *      Txn is executed prior to a superTx, so it can pass some funds from the EOA to the smart account
 *      For more details see Fusion docs:
 *      - https://ethresear.ch/t/fusion-module-7702-alternative-with-no-protocol-changes/20949
 *      - https://docs.biconomy.io/explained/eoa#fusion-module
 *      @dev Some smart contracts may not be able to consume the txn with bytes32 appended to the calldata.
 *           However this is very small subset. One of the cases when it can happen is when the smart contract
 *           is has separate receive() and fallback() functions. Then if a txn is a value transfer, it will
 *           be expected to be consumed by the receive() function. However, if there's bytes32 appended to the calldata,
 *           it will be consumed by the fallback() function which may not be expected. In this case, the provided
 *           contracts/forwarder/Forwarder.sol can be used to 'clear' the bytes32 from the calldata.
 *      @dev In theory, the last 32 bytes of calldata from any transaction by the EOA can be interpreted as
 *           a superTx hash. Even if it was not assumed. This introduces the potential risk of phishing attacks
 *           where the user may unknowingly sign a transaction where the last 32 bytes of the calldata end up
 *           being a superTx hash. However, it is not easy to craft a txn that makes sense for a user and allows
 *           arbitrary bytes32 as last 32 bytes. Thus, wallets and users should be aware of this potential risk
 *           and should not sign txns where the last 32 bytes of the calldata do not belong to the function arguments
 *           and are just appended at the end.
 *
 */

struct TxData {
    uint8 txType;
    uint8 v;
    bytes32 r;
    bytes32 s;
    bytes32 utxHash;
    bytes32 superTxHash;
    bytes32[] proof;
    uint48 lowerBoundTimestamp;
    uint48 upperBoundTimestamp;
}

// To save a bit of gas, not pass timestamps where not needed
struct TxDataShort {
    uint8 txType;
    uint8 v;
    bytes32 r;
    bytes32 s;
    bytes32 utxHash;
    bytes32 superTxHash;
    bytes32[] proof;
}

struct TxParams {
    uint256 v;
    bytes32 r;
    bytes32 s;
    bytes callData;
}

error TxDecoder_CallDataLengthTooShort();
error TxValidatorLib_UnsupportedTxType();

uint8 constant LEGACY_TX_TYPE = 0x00;
uint8 constant EIP1559_TX_TYPE = 0x02;

uint8 constant EIP_155_MIN_V_VALUE = 37;
uint8 constant HASH_BYTE_SIZE = 32;

uint8 constant TIMESTAMP_BYTE_SIZE = 6;
uint8 constant PROOF_ITEM_BYTE_SIZE = 32;
uint8 constant ITX_HASH_BYTE_SIZE = 32;

contract TxSubmodule is IStxModeVerifier {
    using RLPDecoder for RLPDecoder.RLPItem;
    using RLPDecoder for bytes;
    using RLPEncoder for uint256;
    using BytesLib for bytes;

    using EcdsaHelperLib for bytes32;

    /**
     * @dev Processes the userOp data for the Stx on-chain Txn fusion mode
     *      This function will decode the signature data and verify
     *      the Merkle proof for the superTx hash.
     *      It will return the data required for the further signature validation via erc-7780.
     * @param userOpHash The hash of the userOp
     * @param sigData The signature data for the userOp
     * @return bytes The encoded data : timestamps, meeHash, and a clean signature
     */
    function processStxUserOpData(bytes32 userOpHash, bytes calldata sigData) external returns (bytes memory) {
        // AA-4337 backwards compatibility flow
        if (sigData.length == 65) {
            // if sigData.length == 65, this is a simple EOA signature for the vanilla ERC-4337 flow
            // in this case, we just have to verify the og userOp.signature against the userOpHash
            return (abi.encode(uint48(0), uint48(0), userOpHash, sigData));
        }

        TxData memory decodedTx = decodeTx(sigData);

        bytes32 meeUserOpHash =
            MEEUserOpHashLib.getMEEUserOpHash(userOpHash, decodedTx.lowerBoundTimestamp, decodedTx.upperBoundTimestamp);

        if (!MerkleProofLib.verify(decodedTx.proof, decodedTx.superTxHash, meeUserOpHash)) {
            revert MerkleVerificationFailed();
        }

        bytes memory txnSignature = abi.encodePacked(decodedTx.r, decodedTx.s, decodedTx.v);

        return
            (abi.encode(decodedTx.lowerBoundTimestamp, decodedTx.upperBoundTimestamp, decodedTx.utxHash, txnSignature));
    }

    /**
     * @dev Processes the data object for the Stx on-chain Txn fusion mode
     *      This function will decode the signature data and verify
     *      the Merkle proof for the superTx hash.
     *      It will return the data required for the further erc-7780 signature validation.
     *      Since Eth native txns are not erc-712 objects, using erc-7739 makes no sense here
     * @param account The account that requested data object processing
     * @param dataHash The hash of the data object
     * @param sigData The signature data for the data object
     * @return bool isErc7739Required True if the erc-7739 is required for the signature validation,
     *         in the StxValidator contract, false otherwise
     * @return bytes32 The hash, that was signed
     * @return bytes The clean signature
     */
    function processStxDataObject(
        address account,
        bytes32 dataHash,
        bytes calldata sigData
    )
        external
        view
        returns (bool, bytes32, bytes memory)
    {
        TxDataShort memory decodedTx = decodeTxShort(sigData);

        // since Eth native txns are not erc-712 objects, using erc-7739 makes no sense here
        // To protect from the `two accounts, same owner` attack vector, we just rehash the
        // entry hash with the account address. Since user signs the txn anyways, which just has
        // the superTx root hash appended to the calldata, the entry hash can also be blind,
        // thus we just rehash it with the account address.

        // if the `account` passed is zero address, means, the function is called
        // via StxValidator.validateSignatureWithData function, which
        // doesn't assume any additional security measures, as ERC-7780 stateless validators
        // always act as `stupid` signature verifiers. So all the security checks
        // should be pre-taken by the multiplexer that called StxValidator.validateSignatureWithData function.
        // Thus in this case, no rehashing is needed.
        bytes32 entryHash = account == address(0) ? dataHash : keccak256(abi.encodePacked(dataHash, account));

        if (!MerkleProofLib.verify(decodedTx.proof, decodedTx.superTxHash, entryHash)) {
            revert MerkleVerificationFailed();
        }

        // return the data required for the further signature validation
        return (
            false, // no erc-7739 required
            decodedTx.utxHash, // signed hash
            abi.encodePacked(decodedTx.r, decodedTx.s, decodedTx.v) // signature
        );
    }

    // ========================================================

    function decodeTx(bytes calldata self) internal pure returns (TxData memory) {
        uint8 txType = uint8(self[0]); //first byte is tx type
        uint48 lowerBoundTimestamp =
            uint48(bytes6((self[self.length - 2 * TIMESTAMP_BYTE_SIZE:self.length - TIMESTAMP_BYTE_SIZE])));
        uint48 upperBoundTimestamp = uint48(bytes6(self[self.length - TIMESTAMP_BYTE_SIZE:]));
        uint8 proofItemsCount = uint8(self[self.length - 2 * TIMESTAMP_BYTE_SIZE - 1]);
        uint256 appendedDataLen = (uint256(proofItemsCount) * PROOF_ITEM_BYTE_SIZE + 1) + 2 * TIMESTAMP_BYTE_SIZE;
        bytes calldata rlpEncodedTx = self[1:self.length - appendedDataLen];
        RLPDecoder.RLPItem memory parsedRlpEncodedTx = rlpEncodedTx.toRlpItem();
        RLPDecoder.RLPItem[] memory parsedRlpEncodedTxItems = parsedRlpEncodedTx.toList();
        TxParams memory params = extractParams(txType, parsedRlpEncodedTxItems);

        return TxData({
            txType: txType,
            v: _adjustV(params.v),
            r: params.r,
            s: params.s,
            utxHash: calculateUnsignedTxHash(
                txType, rlpEncodedTx, parsedRlpEncodedTx.payloadLen(), params.v, params.r, params.s
            ),
            superTxHash: extractAppendedHash(params.callData),
            proof: extractProof(self, proofItemsCount),
            lowerBoundTimestamp: lowerBoundTimestamp,
            upperBoundTimestamp: upperBoundTimestamp
        });
    }

    function decodeTxShort(bytes calldata self) internal pure returns (TxDataShort memory) {
        uint8 txType = uint8(self[0]); //first byte is tx type
        uint8 proofItemsCount = uint8(self[self.length - 1]);
        uint256 appendedDataLen = (uint256(proofItemsCount) * PROOF_ITEM_BYTE_SIZE + 1);
        bytes calldata rlpEncodedTx = self[1:self.length - appendedDataLen];
        RLPDecoder.RLPItem memory parsedRlpEncodedTx = rlpEncodedTx.toRlpItem();
        RLPDecoder.RLPItem[] memory parsedRlpEncodedTxItems = parsedRlpEncodedTx.toList();
        TxParams memory params = extractParams(txType, parsedRlpEncodedTxItems);

        return TxDataShort({
            txType: txType,
            v: _adjustV(params.v),
            r: params.r,
            s: params.s,
            utxHash: calculateUnsignedTxHash(
                txType, rlpEncodedTx, parsedRlpEncodedTx.payloadLen(), params.v, params.r, params.s
            ),
            superTxHash: extractAppendedHash(params.callData),
            proof: extractProofShort(self, proofItemsCount)
        });
    }

    function extractParams(
        uint8 txType,
        RLPDecoder.RLPItem[] memory items
    )
        private
        pure
        returns (TxParams memory params)
    {
        uint8 dataPos;
        uint8 vPos;
        uint8 rPos;
        uint8 sPos;

        if (txType == LEGACY_TX_TYPE) {
            dataPos = 5;
            vPos = 6;
            rPos = 7;
            sPos = 8;
        } else if (txType == EIP1559_TX_TYPE) {
            dataPos = 7;
            vPos = 9;
            rPos = 10;
            sPos = 11;
        } else {
            revert TxValidatorLib_UnsupportedTxType();
        }

        return TxParams(
            items[vPos].toUint(), bytes32(items[rPos].toUint()), bytes32(items[sPos].toUint()), items[dataPos].toBytes()
        );
    }

    function extractAppendedHash(bytes memory callData) private pure returns (bytes32 iTxHash) {
        if (callData.length < ITX_HASH_BYTE_SIZE) revert TxDecoder_CallDataLengthTooShort();
        iTxHash = bytes32(callData.slice(callData.length - ITX_HASH_BYTE_SIZE, ITX_HASH_BYTE_SIZE));
    }

    function extractProof(bytes calldata signedTx, uint8 proofItemsCount)
        private
        pure
        returns (bytes32[] memory proof)
    {
        proof = new bytes32[](proofItemsCount);
        uint256 pos = signedTx.length - 2 * TIMESTAMP_BYTE_SIZE - 1;
        for (proofItemsCount; proofItemsCount > 0; proofItemsCount--) {
            proof[proofItemsCount - 1] = bytes32(signedTx[pos - PROOF_ITEM_BYTE_SIZE:pos]);
            pos = pos - PROOF_ITEM_BYTE_SIZE;
        }
    }

    function extractProofShort(
        bytes calldata signedTx,
        uint8 proofItemsCount
    )
        private
        pure
        returns (bytes32[] memory proof)
    {
        proof = new bytes32[](proofItemsCount);
        uint256 pos = signedTx.length - 1;
        for (proofItemsCount; proofItemsCount > 0; proofItemsCount--) {
            proof[proofItemsCount - 1] = bytes32(signedTx[pos - PROOF_ITEM_BYTE_SIZE:pos]);
            pos = pos - PROOF_ITEM_BYTE_SIZE;
        }
    }

    function calculateUnsignedTxHash(
        uint8 txType,
        bytes memory rlpEncodedTx,
        uint256 rlpEncodedTxPayloadLen,
        uint256 v,
        bytes32 r,
        bytes32 s
    )
        private
        pure
        returns (bytes32 hash)
    {
        uint256 totalSignatureSize =
            uint256(r).encodeUint().length + uint256(s).encodeUint().length + v.encodeUint().length;
        uint256 totalPrefixSize = rlpEncodedTx.length - rlpEncodedTxPayloadLen;
        bytes memory rlpEncodedTxNoSigAndPrefix =
            rlpEncodedTx.slice(totalPrefixSize, rlpEncodedTx.length - totalSignatureSize - totalPrefixSize);
        if (txType == EIP1559_TX_TYPE) {
            return
                EfficientHashLib.hash(abi.encodePacked(txType, prependRlpContentSize(rlpEncodedTxNoSigAndPrefix, "")));
        } else if (txType == LEGACY_TX_TYPE) {
            if (v >= EIP_155_MIN_V_VALUE) {
                return EfficientHashLib.hash(
                    prependRlpContentSize(
                        rlpEncodedTxNoSigAndPrefix,
                        abi.encodePacked(
                            uint256(_extractChainIdFromV(v)).encodeUint(),
                            uint256(0).encodeUint(),
                            uint256(0).encodeUint()
                        )
                    )
                );
            } else {
                return EfficientHashLib.hash(prependRlpContentSize(rlpEncodedTxNoSigAndPrefix, ""));
            }
        } else {
            revert TxValidatorLib_UnsupportedTxType();
        }
    }

    function prependRlpContentSize(bytes memory content, bytes memory extraData) public pure returns (bytes memory) {
        bytes memory combinedContent = abi.encodePacked(content, extraData);
        return abi.encodePacked(combinedContent.length.encodeLength(RLPDecoder.LIST_SHORT_START), combinedContent);
    }

    function _adjustV(uint256 v) internal pure returns (uint8) {
        if (v >= EIP_155_MIN_V_VALUE) {
            return uint8((v - 2 * _extractChainIdFromV(v) - 35) + 27);
        } else if (v <= 1) {
            /// forge-lint:disable-next-line(unsafe-typecast)
            return uint8(v + 27);
        } else {
            /// forge-lint:disable-next-line(unsafe-typecast)
            return uint8(v);
        }
    }

    function _extractChainIdFromV(uint256 v) internal pure returns (uint256 chainId) {
        chainId = (v - 35) / 2;
    }
}
