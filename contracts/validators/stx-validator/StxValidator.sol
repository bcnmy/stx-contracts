// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import { IValidator, MODULE_TYPE_VALIDATOR } from "erc7579/interfaces/IERC7579Module.sol";
import { IStatelessValidator } from "contracts/interfaces/standard/erc-7780/IStatelessValidator.sol";
import { PackedUserOperation } from "account-abstraction/interfaces/PackedUserOperation.sol";
import { _packValidationData } from "account-abstraction/core/Helpers.sol";
import { EnumerableSet } from "EnumerableSet4337/EnumerableSet4337.sol";
import { ERC7739Validator } from "./ERC7739Validator.sol";
import { ERC1271_SUCCESS, ERC1271_FAILED, MODULE_TYPE_STATELESS_VALIDATOR } from "contracts/types/Constants.sol";
import { FlatBytesLib } from "flatbytes/BytesLib.sol";
import { IStxModeVerifier } from "contracts/interfaces/stx-validator/IStxModeVerifier.sol";
import { IERC7739Multiplexer } from "contracts/interfaces/stx-validator/IERC7739Multiplexer.sol";
import { ConfigManager, SubmoduleAddresses, ValidationConfig } from "./ConfigManager.sol";

/**
 * @title StxValidator
 * @author Biconomy
 * @notice ERC-7579 compatible validator module for validating ERC-4337 UserOps
 *         and ERC-1271 signatures that are part of MEE SuperTransactions (Stx).
 * @dev This validator implements a modular two-layer architecture:
 *
 *      1. **Stx Mode Verification (IStxModeVerifier)**: Validates that a UserOp or data object
 *         is part of a SuperTransaction. Different modes are supported via pluggable submodules:
 *         - Simple Mode: Direct EIP-712 signing of SuperTx struct
 *         - Permit Mode: ERC-2612 permit with Stx hash in deadline field
 *         - Tx Mode: On-chain transaction with Stx hash appended to calldata
 *         - Safe Account Mode: Safe multisig transaction as trigger
 *
 *      2. **Signature Verification (IStatelessValidator / ERC-7780)**: Cryptographic verification
 *         of signatures, agnostic to the signing scheme. Supported schemes include:
 *         - EOA (secp256k1)
 *         - Passkeys (secp256r1 / P256)
 *         - Safe multisig
 *         - Any custom scheme implementing IStatelessValidator
 *
 *      The validator stores per-account configurations (configId => account => config) that
 *      specify which submodules to use for verification. Multiple configs can be enabled
 *      per account to support different signing methods or Stx modes.
 *
 */

