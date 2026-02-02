// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import { IValidator, MODULE_TYPE_VALIDATOR } from "erc7579/interfaces/IERC7579Module.sol";
import { IStatelessValidator } from "contracts/interfaces/standard/erc-7780/IStatelessValidator.sol";
import { EnumerableSet } from "EnumerableSet4337/EnumerableSet4337.sol";
import { PackedUserOperation } from "account-abstraction/interfaces/PackedUserOperation.sol";
import { SIG_VALIDATION_FAILED, _packValidationData } from "account-abstraction/core/Helpers.sol";
import { ERC7739Validator } from "./ERC7739Validator.sol";
import {
    SIG_TYPE_SIMPLE,
    SIG_TYPE_ON_CHAIN,
    SIG_TYPE_ERC20_PERMIT,
    SIG_TYPE_SAFE_ACCOUNT,
    ERC1271_SUCCESS,
    ERC1271_FAILED,
    MODULE_TYPE_STATELESS_VALIDATOR,
    SIG_TYPE_MEE_FLOW
} from "contracts/types/Constants.sol";
// Fusion libraries - validate userOp using on-chain tx or off-chain permit
import { PermitValidatorLib } from "../../lib/stx-validator/validation-modes/PermitValidatorLib.sol";
import { TxValidatorLib } from "../../lib/stx-validator/validation-modes/TxValidatorLib.sol";
import { SimpleValidatorLib } from "../../lib/stx-validator/validation-modes/SimpleValidatorLib.sol";
import { SafeAccountValidatorLib } from "../../lib/stx-validator/validation-modes/SafeAccountValidatorLib.sol";
import { NoMeeFlowLib } from "../../lib/stx-validator/validation-modes/NoMeeFlowLib.sol";
import { EcdsaHelperLib } from "../../lib/util/EcdsaHelperLib.sol";
import { FlatBytesLib } from "flatbytes/BytesLib.sol";
import { IStxModeVerifier } from "contracts/interfaces/stx-validator/IStxModeVerifier.sol";
import { IERC7739Multiplexer } from "contracts/interfaces/stx-validator/IERC7739Multiplexer.sol";

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
 *      Special configIds are reserved for non-Stx flows:
 *      - NO_STX_CONFIG_ID_4337 (0x00): Vanilla ERC-4337 UserOp validation
 *      - NO_STX_CONFIG_ID_7739 (0x01): Full ERC-7739 flow for off-chain signatures
 *      - NO_STX_CONFIG_ID_VANILLA_1271 (0x02): Direct ERC-1271 validation
 */

/**
 * @notice Configuration for a validation setup
 * @param stxModeVerifierAddress Address of the IStxModeVerifier submodule for Stx validation
 * @param statelessValidatorAddress Address of the IStatelessValidator for signature verification
 * @param validationData Additional data for validation (e.g., owner public key)
 */
struct ValidationConfig {
    address stxModeVerifierAddress;
    address statelessValidatorAddress;
    FlatBytesLib.Bytes validationData;
}

// keccak256("default");
bytes32 constant DEFAULT_CONFIG_ID = 0xcfee7c08a98f4b565d124c7e4e28acc52e1bc780e3887db0a02a7d2d5bc66728;
// flags for 4337/7739/1271 no stx modes
bytes32 constant NO_STX_CONFIG_ID_4337 = 0x0000000000000000000000000000000000000000000000000000000000000000;
bytes32 constant NO_STX_CONFIG_ID_7739 = 0x0000000000000000000000000000000000000000000000000000000000000001;
bytes32 constant NO_STX_CONFIG_ID_VANILLA_1271 = 0x0000000000000000000000000000000000000000000000000000000000000002;

