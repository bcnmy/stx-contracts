// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import { ValidationConfig } from "contracts/validators/stx-validator/StxValidator.sol";
import { SIG_VALIDATION_FAILED, _packValidationData } from "account-abstraction/core/Helpers.sol";
import { IStatelessValidator } from "contracts/interfaces/standard/erc-7780/IStatelessValidator.sol";
import { IStxModeVerifier } from "contracts/interfaces/stx-validator/IStxModeVerifier.sol";
import { FlatBytesLib } from "flatbytes/BytesLib.sol";

error StxModeVerifierAddressCannotBeZeroAddress();

library ValidationConfigLib {
    using FlatBytesLib for FlatBytesLib.Bytes;

    function validateStxSignature(
        mapping(bytes32 configId => mapping(address smartAccount => ValidationConfig config)) storage configs,
        address smartAccount,
        bytes32 configId,
        bytes32 userOpHash,
        bytes memory signature
    )
        internal
        returns (uint256)
    {
        ValidationConfig storage config = configs[configId][smartAccount];
        address stxModeVerifierAddress = config.stxModeVerifierAddress;
        address statelessValidatorAddress = config.statelessValidatorAddress;
        require(stxModeVerifierAddress != address(0), StxModeVerifierAddressCannotBeZeroAddress());
        // sometimes we use same submodule for both stx mode verifier and stateless validator
        // in this case we can pass address(0) as statelessValidatorAddress
        // and save some calldata gas this way
        if (statelessValidatorAddress == address(0)) {
            statelessValidatorAddress = stxModeVerifierAddress;
        }

        // I) validateStxUserOp is parsing the userOp.signature,
        // makes sure the given userOp is the part of the superTx
        // return timestamps and signed hash + clean signature for the further
        // sig verification via erc-7780
        // if external call reverts => this method will revert as well => will make handleOps revert with AA23
        (bool sigValidationRequired, bytes memory ret) =
            IStxModeVerifier(stxModeVerifierAddress).validateStxUserOp(userOpHash, signature);

        // decode ret
        // backward compatibility flow: if IStxValidator.validateStxUserOp detects the non-mee flow, it
        // will just repack og userOpHash and userOp.signature and (0,0) as timestamps into ret
        // so at the next step the sig validation will happen with the original userOpHash and userOp.signature
        // as in the vanilla erc-4337 flow
        (uint48 lowerBoundTimestamp, uint48 upperBoundTimestamp, bytes32 signedHash, bytes memory cleanSignature) =
            abi.decode(ret, (uint48, uint48, bytes32, bytes));

        // II) Sig validation via erc-7780
        bool isValidSig = sigValidationRequired
            ? IStatelessValidator(statelessValidatorAddress)
                .validateSignatureWithData(signedHash, cleanSignature, config.validationData.load())
            : true;

        // return validation data as per erc-4337
        // first value is sigValidationFailed which is opposite to isValidSig returned by the validateSignatureWithData
        return _packValidationData(!isValidSig, upperBoundTimestamp, lowerBoundTimestamp);
    }
}