contract StxValidator is IValidator, IStatelessValidator, ERC7739Validator, IERC7739Multiplexer, ConfigManager {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.AddressSet;
    using FlatBytesLib for FlatBytesLib.Bytes;

    /*//////////////////////////////////////////////////////////////////////////
                            CONSTANTS & STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    uint256 private constant ENCODED_DATA_OFFSET = 4;

    /// @notice Set of safe senders for each smart account
    EnumerableSet.AddressSet private _safeSenders;

    /// @notice Error to indicate the module is already initialized
    error ModuleAlreadyInitialized();

    /// @notice Error to indicate that the data length is invalid
    error InvalidDataLength();

    /// @notice Error to indicate that the safe senders length is invalid
    error SafeSendersLengthInvalid();

    /// @notice Error to indicate that the ownership data already exists for the stateless validator
    error OwnershipDataAlreadyExistsForStatelessValidator(address statelessValidatorAddress);

    /// @notice Error to indicate that the module is not initialized
    error ModuleNotInitialized();

    /// @notice Emitted when a new config is added
    event ConfigAdded(bytes32 indexed configId, address indexed smartAccount);

    /// @notice Emitted when a config is replaced
    event ConfigReplaced(bytes32 indexed configId, address indexed smartAccount);

    /// @notice Emitted when a config is deleted
    event ConfigDeleted(bytes32 indexed configId, address indexed smartAccount);

    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/
    constructor(SubmoduleAddresses memory submoduleAddresses) ConfigManager(submoduleAddresses) { }

    /*//////////////////////////////////////////////////////////////////////////
                                     MODULE LOGIC
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * Validates PackedUserOperation
     *
     * @param userOp UserOperation to be validated
     * @param userOpHash Hash of the UserOperation to be validated
     * @dev fallback flow => non MEE flow => no dedicated prefix introduced for the sake of compatibility.
     *      It may lead to a case where some signature turns out to have first bytes matching the prefix.
     *      However, this is very unlikely to happen and even if it does, the consequences are just
     *      that the signature is not validated which is easily solved by altering userOp => hash => sig.
     *      The userOp.signature is encoded as follows:
     *      MEE flow: [65 bytes node master signature] [4 bytes sigType] [encoded data for this validator]
     *      Non-MEE flow: [65 bytes regular secp256k1 sig]
     * @dev Since we do not expect much vanilla AA (via ERC-4337) to be used with this validator,
     *      we do not introduce a separate logic branch here for the non-Stx flow here.
     *      Instead, we expect IStxModeVerifier to identify the non-Stx flow (most likely by
     *      checking the signature length), and handle the non-Stx flow by returning the appropriate
     *      `ret` value with same format as the Stx flow, but with empty timestamps and non-altered
     *      userOpHash and signature.
     *
     * @return vd validation data = the result of the signature validation, which can be:
     *  - 0 if the signature is valid
     *  - 1 if the signature is invalid
     *  - <20-byte> aggregatorOrSigFail, <6-byte> validUntil and <6-byte> validAfter (see ERC-4337
     * for more details)
     */
    function validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash
    )
        external
        override
        returns (uint256)
    {
        (address stxModeVerifierAddress, address statelessValidatorAddress, bytes calldata parsedSigData) =
            _getSubmodules(msg.sender, userOp.signature);

        uint48 lowerBoundTimestamp;
        uint48 upperBoundTimestamp;
        bytes32 signedHash;
        bytes memory cleanSignature;

        // I) processStxUserOpData is parsing the userOp.signature,
        // makes sure the given userOp is the part of the superTx
        // return timestamps and signed hash + clean signature for the further
        // sig verification via erc-7780
        // if external call reverts => this method will revert as well => will make handleOps revert with AA23
        bytes memory ret = IStxModeVerifier(stxModeVerifierAddress)
            .processStxUserOpData({ account: msg.sender, userOpHash: userOpHash, signatureData: parsedSigData });

        // decode ret
        // backward compatibility flow: if IStxValidator.processStxUserOpData detects the non-mee flow, it
        // will just repack og userOpHash and userOp.signature and (0,0) as timestamps into ret
        // so at the next step the sig validation will happen with the original userOpHash and userOp.signature
        // as in the vanilla erc-4337 flow
        (lowerBoundTimestamp, upperBoundTimestamp, signedHash, cleanSignature) =
            abi.decode(ret, (uint48, uint48, bytes32, bytes));

        bytes memory ownershipData = _getOwnershipData(msg.sender, statelessValidatorAddress);
        // II) Sig validation via erc-7780
        bool isValidSig = IStatelessValidator(statelessValidatorAddress)
            .validateSignatureWithData(signedHash, cleanSignature, ownershipData);

        // return validation data as per erc-4337
        // first value is sigValidationFailed which is opposite to isValidSig returned by the validateSignatureWithData
        return _packValidationData(!isValidSig, upperBoundTimestamp, lowerBoundTimestamp);
    }

    /**
     * Validates an ERC-1271/ERC-7739 signature
     *      Alert!: SIWE messages should not be included in the superTx.
     *      (Neither other objects which are intended to be used by off-chain code)
     *      Please sign SIWE objects separately, not as a part of the superTx.
     *      Stx is expected to include only data structs that are to be
     *      verified and used by on-chain protocols, not off-chain code.
     *
     * @param sender The sender of the ERC-1271 call to the account
     * @param dataHash The hash of the DataObject Stx entry
     * @param signature The signature of the message, with all the additions:
     *                  1. Append 7739 payload to the signature (if needed)
     *                  2. Make the signature as per expected IStxModeVerifier
     *                    for example, signature = abi.encode(DecodedErc20PermitSig(...))
     *                    for the permit mode
     *                  3. Prepend configId to the signature (left side, MSB's)
     *                     if needed (for the default configId, no need to prepend)
     *
     * @return sigValidationResult the result of the signature validation, which can be:
     *  - ERC1271_SUCCESS if the signature is valid
     *  - ERC1271_FAILED if the signature is invalid
     */
    function isValidSignatureWithSender(
        address sender,
        bytes32 dataHash,
        bytes calldata signature
    )
        external
        view
        virtual
        override
        returns (bytes4)
    {
        // ERC-7739 detection
        if (signature.length == 0) {
            // in this case it doesn't matter what address we pass as account
            return _erc1271IsValidSignatureWithSender(sender, address(0), dataHash, signature);
        }

        (address stxModeVerifierAddress, address statelessValidatorAddress, bytes calldata parsedSigData) =
            _getSubmodules(msg.sender, _erc1271UnwrapSignature(signature));

        bytes32 meeHash;
        bytes memory cleanSignature;

        if (stxModeVerifierAddress == address(0)) {
            // user explicitly requested vanilla 1271 validation
            meeHash = dataHash;
            cleanSignature = parsedSigData;
        } else {
            (meeHash, cleanSignature) = IStxModeVerifier(stxModeVerifierAddress)
                .processStxDataObject(msg.sender, sender, dataHash, parsedSigData);
        }

        bytes memory ownershipData = _getOwnershipData(msg.sender, statelessValidatorAddress);

        return _validateSignatureViaErc7780(statelessValidatorAddress, ownershipData, meeHash, cleanSignature)
            ? ERC1271_SUCCESS
            : ERC1271_FAILED;
    }

    /// @notice IStatelessValidator interface
    /// @param hash The hash of the data to validate
    /// @param sig The signature data
    /// @param data The data to validate against (owner address in this case)
    /// @dev No erc-7739 flow needed, as if this module acts as a stateless validator,
    /// all the logic related to erc-7739 has already been handled at this point by caller contract.
    /// @dev no explicit flow for non-stx mode here, as it makes no sense to use this
    ///      module as a stateless validator for non-stx modes.
    ///      It is recommended to use submodules from this repository as stateless validators directly in your
    ///      multiplexer if you need to process non-stx modes.
    ///      if by some reason non stx mode is still required to be processed
    ///      via this validator, pass the appropriate stxModeVerifierAddress
    ///      within the `data` parameter
    function validateSignatureWithData(
        bytes32 hash,
        bytes calldata sig,
        bytes calldata data
    )
        external
        view
        returns (bool isValidSig)
    {
        (address account, bytes memory _ownershipData) = abi.decode(data, (address, bytes));

        (address stxModeVerifierAddress, address statelessValidatorAddress, bytes calldata parsedSigData) =
            _getSubmodules(account, sig);

        (bytes32 meeHash, bytes memory cleanSignature) =
            IStxModeVerifier(stxModeVerifierAddress).processStxDataObjectFor7780Flow(account, hash, parsedSigData);

        isValidSig = _validateSignatureViaErc7780(statelessValidatorAddress, _ownershipData, meeHash, cleanSignature);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                     ERC-7739 MULTIPLEXER INTERFACE
    //////////////////////////////////////////////////////////////////////////*/
    /**
     * @dev Returns the hash and signature for the ERC-7739 validation
     * @param account The account that requested the validation
     * @param sender The sender that requested the validation
     * @param hash The hash of the data to validate
     * @param signature The signature of the data to validate
     * @return The hash and signature for the ERC-7739 validation
     */
    function getErc7739HashAndSignature(
        address account,
        address sender,
        bytes32 hash,
        bytes calldata signature
    )
        external
        view
        returns (bytes32, bytes calldata)
    {
        return _getErc7739HashAndSignature(account, sender, hash, signature);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                     CONFIG
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * Initialize the module with the given data
     *   onInstall always uses the default configId
     *   if more configs are needed, they should be added later
     *
     * @param data The data to initialize the module with
     *   data format:
     *   [20 bytes] stateless validator address
     *   ----If custom config is being enabled----:
     *   [20 bytes] stx mode verifier address
     *   [32 bytes] configId
     *   -----------------------------------------:
     *   [1 byte] safe senders number
     *   [safeSendersNumber * 20 bytes] safe senders addresses
     *   [ownershipDataLength bytes] ownership data
     */
    function onInstall(bytes calldata data) external override {
        require(!_isInitialized(msg.sender), ModuleAlreadyInitialized());

        // sanity check for the data length
        require(data.length >= 20, InvalidDataLength());

        // 20 bytes - stateless validator address
        address statelessValidatorAddress = address(bytes20(data[:20]));

        uint256 startSafeSendersOffset = 20;

        bool _enableCustomConfig = _isCustomConfig(statelessValidatorAddress);
        if (_enableCustomConfig) {
            require(data.length >= 72, InvalidDataLength());
            // start safe senders offset
            startSafeSendersOffset = 72;
        }

        // check for the safe senders
        uint8 safeSendersNumber = uint8(bytes1(data[startSafeSendersOffset]));
        uint256 ownershipDataOffset = startSafeSendersOffset + 1 + safeSendersNumber * 20;
        if (safeSendersNumber > 0) {
            require(data.length >= ownershipDataOffset, InvalidDataLength());
            _fillSafeSenders(data[startSafeSendersOffset + 1:ownershipDataOffset]);
        }

        if (_enableCustomConfig) {
            // 20 bytes - stx mode verifier address
            address stxModeVerifierAddress = address(bytes20(data[20:40]));
            // 32 bytes config id
            bytes32 configId = bytes32(data[40:72]);

            _enableConfigForAccount({
                smartAccount: msg.sender,
                configId: configId,
                stxModeVerifierAddress: stxModeVerifierAddress,
                statelessValidatorAddress: statelessValidatorAddress
            });
        }

        _storeOwnershipDataForAccount({
            smartAccount: msg.sender,
            statelessValidator: statelessValidatorAddress,
            _ownershipData: data[ownershipDataOffset:]
        });
    }

    /**
     * De-initialize the module with the given data
     * @dev Removes all configurations and data stored for the calling smart account
     */
    function onUninstall(bytes calldata) external override {
        require(_isInitialized(msg.sender), ModuleNotInitialized());

        address account = msg.sender;

        // 1. Clear all safe senders for this account
        _safeSenders.removeAll(account);

        // 2. Clear ownership data for default stateless validators
        _deleteOwnershipDataForAccount(account, EOA_STATELESS_VALIDATOR);
        _deleteOwnershipDataForAccount(account, P256_STATELESS_VALIDATOR);
        _deleteOwnershipDataForAccount(account, SAFE_ACCOUNT_SUBMODULE);

        // 3. Clear all custom configs and their associated ownership data
        uint256 configCount = enabledCustomConfigs.length(account);
        for (uint256 i = 0; i < configCount; i++) {
            bytes32 configId = enabledCustomConfigs.at(account, i);

            // Get the stateless validator address from the config and clear its ownership data
            address statelessValidator = customConfigs[configId][account].statelessValidatorAddress;
            ownershipData[statelessValidator][account].clear();

            delete customConfigs[configId][account];
        }
        enabledCustomConfigs.removeAll(account);
    }

    /**
     * @dev Sets the ownership data for the given stateless validator address
     * @param statelessValidatorAddress The address of the stateless validator
     * @param ownershipData The ownership data to set
     */
    function setOwnershipData(address statelessValidatorAddress, bytes calldata ownershipData) external {
        _storeOwnershipDataForAccount(msg.sender, statelessValidatorAddress, ownershipData);
    }

    /**
     * @dev Clears the ownership data for the given stateless validator address
     * @param statelessValidatorAddress The address of the stateless validator
     */
    function cleanOwnershipData(address statelessValidatorAddress) external {
        _deleteOwnershipDataForAccount(msg.sender, statelessValidatorAddress);
    }

    /**
     * @dev Returns the ownership data for the given stateless validator address
     * @param statelessValidatorAddress The address of the stateless validator
     * @return The ownership data
     */
    function getOwnershipData(
        address smartAccount,
        address statelessValidatorAddress
    )
        external
        view
        returns (bytes memory)
    {
        return _getOwnershipData(smartAccount, statelessValidatorAddress);
    }

    /**
     * @dev Adds a new config to the module with the given configId
     *      Alert: it doesn't store the ownership data for the stateless validator associated with the config
     *      If this config is reusing the same stateless validator as another config or preconfigured sig type,
     *      then the existing ownership data will be used.
     *      If this config is not sharing the same stateless validator with another config or preconfigured sig type,
     *      then the ownership data should be set manually via setOwnershipData
     * @param configId The id of the config to add
     * @param stxModeVerifierAddress The address of the stx mode verifier
     * @param statelessValidatorAddress The address of the stateless validator
     */
    function addConfig(bytes32 configId, address stxModeVerifierAddress, address statelessValidatorAddress) external {
        require(!enabledCustomConfigs.contains(msg.sender, configId), ConfigAlreadyEnabled());
        _validateConfigAddresses(stxModeVerifierAddress, statelessValidatorAddress);
        _enableConfigForAccount(msg.sender, configId, stxModeVerifierAddress, statelessValidatorAddress);
        emit ConfigAdded(configId, msg.sender);
    }

    /**
     * @dev Replaces the config data for the given configId
     * @param configId The id of the config to replace
     * @param stxModeVerifierAddress The address of the stx mode verifier
     * @param statelessValidatorAddress The address of the stateless validator
     */
    function replaceConfig(
        bytes32 configId,
        address stxModeVerifierAddress,
        address statelessValidatorAddress,
        bytes calldata ownershipData
    )
        external
    {
        // if a new stateless validator is provided, clear the ownership data for the old one
        address oldStatelessValidatorAddress = customConfigs[configId][msg.sender].statelessValidatorAddress;
        if (statelessValidatorAddress != oldStatelessValidatorAddress) {
            _deleteOwnershipDataForAccount(msg.sender, oldStatelessValidatorAddress);
        }
        _replaceConfigForAccount(msg.sender, configId, stxModeVerifierAddress, statelessValidatorAddress);
        // in any case, we store the ownership data for the new stateless validator
        _storeOwnershipDataForAccount(msg.sender, statelessValidatorAddress, ownershipData);
        emit ConfigReplaced(configId, msg.sender);
    }

    /**
     * @dev Deletes the config data for the given configId
     *      Alert: it doesn't clear the ownership data for the stateless validator associated with the config
     *      because it may be used by other configs or preconfigured sig types
     *      if you want to clear the ownership data for the stateless validator associated with the config,
     *      you should manually clear it via cleanOwnershipData
     * @param configId The id of the config to delete
     */

    function deleteConfig(bytes32 configId) external {
        address statelessValidatorAddress = customConfigs[configId][msg.sender].statelessValidatorAddress;
        _deleteConfigForAccount(msg.sender, configId);
        emit ConfigDeleted(configId, msg.sender);
    }

    /**
     * @dev Checks if the config is enabled for the given smart account
     * @param smartAccount The smart account to check the config for
     * @param configId The id of the config to check
     * @return True if the config is enabled, false otherwise
     */
    function isConfigEnabled(address smartAccount, bytes32 configId) external view returns (bool) {
        return enabledCustomConfigs.contains(smartAccount, configId);
    }

    /**
     * @dev Returns the config data for the given configId
     * @param smartAccount The smart account to get the config data for
     * @param configId The id of the config to get the data for
     * @return config The config data
     */
    function getConfigData(
        address smartAccount,
        bytes32 configId
    )
        external
        view
        returns (ValidationConfig memory config)
    {
        config = customConfigs[configId][smartAccount];
    }

    /**
     * Check if the module is initialized
     * @param smartAccount The smart account to check
     *
     * @return true if the module is initialized, false otherwise
     */
    function isInitialized(address smartAccount) external view returns (bool) {
        return _isInitialized(smartAccount);
    }

    /// @notice Adds a safe sender to the _safeSenders list for the smart account
    function addSafeSender(address sender) external {
        _safeSenders.add(msg.sender, sender);
    }

    /// @notice Removes a safe sender from the _safeSenders list for the smart account
    function removeSafeSender(address sender) external {
        _safeSenders.remove(msg.sender, sender);
    }

    /// @notice Checks if a sender is in the _safeSenders list for the smart account
    function isSafeSender(address sender, address smartAccount) external view returns (bool) {
        return _safeSenders.contains(smartAccount, sender);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                     METADATA
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Returns the name of the module
    /// @return The name of the module
    function name() external pure returns (string memory) {
        return "StxValidator";
    }

    /// @notice Returns the version of the module
    /// @return The version of the module
    function version() external pure returns (string memory) {
        return "0.0.1";
    }

    /// @notice Checks if the module is of the specified type
    /// @param typeId The type ID to check
    /// @return True if the module is of the specified type, false otherwise
    function isModuleType(uint256 typeId) external pure returns (bool) {
        return typeId == MODULE_TYPE_VALIDATOR || typeId == MODULE_TYPE_STATELESS_VALIDATOR;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                     INTERNAL
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Checks if the smart account is initialized with an owner
    /// @param smartAccount The address of the smart account
    /// @return isInitializedRet True if the smart account has an owner, false otherwise
    function _isInitialized(address smartAccount) private view returns (bool isInitializedRet) {
        return ownershipData[EOA_STATELESS_VALIDATOR][smartAccount].totalLength > 0
            || ownershipData[P256_STATELESS_VALIDATOR][smartAccount].totalLength > 0
            || ownershipData[SAFE_ACCOUNT_SUBMODULE][smartAccount].totalLength > 0
            || enabledCustomConfigs.length(smartAccount) > 0;
    }

    /**
     * @notice Fills the _safeSenders list from the given data
     * @dev Data must be a multiple of 20 bytes (packed addresses)
     * @param data Packed array of addresses (20 bytes each)
     */
    function _fillSafeSenders(bytes calldata data) private {
        require(data.length % 20 == 0, SafeSendersLengthInvalid());
        uint256 len = data.length / 20;
        for (uint256 i; i < len; ++i) {
            _safeSenders.add(msg.sender, address(bytes20(data[20 * i:20 * (i + 1)])));
        }
    }

    /**
     * @notice Wrapper method to validate signature via ERC-7780 stateless validator
     * @param statelessValidatorAddress The address of the stateless validator to use
     * @param ownershipData The ownership data (e.g., owner public key)
     * @param hash The hash that was signed
     * @param signature The signature to validate
     * @return isValidSig True if the signature is valid
     */
    function _validateSignatureViaErc7780(
        address statelessValidatorAddress,
        bytes memory ownershipData,
        bytes32 hash,
        bytes memory signature
    )
        internal
        view
        returns (bool isValidSig)
    {
        isValidSig =
            IStatelessValidator(statelessValidatorAddress).validateSignatureWithData(hash, signature, ownershipData);
    }

    /**
     * @dev Checks if the stateless validator address is one of the default ones
     *      if not => a custom config required
     * @param statelessValidatorAddress The address of the stateless validator
     * @return isCustomConfig True if the stateless validator address is a custom config, false otherwise
     */
    function _isCustomConfig(address statelessValidatorAddress) internal view returns (bool isCustomConfig) {
        isCustomConfig =
        !(statelessValidatorAddress == EOA_STATELESS_VALIDATOR || statelessValidatorAddress == P256_STATELESS_VALIDATOR
                || statelessValidatorAddress == SAFE_ACCOUNT_SUBMODULE);
    }

    /*//////////////////////////////////////////////////////////////////////////
                         ERC-7739 VALIDATOR BASE OVERRIDES
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Returns whether the `hash` and `signature` are valid.
    ///      Obtains the authorized signer's credentials and calls some
    ///      module's specific internal function to validate the signature
    ///      against credentials.
    /// @param hash The hash of the data to validate, processed as per erc7739
    ///             if required
    /// @param signature The signature of the data, with all the potential
    ///                  erc7739 payload trimmed off, just with the configId prepended

    function _erc1271IsValidSignatureNowCalldata(
        address account,
        bytes32 hash,
        bytes calldata signature
    )
        internal
        view
        override
        returns (bool isValidSig)
    {
        address stxModeVerifierAddress = address(bytes20(signature[0:20]));
        address statelessValidatorAddress = address(bytes20(signature[20:40]));
        bytes memory _ownershipData = _getOwnershipData(account, statelessValidatorAddress);
        isValidSig = _validateSignatureViaErc7780(statelessValidatorAddress, _ownershipData, hash, signature[40:]);
    }

    /// @dev Returns whether the `sender` is considered safe, such
    /// that we don't need to use the nested EIP-712 workflow.
    /// See: https://mirror.xyz/curiousapple.eth/pFqAdW2LiJ-6S4sg_u1z08k4vK6BCJ33LcyXpnNb8yU
    // The canonical `MulticallerWithSigner` at 0x000000000000D9ECebf3C23529de49815Dac1c4c
    // is known to include the account in the hash to be signed.
    // msg.sender = Smart Account
    // sender = 1271 og request sender
    function _erc1271CallerIsSafe(
        address account,
        address sender
    )
        internal
        view
        virtual
        override
        returns (bool isCallerSafe)
    {
        isCallerSafe =
        (sender == 0x000000000000D9ECebf3C23529de49815Dac1c4c // MulticallerWithSigner
                || sender == account // Smart Account. Assume smart account never sends non safe eip-712 struct
                || _safeSenders.contains(account, sender)); // check if sender is in _safeSenders for the Smart
        // Account
    }
}
