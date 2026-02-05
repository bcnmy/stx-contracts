// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import { EnumerableSet } from "EnumerableSet4337/EnumerableSet4337.sol";
import { FlatBytesLib } from "flatbytes/BytesLib.sol";
import { IStatelessValidator } from "contracts/interfaces/standard/erc-7780/IStatelessValidator.sol";
import {
    SIG_TYPE_MEE_FLOW,
    SIG_TYPE_SIMPLE,
    SIG_TYPE_ON_CHAIN,
    SIG_TYPE_ERC20_PERMIT,
    SIG_TYPE_SAFE_ACCOUNT,
    SIG_TYPE_NO_STX_VANILLA_1271_EOA,
    SIG_TYPE_SIMPLE_P256,
    SIG_TYPE_NO_STX_VANILLA_1271_P256,
    SIG_TYPE_NO_STX_P256,
    SIG_TYPE_CUSTOM
} from "contracts/types/Constants.sol";

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
    address safeAccountSubmodule;
    address eoaStatelessValidator;
    address p256StatelessValidator;
}

contract ConfigManager {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using FlatBytesLib for FlatBytesLib.Bytes;

    /// @notice Error to indicate that the signature type is not recognized
    error UnrecognizedSignatureType();
    /// @notice Error to indicate that the signature data length is invalid
    error InvalidSignatureDataLength();
    /// @notice Error to indicate that the config is not enabled
    error ConfigNotEnabled();
    /// @notice Error to indicate that the config is already enabled
    error ConfigAlreadyEnabled();
    /// @notice Error to indicate that the stx mode verifier address cannot be the zero address
    error StxModeVerifierAddressCannotBeZeroAddress();

    /// @notice Error to indicate that the stateless validator address cannot be the zero address
    error StatelessValidatorAddressCannotBeZeroAddress();

    address public immutable NO_STX_MODE_VERIFIER;
    address public immutable SIMPLE_MODE_VERIFIER;
    address public immutable PERMIT_MODE_VERIFIER;
    address public immutable TX_MODE_VERIFIER;
    address public immutable SAFE_ACCOUNT_SUBMODULE;
    address public immutable EOA_STATELESS_VALIDATOR;
    address public immutable P256_STATELESS_VALIDATOR;

    mapping(bytes32 configId => mapping(address smartAccount => ValidationConfig config)) public customConfigs;
    EnumerableSet.Bytes32Set internal enabledCustomConfigs;

    mapping(address statelessValidator => mapping(address smartAccount => FlatBytesLib.Bytes validationData)) public
        ownershipData;

    constructor(SubmoduleAddresses memory submoduleAddresses) {
        NO_STX_MODE_VERIFIER = submoduleAddresses.noStxModeVerifier;
        SIMPLE_MODE_VERIFIER = submoduleAddresses.simpleModeVerifier;
        PERMIT_MODE_VERIFIER = submoduleAddresses.permitModeVerifier;
        TX_MODE_VERIFIER = submoduleAddresses.txModeVerifier;
        SAFE_ACCOUNT_SUBMODULE = submoduleAddresses.safeAccountSubmodule;
        EOA_STATELESS_VALIDATOR = submoduleAddresses.eoaStatelessValidator;
        P256_STATELESS_VALIDATOR = submoduleAddresses.p256StatelessValidator;
    }

    /**
     * @dev Internal function to get the submodules for the given signature type
     *      for no sig type prefix, fallback to no stx mode
     * @param smartAccount The smart account that requested the validation
     * @param sigData The signature data to get the submodules for
     */
    function _getSubmodules(
        address smartAccount,
        bytes calldata sigData
    )
        internal
        view
        returns (
            address, /*stxModeVerifier*/
            address, /*statelessValidator*/
            bytes calldata /*parsedSigData*/
        )
    {
        if (sigData.length < 4) {
            revert InvalidSignatureDataLength();
        }
        bytes4 sigType = bytes4(sigData[:4]);
        bytes calldata parsedSigData = sigData[4:];
        if (sigType == SIG_TYPE_SIMPLE) {
            // 0x177eee00
            return (SIMPLE_MODE_VERIFIER, EOA_STATELESS_VALIDATOR, parsedSigData);
        } else if (sigType == SIG_TYPE_ON_CHAIN) {
            // 0x177eee01
            return (TX_MODE_VERIFIER, EOA_STATELESS_VALIDATOR, parsedSigData);
        } else if (sigType == SIG_TYPE_ERC20_PERMIT) {
            // 0x177eee02
            return (PERMIT_MODE_VERIFIER, EOA_STATELESS_VALIDATOR, parsedSigData);
        } else if (sigType == SIG_TYPE_SAFE_ACCOUNT) {
            // 0x177eee04
            return (SAFE_ACCOUNT_SUBMODULE, SAFE_ACCOUNT_SUBMODULE, parsedSigData);
        } else if (sigType == SIG_TYPE_NO_STX_VANILLA_1271_EOA) {
            // 0x177eee05
            return (address(0), EOA_STATELESS_VALIDATOR, parsedSigData);
        } else if (sigType == SIG_TYPE_SIMPLE_P256) {
            // 0x177eee10
            return (SIMPLE_MODE_VERIFIER, P256_STATELESS_VALIDATOR, parsedSigData);
        } else if (sigType == SIG_TYPE_NO_STX_VANILLA_1271_P256) {
            // 0x177eee11
            return (address(0), P256_STATELESS_VALIDATOR, parsedSigData);
        } else if (sigType == SIG_TYPE_NO_STX_P256) {
            // 0x177eee12
            return (NO_STX_MODE_VERIFIER, P256_STATELESS_VALIDATOR, parsedSigData);
        } else if (sigType == SIG_TYPE_CUSTOM) {
            // 0x177eeeff
            require(sigData.length > 36, InvalidSignatureDataLength());
            bytes32 configId = bytes32(sigData[4:36]);
            ValidationConfig storage config = customConfigs[configId][smartAccount];
            return (config.stxModeVerifierAddress, config.statelessValidatorAddress, sigData[36:]);
        } else if (bytes3(sigData[:3]) == SIG_TYPE_MEE_FLOW) {
            // 0x177eee
            // prefix is MEE, but the preconfigured set is not recognized => revert
            revert UnrecognizedSignatureType();
        } else {
            // fallback to no stx mode
            return (NO_STX_MODE_VERIFIER, EOA_STATELESS_VALIDATOR, sigData);
        }
    }

    /**
     * @dev Internal function to get the ownership data for the given stateless validator address
     * @param smartAccount The smart account that requested the validation
     * @param statelessValidator The address of the stateless validator
     * @return _ownershipData The ownership data
     */
    function _getOwnershipData(
        address smartAccount,
        address statelessValidator
    )
        internal
        view
        returns (bytes memory _ownershipData)
    {
        _ownershipData = ownershipData[statelessValidator][smartAccount].load();
        // account for 7702 case
        // if stateless validator is eoa, and ownership data is empty, try to return the smart account address as owner
        // in case smart account is an 7702 delegated EOA, it will work
        // since EVM currently supports only secp256k1 for EOA, we expect
        // EOA_STATELESS_VALIDATOR as stateless validator
        if (_ownershipData.length == 0 && statelessValidator == EOA_STATELESS_VALIDATOR) {
            _ownershipData = abi.encodePacked(smartAccount);
        }
    }

    /**
     * @dev Internal function to store the ownership data for the given stateless validator address
     * @param smartAccount The smart account that requested the validation
     * @param statelessValidator The address of the stateless validator
     * @param _ownershipData The ownership data to store
     */
    function _storeOwnershipDataForAccount(
        address smartAccount,
        address statelessValidator,
        bytes calldata _ownershipData
    )
        internal
    {
        ownershipData[statelessValidator][smartAccount].store(_ownershipData);
    }

    /**
     * @dev Internal function to enable a new config for the smart account
     *      stores the config and adds the config id to the enabled custom configs set
     * @param smartAccount The smart account that requested the validation
     * @param configId The id of the config to add
     * @param stxModeVerifierAddress The address of the stx mode verifier
     * @param statelessValidatorAddress The address of the stateless validator
     */
    function _enableConfigForAccount(
        address smartAccount,
        bytes32 configId,
        address stxModeVerifierAddress,
        address statelessValidatorAddress
    )
        internal
    {
        _storeConfigForAccount(smartAccount, configId, stxModeVerifierAddress, statelessValidatorAddress);
        enabledCustomConfigs.add(smartAccount, configId);
    }

    /**
     * @dev Internal function to replace a config for the smart account
     * @param smartAccount The smart account that requested the validation
     * @param configId The id of the config to replace
     * @param stxModeVerifierAddress The address of the stx mode verifier
     * @param statelessValidatorAddress The address of the stateless validator
     */
    function _replaceConfigForAccount(
        address smartAccount,
        bytes32 configId,
        address stxModeVerifierAddress,
        address statelessValidatorAddress
    )
        internal
    {
        require(enabledCustomConfigs.contains(smartAccount, configId), ConfigNotEnabled());
        _validateConfigAddresses(stxModeVerifierAddress, statelessValidatorAddress);
        _storeConfigForAccount(smartAccount, configId, stxModeVerifierAddress, statelessValidatorAddress);
    }

    /**
     * @dev Internal function to delete a config for the smart account
     * @param smartAccount The smart account that requested the validation
     * @param configId The id of the config to delete
     */
    function _deleteConfigForAccount(address smartAccount, bytes32 configId) internal {
        require(enabledCustomConfigs.contains(smartAccount, configId), ConfigNotEnabled());
        delete customConfigs[configId][smartAccount];
        enabledCustomConfigs.remove(smartAccount, configId);
    }

    /**
     * @dev Internal function to enable a new config for the smart account
     * @param configId The id of the config to add
     * @param stxModeVerifierAddress The address of the stx mode verifier
     * @param statelessValidatorAddress The address of the stateless validator
     */
    function _storeConfigForAccount(
        address smartAccount,
        bytes32 configId,
        address stxModeVerifierAddress,
        address statelessValidatorAddress
    )
        internal
    {
        customConfigs[configId][smartAccount] = ValidationConfig({
            stxModeVerifierAddress: stxModeVerifierAddress, statelessValidatorAddress: statelessValidatorAddress
        });
    }

    /**
     * @dev Internal function to validate the stx mode verifier address
     *      and the stateless validator address
     * @param stxModeVerifierAddress The address of the stx mode verifier
     * @param statelessValidatorAddress The address of the stateless validator
     */
    function _validateConfigAddresses(address stxModeVerifierAddress, address statelessValidatorAddress) internal view {
        require(stxModeVerifierAddress != address(0), StxModeVerifierAddressCannotBeZeroAddress());
        require(statelessValidatorAddress != address(0), StatelessValidatorAddressCannotBeZeroAddress());
    }
}
