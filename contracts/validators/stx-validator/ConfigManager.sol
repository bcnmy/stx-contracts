// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

/**
 * @notice Configuration for a validation setup
 * @param stxModeVerifierAddress Address of the IStxModeVerifier submodule for Stx validation
 * @param statelessValidatorAddress Address of the IStatelessValidator for signature verification
 * @param validationData Additional data for validation (e.g., owner public key)
 */
struct ValidationConfig {
    address stxModeVerifierAddress;
    address statelessValidatorAddress;
}

struct SubmoduleAddresses {
    address noStxModeVerifier;
    address simpleModeVerifier;
    address permitModeVerifier;
    address txModeVerifier;
    address safeAccountModeSubmodule;
    address eoaStatelessValidator;
    address p256StatelessValidator;
}

contract ConfigManager {
    error UnrecognizedSignatureType();
    error InvalidSignatureDataLength();

    address public immutable NO_STX_MODE_VERIFIER;
    address public immutable SIMPLE_MODE_VERIFIER;
    address public immutable PERMIT_MODE_VERIFIER;
    address public immutable TX_MODE_VERIFIER;
    address public immutable SAFE_ACCOUNT_MODE_SUBMODULE;
    address public immutable EOA_STATELESS_VALIDATOR;
    address public immutable P256_STATELESS_VALIDATOR;

    mapping(bytes32 configId => mapping(address smartAccount => ValidationConfig config)) public customConfigs;
    EnumerableSet.Bytes32Set internal enabledCustomConfigs;

    mapping(
        IStatelessValidator statelessValidator => mapping(address smartAccount => FlatBytesLib.Bytes validationData)
    ) public ownershipData;

    constructor(SubmoduleAddresses memory submoduleAddresses) {
        NO_STX_MODE_VERIFIER = submoduleAddresses.noStxModeVerifier;
        SIMPLE_MODE_VERIFIER = submoduleAddresses.simpleModeVerifier;
        PERMIT_MODE_VERIFIER = submoduleAddresses.permitModeVerifier;
        TX_MODE_VERIFIER = submoduleAddresses.txModeVerifier;
        SAFE_ACCOUNT_MODE_SUBMODULE = submoduleAddresses.safeAccountModeSubmodule;
        EOA_STATELESS_VALIDATOR = submoduleAddresses.eoaStatelessValidator;
        P256_STATELESS_VALIDATOR = submoduleAddresses.p256StatelessValidator;
    }

    function _getSubmodules(
        address smartAccount,
        bytes sigData
    )
        internal
        view
        returns (address stxModeVerifier, address statelessValidator, bytes calldata parsedSigData)
    {
        if (sigData.length < 4) {
            revert InvalidSignatureDataLength();
        }
        bytes4 sigType = bytes4(sigData[:4]);
        if (sigType == SIG_TYPE_SIMPLE) {
            return (SIMPLE_MODE_VERIFIER, EOA_STATELESS_VALIDATOR);
        } else if (sigType == SIG_TYPE_ON_CHAIN) {
            return (TX_MODE_VERIFIER, EOA_STATELESS_VALIDATOR);
        } else if (sigType == SIG_TYPE_ERC20_PERMIT) {
            return (PERMIT_MODE_VERIFIER, EOA_STATELESS_VALIDATOR);
        } else if (sigType == SIG_TYPE_SAFE_ACCOUNT) {
            return (SAFE_ACCOUNT_MODE_SUBMODULE, SAFE_ACCOUNT_MODE_SUBMODULE);
        } else if (sigType == SIG_TYPE_NO_STX_VANILLA_1271_EOA) {
            return (address(0), EOA_STATELESS_VALIDATOR);
        } else if (sigType == SIG_TYPE_NO_STX_VANILLA_1271_P256) {
            return (address(0), P256_STATELESS_VALIDATOR);
            //...... other modes + validators
        } else if (sigType == SIG_TYPE_CUSTOM) {
            // get submodules from the config storage
            return (stxModeVerifier, statelessValidator);
        } else if (bytes3(sigData[:3]) == SIG_TYPE_MEE_FLOW) {
            //
            revert UnrecognizedSignatureType();
        } else {
            // fallback to no stx mode
            return (NO_STX_MODE_VERIFIER, EOA_STATELESS_VALIDATOR);
        }
    }

    function _getOwnershipData(
        address smartAccount,
        address statelessValidator
    )
        internal
        view
        returns (bytes calldata validationData)
    {
        bytes memory ownershipData = ownershipData[statelessValidator][smartAccount].load();
        // account for 7702 case
        // if stateless validator is eoa, and ownership data is empty, try to return the smart account address as owner
        // in case smart account is an 7702 delegated EOA, it will work
        // since EVM currently supports only secp256k1 for EOA, we expect
        // EOA_STATELESS_VALIDATOR as stateless validator
        if (ownershipData.length == 0 && statelessValidator == EOA_STATELESS_VALIDATOR) {
            ownershipData = abi.encodePacked(smartAccount);
        }
        return ownershipData;
    }
}
