// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import { IValidator, MODULE_TYPE_VALIDATOR } from "erc7579/interfaces/IERC7579Module.sol";
import { IStatelessValidator } from "contracts/interfaces/standard/erc-7780/IStatelessValidator.sol";
import { EnumerableSet } from "EnumerableSet4337/EnumerableSet4337.sol";
import { PackedUserOperation } from "account-abstraction/interfaces/PackedUserOperation.sol";
import { SIG_VALIDATION_FAILED, _packValidationData } from "account-abstraction/core/Helpers.sol";
import { ERC7739Validator } from "erc7739Validator/ERC7739Validator.sol";
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
import { IStatelessValidator } from "contracts/interfaces/standard/erc-7780/IStatelessValidator.sol";
import { IStxModeVerifier } from "contracts/interfaces/stx-validator/IStxModeVerifier.sol";

/**
 * @title K1MeeValidator
 *
 *
 */

struct ValidationConfig {
    address stxModeVerifierAddress;
    address statelessValidatorAddress;
    FlatBytesLib.Bytes validationData;
}

// keccak256("default");
bytes32 constant DEFAULT_CONFIG_ID = 0xcfee7c08a98f4b565d124c7e4e28acc52e1bc780e3887db0a02a7d2d5bc66728;

contract StxValidator is IValidator, IStatelessValidator, ERC7739Validator {
    using EnumerableSet for EnumerableSet.AddressSet; // TODO: remove this?

    using EnumerableSet for EnumerableSet.Bytes32Set;
    using FlatBytesLib for FlatBytesLib.Bytes;

    /*//////////////////////////////////////////////////////////////////////////
                            CONSTANTS & STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    uint256 private constant ENCODED_DATA_OFFSET = 4;

    mapping(bytes32 configId => mapping(address smartAccount => ValidationConfig config)) public configs;
    EnumerableSet.Bytes32Set internal enabledConfigs;

    // address => configId => config (sig validator can be of 1271 or 7780 type)

    /// @notice Set of safe senders for each smart account
    EnumerableSet.AddressSet private _safeSenders;

    /// @notice Error to indicate that no owner was provided during installation
    error NoOwnerProvided();

    /// @notice Error to indicate that the new owner cannot be the zero address
    error ZeroAddressNotAllowed();

    /// @notice Error to indicate the module is already initialized
    error ModuleAlreadyInitialized();

    /// @notice Error to indicate that the owner cannot be the zero address
    error OwnerCannotBeZeroAddress();

    /// @notice Error to indicate that the data length is invalid
    error InvalidDataLength();

    /// @notice Error to indicate that the safe senders length is invalid
    error SafeSendersLengthInvalid();

    /// @notice Error to indicate that the stx mode verifier address cannot be the zero address
    error StxModeVerifierAddressCannotBeZeroAddress();

    /*//////////////////////////////////////////////////////////////////////////
                                     CONFIG
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * Initialize the module with the given data
     *
     * @param data The data to initialize the module with
     */
    function onInstall(bytes calldata data) external override {
        // 20 bytes - stx mode verifier address
        // 20 bytes - custom validator address
        // 1 byte - safe senders length (n)
        // n*20 bytes - safe senders if any
        // config validation data

        /**
         *   onInstall always uses the default configId
         *   if more configs are needed, they should be added later
         *
         *   no backwards compatibility features are needed
         *
         */

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
            _fillSafeSenders(data[21:configValidationDataOffset]);
        }

        ValidationConfig storage conf = configs[DEFAULT_CONFIG_ID][msg.sender];
        conf.stxModeVerifierAddress = stxModeVerifierAddress;
        conf.statelessValidatorAddress = statelessValidatorAddress;
        conf.validationData.store(data[configValidationDataOffset:]);

        enabledConfigs.add(msg.sender, DEFAULT_CONFIG_ID);
    }

    /**
     * De-initialize the module with the given data
     */
    function onUninstall(bytes calldata) external override {
        // TODO: clean configs
        _safeSenders.removeAll(msg.sender);
    }

    // TODO:
    // implement a function to replace ownership data within a config

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

        // I) processStxUserOpData is parsing the userOp.signature,
        // makes sure the given userOp is the part of the superTx
        // return timestamps and signed hash + clean signature for the further
        // sig verification via erc-7780
        // if external call reverts => this method will revert as well => will make handleOps revert with AA23
        (bool isSigValidationRequired, bytes memory ret) =
            IStxModeVerifier(stxModeVerifierAddress).processStxUserOpData(userOpHash, parsedSigData);

        // decode ret
        // backward compatibility flow: if IStxValidator.processStxUserOpData detects the non-mee flow, it
        // will just repack og userOpHash and userOp.signature and (0,0) as timestamps into ret
        // so at the next step the sig validation will happen with the original userOpHash and userOp.signature
        // as in the vanilla erc-4337 flow
        (uint48 lowerBoundTimestamp, uint48 upperBoundTimestamp, bytes32 signedHash, bytes memory cleanSignature) =
            abi.decode(ret, (uint48, uint48, bytes32, bytes));

        // II) Sig validation via erc-7780
        bool isValidSig = isSigValidationRequired
            ? IStatelessValidator(statelessValidatorAddress)
                .validateSignatureWithData(signedHash, cleanSignature, validationData)
            : true;

        // return validation data as per erc-4337
        // first value is sigValidationFailed which is opposite to isValidSig returned by the validateSignatureWithData
        return _packValidationData(!isValidSig, upperBoundTimestamp, lowerBoundTimestamp);
    }

    /**
     * Validates an ERC-1271 signature
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
            return _erc1271IsValidSignatureWithSender(sender, dataHash, signature);
        }

        (bytes32 activeConfigId, bytes calldata parsedSigData) =
            _parseSignatureWithConfigId(_erc1271UnwrapSignature(signature));

        address stxModeVerifierAddress = configs[activeConfigId][msg.sender].stxModeVerifierAddress;
        require(stxModeVerifierAddress != address(0), StxModeVerifierAddressCannotBeZeroAddress());

        // FLOW IS:
        // 1. call IStxModeVerifier.processStxDataObject(hash, sig)
        //    this IStxModeVerifier will decode the signature according to the stx mode
        //    as a part of this decoding, in applicable modes (for example, simple mode and permit mode)
        //    it will get a signature that is packed as per eip-7739
        //    and also it will prepare the pre-7739 hash using the data from the
        //    decoded signature (like making the Permit struct hash in the permit mode)

        // (( for the on-chain tx mode, we do not need 7739, we just rehash the txn hash with the smart account
        // address))

        // 2. pass this data to the ERC7739Validator methods (prepend active configId to the signature as well)
        //    those methods do their magic and call IStatelessValidator via overridden
        // _erc1271IsValidSignatureNowCalldata method

        // So when we prepare data for this flow off-chain, what we do is:
        // 1. prepare the meeHash, for example, the Permit struct hash in the permit mode
        //    or the SuperTx() struct hash in the simple mode
        // 2. Rebuild 7739 hash out of it and sign it
        // 3. Prepare the 7739 signature by appending the 7739 specific data to the signature
        // 4. Prepare the Stx signature by encoding the signature as per stx mode

        // meeHash is the hash of some data object required by a given stx mode: it can be erc2612 permit object,
        // on-chain tx object, merkle tree root, SuperTx() eip712 data struct, etc.
        (bool isErc7739Required, bytes32 meeHash, bytes memory cleanSignature) =
            IStxModeVerifier(stxModeVerifierAddress).processStxDataObject(dataHash, parsedSigData);

        if (isErc7739Required) {
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
            // methods. ---
            // !!! TODO: do a thoroughful test for it to make sure it works as expected
            bytes memory sigWithConfigId = abi.encodePacked(activeConfigId, cleanSignature);

            // the public wrapper function `_validateSignatureViaErc7739` is introduced to put `sigWithConfigId` from
            // memory to calldata
            (bool success, bytes memory result) = address(this)
                .staticcall(abi.encodeCall(this._validateSignatureViaErc7739, (sender, meeHash, sigWithConfigId)));
            return success && result.length == 32
                ? abi.decode(result, (bytes4))  // if the call is successful and returned proper result => decode it as
                // bytes4 and return
                : ERC1271_FAILED; // if something went wrong => return ERC1271_FAILED
        } else {
            // StxMode verifier reported, that erc-7739 is not needed (hash is already safe in terms of having SA
            // address hashed into it) => we can use ERC-7780 directly to validate the signature
            (, address statelessValidatorAddress, bytes memory validationData) =
                _getConfigData(configs, msg.sender, activeConfigId);
            return _validateSignatureViaErc7780(statelessValidatorAddress, validationData, meeHash, cleanSignature)
                ? ERC1271_SUCCESS
                : ERC1271_FAILED;
        }
    }

    /// @notice IStatelessValidator interface
    /// @param hash The hash of the data to validate
    /// @param sig The signature data
    /// @param data The data to validate against (owner address in this case)
    /// @dev No erc-7739 flow needed, as if this module acts as a stateless validator,
    /// all the logic related to erc-7739 has already been handled at this point by caller contract.
    function validateSignatureWithData(
        bytes32 hash,
        bytes calldata sig,
        bytes calldata data
    )
        external
        view
        returns (bool isValidSig)
    {
        ValidationConfig memory config = abi.decode(data, (ValidationConfig));
        // parse the config entries from the data parameter
        // no sanity checks for the config entries, we expect the caller to provide valid data
        (address stxModeVerifierAddress, address statelessValidatorAddress, bytes memory validationData) =
            abi.decode(data, (address, address, bytes));

        (, bytes32 meeHash, bytes memory cleanSignature) =
            IStxModeVerifier(stxModeVerifierAddress).processStxDataObject(hash, sig);

        isValidSig = _validateSignatureViaErc7780(statelessValidatorAddress, validationData, meeHash, cleanSignature);
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
    /// @dev
    /// - supports appended 65-bytes signature for on-chain fusion mode
    /// - supports erc7702-delegated EOAs as owners
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
        require(stxModeVerifierAddress != address(0), StxModeVerifierAddressCannotBeZeroAddress());
        // sometimes we use same submodule for both stx mode verifier and stateless validator
        // in this case we can pass address(0) as statelessValidatorAddress
        // and save some calldata gas this way
        if (statelessValidatorAddress == address(0)) {
            statelessValidatorAddress = stxModeVerifierAddress;
        }
        validationData = config.validationData.load();
    }

    /// @notice Checks if the smart account is initialized with an owner
    /// @param smartAccount The address of the smart account
    /// @return isInitializedRet True if the smart account has an owner, false otherwise
    function _isInitialized(address smartAccount) private view returns (bool isInitializedRet) {
        // TODO: properly implement this check using enabled configs
    }

    // @notice Fills the _safeSenders list from the given data
    // data provided should always be 20*n
    function _fillSafeSenders(bytes calldata data) private {
        for (uint256 i; i < data.length / 20; ++i) {
            _safeSenders.add(msg.sender, address(bytes20(data[20 * i:20 * (i + 1)])));
        }
    }

    // @dev wrapper method to convert bytes memory to bytes calldata
    function _validateSignatureViaErc7739(
        address sender,
        bytes32 meeHash,
        bytes calldata sigWithConfigId
    )
        public
        view
        returns (bytes4)
    {
        // note: ERC7739Validator._erc1271IsValidSignatureWithSender uses _erc1271IsValidSignatureNowCalldata under the
        // hood to validate the signature so see how _erc1271IsValidSignatureNowCalldata is overridden in this contract
        return _erc1271IsValidSignatureWithSender(sender, meeHash, sigWithConfigId);
    }

    // @dev Wrapper method to validate the signature via erc-7780
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
            _getConfigData(configs, msg.sender, activeConfigId);

        isValidSig = _validateSignatureViaErc7780(statelessValidatorAddress, validationData, hash, signature[32:]);
    }

    /// @dev Returns whether the `sender` is considered safe, such
    /// that we don't need to use the nested EIP-712 workflow.
    /// See: https://mirror.xyz/curiousapple.eth/pFqAdW2LiJ-6S4sg_u1z08k4vK6BCJ33LcyXpnNb8yU
    // The canonical `MulticallerWithSigner` at 0x000000000000D9ECebf3C23529de49815Dac1c4c
    // is known to include the account in the hash to be signed.
    // msg.sender = Smart Account
    // sender = 1271 og request sender
    function _erc1271CallerIsSafe(address sender) internal view virtual override returns (bool isCallerSafe) {
        isCallerSafe =
        (sender == 0x000000000000D9ECebf3C23529de49815Dac1c4c // MulticallerWithSigner
                || sender == msg.sender // Smart Account. Assume smart account never sends non safe eip-712 struct
                || _safeSenders.contains(msg.sender, sender)); // check if sender is in _safeSenders for the Smart
        // Account
    }
}