contract StxValidator is IValidator, IStatelessValidator, ERC7739Validator, IERC7739Multiplexer {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using FlatBytesLib for FlatBytesLib.Bytes;

    /*//////////////////////////////////////////////////////////////////////////
                            CONSTANTS & STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    uint256 private constant ENCODED_DATA_OFFSET = 4;

    mapping(bytes32 configId => mapping(address smartAccount => ValidationConfig config)) public configs;
    EnumerableSet.Bytes32Set internal enabledConfigs;

    /// @notice Set of safe senders for each smart account
    EnumerableSet.AddressSet private _safeSenders;

    /// @notice Error to indicate the module is already initialized
    error ModuleAlreadyInitialized();

    /// @notice Error to indicate that the data length is invalid
    error InvalidDataLength();

    /// @notice Error to indicate that the stx mode verifier address cannot be the zero address
    error StxModeVerifierAddressCannotBeZeroAddress();

    /// @notice Error to indicate that the stateless validator address cannot be the zero address if the stx mode
    /// verifier address is the zero address
    error StatelessValidatorAddressCannotBeZeroIfStxModeVerifierIsZero();

    /// @notice Error to indicate that the config is not enabled
    error ConfigNotEnabled();

    /// @notice Error to indicate that the config is already enabled
    error ConfigAlreadyEnabled();

    /// @notice Error to indicate that the safe senders length is invalid
    error SafeSendersLengthInvalid();

    /// @notice Emitted when a new config is added
    event ConfigAdded(bytes32 indexed configId, address indexed smartAccount);

    /// @notice Emitted when a config is replaced
    event ConfigReplaced(bytes32 indexed configId, address indexed smartAccount);

    /// @notice Emitted when a config is deleted
    event ConfigDeleted(bytes32 indexed configId, address indexed smartAccount);

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
        (bytes32 activeConfigId, bytes calldata parsedSigData) = _parseSignatureWithConfigId(userOp.signature);

        (address stxModeVerifierAddress, address statelessValidatorAddress, bytes memory validationData) =
            _getConfigData(configs, msg.sender, activeConfigId);

        uint48 lowerBoundTimestamp;
        uint48 upperBoundTimestamp;
        bytes32 signedHash;
        bytes memory cleanSignature;

        if (activeConfigId == NO_STX_CONFIG_ID_4337) {
            // in case default config's stx mode verifier address doesn't support
            // the no stx flow detection, we should be able to force it via configId
            lowerBoundTimestamp = 0;
            upperBoundTimestamp = 0;
            signedHash = userOpHash;
            cleanSignature = parsedSigData;
        } else {
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
            // this approach allows not sending the NO_STX_CONFIG_ID explicitly
            // and this save 32 bytes of calldata
            (lowerBoundTimestamp, upperBoundTimestamp, signedHash, cleanSignature) =
                abi.decode(ret, (uint48, uint48, bytes32, bytes));
        }

        // II) Sig validation via erc-7780
        bool isValidSig = IStatelessValidator(statelessValidatorAddress)
            .validateSignatureWithData(signedHash, cleanSignature, validationData);

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

        (bytes32 activeConfigId, bytes calldata parsedSigData) =
            _parseSignatureWithConfigId(_erc1271UnwrapSignature(signature));

        bytes32 meeHash;
        bytes memory cleanSignature;

        if (activeConfigId == NO_STX_CONFIG_ID_7739) {
            // No Stx case with 7739
            // Use the full 7739 flow, including ..viaRPC here
            // because in no stx case, we want to also support signatures for the off-chain parties
            // such as SIWE messages, etc.
            //
            // Since ERC7739Validator._erc1271IsValidSignatureWithSender and _erc1271IsValidSignatureNowCalldata
            // functions do not expect any arguments to pass an additional
            // context (like statelessValidatorAddress or validationData)
            //
            // Thus we have to pack the active configId back into the signature
            // to later use it to obtain the statelessValidatorAddress and validationData
            // required to perform the signature validation via erc-7780.
            //
            // This should be safe because ERC7739Validator's methods only cut data from the LSB's of the signature
            // (right side) and we pack the active configId into the beginning (left-side, MSB's).
            // Unfortunately this is the only workaround to pass the additional context to the ERC7739Validator's
            // methods.
            bytes memory sigWithConfigId = abi.encodePacked(activeConfigId, parsedSigData);

            // the public wrapper function `_validateSignatureViaErc7739` is introduced to put `sigWithConfigId` from
            // memory to calldata
            (bool success, bytes memory result) = address(this)
                .staticcall(
                    abi.encodeCall(this._validateSignatureViaErc7739, (sender, msg.sender, dataHash, sigWithConfigId))
                );
            // early return
            return success && result.length == 32
                ? abi.decode(result, (bytes4))  // if the call is successful and returned proper result => decode it as
                // bytes4 and return
                : ERC1271_FAILED; // if something went wrong => return ERC1271_FAILED
        } else if (activeConfigId == NO_STX_CONFIG_ID_VANILLA_1271) {
            // No Stx case and user explicitly requested vanilla 1271 validation
            // so we just uyse the dataHash and signature as is
            meeHash = dataHash;
            cleanSignature = parsedSigData;
        } else {
            // Stx case
            address stxModeVerifierAddress = configs[activeConfigId][msg.sender].stxModeVerifierAddress;
            require(stxModeVerifierAddress != address(0), StxModeVerifierAddressCannotBeZeroAddress());

            // meeHash is the hash of some data object required by a given stx mode: it can be erc2612 permit object,
            // on-chain tx object, merkle tree root, SuperTx() eip712 data struct, etc.
            // meeHash can even be 7739 hash if IStxModeVerifier assumes it
            (meeHash, cleanSignature) = IStxModeVerifier(stxModeVerifierAddress)
                .processStxDataObject(msg.sender, sender, dataHash, parsedSigData);
        }

        (, address statelessValidatorAddress, bytes memory validationData) =
            _getConfigData(configs, msg.sender, activeConfigId);
        return _validateSignatureViaErc7780(statelessValidatorAddress, validationData, meeHash, cleanSignature)
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
    /// multiplexer if you need to process non-stx modes.
    //  if by some reason non stx mode is still required to be processed
    /// via this validator by some reason, pass the appropriate stxModeVerifierAddress
    /// within the `data` parameter
    function validateSignatureWithData(
        bytes32 hash,
        bytes calldata sig,
        bytes calldata data
    )
        external
        view
        returns (bool isValidSig)
    {
        // parse the config entries from the data parameter
        // no sanity checks for the config entries, we expect the caller to provide valid data
        // stateless validator address should be provided explicitly even if it's the same as the stx mode verifier
        // address
        (
            address account,
            address stxModeVerifierAddress,
            address statelessValidatorAddress,
            bytes memory validationData
        ) = abi.decode(data, (address, address, address, bytes));

        (bytes32 meeHash, bytes memory cleanSignature) =
            IStxModeVerifier(stxModeVerifierAddress).processStxDataObjectFor7780Flow(account, hash, sig);

        isValidSig = _validateSignatureViaErc7780(statelessValidatorAddress, validationData, meeHash, cleanSignature);
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
     *   - 20 bytes - stx mode verifier address
     *   - 20 bytes - custom validator address
     *   - 1 byte - safe senders length (n)
     *   - n*20 bytes - safe senders if any
     *   - config validation data
     */
    function onInstall(bytes calldata data) external override {
        require(!_isInitialized(msg.sender), ModuleAlreadyInitialized());

        // sanity check for the data length
        require(data.length >= 40, InvalidDataLength());

        // 20 bytes - stx mode verifier address
        address stxModeVerifierAddress = address(bytes20(data[:20]));
        require(stxModeVerifierAddress != address(0), StxModeVerifierAddressCannotBeZeroAddress());

        // 20 bytes - custom validator address
        address statelessValidatorAddress = address(bytes20(data[20:40]));
        // if statelessValidatorAddress is zero, we will use the stxModeVerifierAddress
        // as the stateless validator address when loading and using the config later

        // check for the safe senders
        uint8 safeSendersNumber = uint8(bytes1(data[40]));
        uint256 configValidationDataOffset = 41 + safeSendersNumber * 20;
        if (safeSendersNumber > 0) {
            require(data.length >= configValidationDataOffset, InvalidDataLength());
            _fillSafeSenders(data[41:configValidationDataOffset]);
        }

        _storeConfigData(
            DEFAULT_CONFIG_ID, stxModeVerifierAddress, statelessValidatorAddress, data[configValidationDataOffset:]
        );

        enabledConfigs.add(msg.sender, DEFAULT_CONFIG_ID);
    }

    /**
     * De-initialize the module with the given data
     */
    function onUninstall(bytes calldata) external override {
        // Get all enabled configIds for this account
        bytes32[] memory configIds = enabledConfigs.values(msg.sender);
        uint256 len = configIds.length;

        // Delete each config's data
        for (uint256 i; i < len; ++i) {
            bytes32 configId = configIds[i];
            // Clear the validationData stored via FlatBytesLib
            configs[configId][msg.sender].validationData.clear();
            // Delete the config struct
            delete configs[configId][msg.sender];
        }

        // Remove all configIds from the enabledConfigs set
        enabledConfigs.removeAll(msg.sender);

        // Remove all safe senders
        _safeSenders.removeAll(msg.sender);
    }

    /**
     * @dev Adds a new config to the module with the given configId
     * @param configId The id of the config to add
     * @param stxModeVerifierAddress The address of the stx mode verifier
     * @param statelessValidatorAddress The address of the stateless validator
     * @param validationData The data to validate against
     */
    function addConfig(
        bytes32 configId,
        address stxModeVerifierAddress,
        address statelessValidatorAddress,
        bytes calldata validationData
    )
        external
    {
        require(!enabledConfigs.contains(msg.sender, configId), ConfigAlreadyEnabled());
        _validateConfigAddresses(configId, stxModeVerifierAddress, statelessValidatorAddress);

        _storeConfigData(configId, stxModeVerifierAddress, statelessValidatorAddress, validationData);
        emit ConfigAdded(configId, msg.sender);
    }

    /**
     * @dev Adds a new config to the module with the generated configId
     * @param stxModeVerifierAddress The address of the stx mode verifier
     * @param statelessValidatorAddress The address of the stateless validator
     * @param validationData The data to validate against
     */
    function addConfig(
        address stxModeVerifierAddress,
        address statelessValidatorAddress,
        bytes calldata validationData
    )
        external
    {
        bytes32 configId = getConfigId(stxModeVerifierAddress, statelessValidatorAddress, validationData);

        require(!enabledConfigs.contains(msg.sender, configId), ConfigAlreadyEnabled());
        _validateConfigAddresses(configId, stxModeVerifierAddress, statelessValidatorAddress);

        _storeConfigData(configId, stxModeVerifierAddress, statelessValidatorAddress, validationData);
        emit ConfigAdded(configId, msg.sender);
    }

    /**
     * @dev Replaces the config data for the given configId
     * @param configId The id of the config to replace
     * @param stxModeVerifierAddress The address of the stx mode verifier
     * @param statelessValidatorAddress The address of the stateless validator
     * @param validationData The data to validate against
     */
    function replaceConfig(
        bytes32 configId,
        address stxModeVerifierAddress,
        address statelessValidatorAddress,
        bytes calldata validationData
    )
        external
    {
        require(enabledConfigs.contains(msg.sender, configId), ConfigNotEnabled());
        _validateConfigAddresses(configId, stxModeVerifierAddress, statelessValidatorAddress);
        _storeConfigData(configId, stxModeVerifierAddress, statelessValidatorAddress, validationData);
        emit ConfigReplaced(configId, msg.sender);
    }

    /**
     * @dev Deletes the config data for the given configId
     * @param configId The id of the config to delete
     */
    function deleteConfig(bytes32 configId) external {
        require(enabledConfigs.contains(msg.sender, configId), ConfigNotEnabled());
        delete configs[configId][msg.sender];
        enabledConfigs.remove(msg.sender, configId);
        emit ConfigDeleted(configId, msg.sender);
    }

    /**
     * @dev Generates a configId for the given config
     * @param stxModeVerifierAddress The address of the stx mode verifier
     * @param statelessValidatorAddress The address of the stateless validator
     * @param validationData The data to validate against
     * @return configId The id of the config
     */
    function getConfigId(
        address stxModeVerifierAddress,
        address statelessValidatorAddress,
        bytes calldata validationData
    )
        public
        view
        returns (bytes32 configId)
    {
        configId = keccak256(abi.encode(stxModeVerifierAddress, statelessValidatorAddress, validationData));
    }

    /**
     * @dev Internal function to validate the stx mode verifier address
     * @param configId The id of the config about to use the stx mode verifier provided
     * @param stxModeVerifierAddress The address of the stx mode verifier
     */
    function _validateConfigAddresses(
        bytes32 configId,
        address stxModeVerifierAddress,
        address statelessValidatorAddress
    )
        internal
        view
    {
        // no stx configs do not require a valid stx mode verifier address
        if (
            configId != NO_STX_CONFIG_ID_7739 && configId != NO_STX_CONFIG_ID_VANILLA_1271
                && configId != NO_STX_CONFIG_ID_4337
        ) {
            require(stxModeVerifierAddress != address(0), StxModeVerifierAddressCannotBeZeroAddress());
        } else if (stxModeVerifierAddress == address(0)) {
            // in case of one of the above config ids, the stx mode verifier may be zero
            // if so, stateless validator address should be provided explicitly
            require(
                statelessValidatorAddress != address(0), StatelessValidatorAddressCannotBeZeroIfStxModeVerifierIsZero()
            );
        }
    }

    /**
     * @dev Internal function to enable a new config for the smart account
     * @param configId The id of the config to add
     * @param stxModeVerifierAddress The address of the stx mode verifier
     * @param statelessValidatorAddress The address of the stateless validator
     * @param validationData The data to validate against
     */
    function _storeConfigData(
        bytes32 configId,
        address stxModeVerifierAddress,
        address statelessValidatorAddress,
        bytes calldata validationData
    )
        private
    {
        ValidationConfig storage conf = configs[configId][msg.sender];
        conf.stxModeVerifierAddress = stxModeVerifierAddress;
        conf.statelessValidatorAddress = statelessValidatorAddress;
        conf.validationData.store(validationData);
        enabledConfigs.add(msg.sender, configId);
    }

    function getConfigData(
        address smartAccount,
        bytes32 configId
    )
        external
        view
        returns (address stxModeVerifierAddress, address statelessValidatorAddress, bytes memory validationData)
    {
        (stxModeVerifierAddress, statelessValidatorAddress, validationData) =
            _getConfigData(configs, smartAccount, configId);
    }

    function _getConfigData(
        mapping(bytes32 configId => mapping(address smartAccount => ValidationConfig config)) storage configs_,
        address smartAccount,
        bytes32 configId
    )
        internal
        view
        returns (address stxModeVerifierAddress, address statelessValidatorAddress, bytes memory validationData)
    {
        ValidationConfig storage config = configs_[configId][smartAccount];
        stxModeVerifierAddress = config.stxModeVerifierAddress;
        statelessValidatorAddress = config.statelessValidatorAddress;
        _validateConfigAddresses(configId, stxModeVerifierAddress, statelessValidatorAddress);
        // sometimes we use same submodule for both stx mode verifier and stateless validator
        // in this case we can pass address(0) as statelessValidatorAddress
        // and save some calldata gas this way
        if (statelessValidatorAddress == address(0)) {
            statelessValidatorAddress = stxModeVerifierAddress;
        }
        validationData = config.validationData.load();
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

    /**
     * @notice Parses the signature to extract the configId and the remaining signature data
     * @dev The configId is expected to be prepended to the signature (first 32 bytes).
     *      If the first 32 bytes don't match an enabled configId, the default configId is used.
     *      This allows backwards compatibility where signatures without explicit configId
     *      are processed using the default configuration.
     * @param signature The full signature data, potentially prefixed with a configId
     * @return activeConfigId The configId to use for validation
     * @return parsedSigData The signature data with configId stripped (if present)
     */
    function _parseSignatureWithConfigId(bytes calldata signature)
        internal
        view
        returns (bytes32 activeConfigId, bytes calldata parsedSigData)
    {
        if (signature.length < 32) {
            //  it means, there's no configId present
            // at the same time signature is too short for single eoa sig which is 65 bytes
            // so this is some custom signature scheme which should be defined under the default configId
            activeConfigId = DEFAULT_CONFIG_ID;
            parsedSigData = signature;
        } else {
            // take the first 32 bytes and check
            // if there's no config for this id, try the default configId
            // the default configId should always be set (onInstall)
            // this is the branch for flows, where we want to use a default config and the sig itself is long enough:
            // we do not provide an enabled configId => random 32 bytes are used as configId =>
            // ofc this random configId is not enabled => we use the default configId
            // the chance that random 32 bytes of the signature data match an enabled configId is very low
            activeConfigId = bytes32(signature[0:32]);
            parsedSigData = signature[32:];
            if (!enabledConfigs.contains(msg.sender, activeConfigId)) {
                activeConfigId = DEFAULT_CONFIG_ID;
                parsedSigData = signature; // means there was no configId encoded into the signature
            }
        }
    }

    /// @notice Checks if the smart account is initialized with an owner
    /// @param smartAccount The address of the smart account
    /// @return isInitializedRet True if the smart account has an owner, false otherwise
    function _isInitialized(address smartAccount) private view returns (bool isInitializedRet) {
        return enabledConfigs.contains(smartAccount, DEFAULT_CONFIG_ID);
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
     * @notice Wrapper method to validate signature via ERC-7739 nested typed data flow
     * @dev This public wrapper is needed to convert bytes memory to bytes calldata
     *      for the internal ERC7739Validator methods. Uses staticcall internally.
     * @param sender The original sender of the ERC-1271 request
     * @param account The smart account being validated
     * @param meeHash The hash to validate
     * @param sigWithConfigId The signature with configId prepended
     * @return bytes4 ERC1271_SUCCESS or ERC1271_FAILED
     */
    function _validateSignatureViaErc7739(
        address sender,
        address account,
        bytes32 meeHash,
        bytes calldata sigWithConfigId
    )
        public
        view
        returns (bytes4)
    {
        // note: ERC7739Validator._erc1271IsValidSignatureWithSender uses _erc1271IsValidSignatureNowCalldata under the
        // hood to validate the signature so see how _erc1271IsValidSignatureNowCalldata is overridden in this contract
        return _erc1271IsValidSignatureWithSender(sender, account, meeHash, sigWithConfigId);
    }

    /**
     * @notice Wrapper method to validate signature via ERC-7780 stateless validator
     * @param statelessValidatorAddress The address of the stateless validator to use
     * @param validationData The validation data (e.g., owner public key)
     * @param hash The hash that was signed
     * @param signature The signature to validate
     * @return isValidSig True if the signature is valid
     */
    function _validateSignatureViaErc7780(
        address statelessValidatorAddress,
        bytes memory validationData,
        bytes32 hash,
        bytes memory signature
    )
        internal
        view
        returns (bool isValidSig)
    {
        isValidSig =
            IStatelessValidator(statelessValidatorAddress).validateSignatureWithData(hash, signature, validationData);
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
        // parse the active configId from the signature
        bytes32 activeConfigId = bytes32(signature[0:32]);
        (, address statelessValidatorAddress, bytes memory validationData) =
            _getConfigData(configs, account, activeConfigId);

        isValidSig = _validateSignatureViaErc7780(statelessValidatorAddress, validationData, hash, signature[32:]);
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
