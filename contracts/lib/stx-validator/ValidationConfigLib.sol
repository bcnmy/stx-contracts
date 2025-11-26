// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import { ValidationConfig } from "contracts/validators/stx-validator/StxValidator.sol";

library ValidationConfigLib {
    function validateSignatureWithConfig(
        mapping(bytes32 configId => mapping(address smartAccount => ValidationConfig config)) storage configs,
        address smartAccount,
        bytes32 configId,
        bytes32 userOpHash,
        bytes memory signature
    )
        internal
        view
        returns (bool)
    {
        ValidationConfig memory config = configs[configId][smartAccount];
        require(config.validatorAddress != address(0), NoConfigsEnabledForAccount(smartAccount));

        if (config.validationType == ValidationType.ERC1271) {
            // in this case, the validator address is an account address
            bytes4 erc1271Return = IERC1271(config.validatorAddress).isValidSignature(userOpHash, signature);
            return erc1271Return == ERC1271_SUCCESS;
        } else if (config.validationType == ValidationType.ERC7780) {
            return IStatelessValidator(config.validatorAddress)
                .validateSignatureWithData(userOpHash, signature, config.validationData.load());
        } else {
            revert ValidationConfigLib_unsupportedValidationType();
        }
    }
}
