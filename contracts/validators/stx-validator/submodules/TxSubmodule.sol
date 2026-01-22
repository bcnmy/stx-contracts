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

/**
 * @dev
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

    function processStxUserOpData(bytes32 userOpHash, bytes calldata sigData) external returns (bytes memory) {
        return (abi.encode(uint48(0), uint48(0), userOpHash, sigData));
    }

    function processStxDataObject(
        bytes32 dataHash,
        bytes calldata sigData
    )
        external
        view
        returns (bool, bytes32, bytes memory)
    {
        return (true, dataHash, sigData);
    }

    // ========================================================
}
