// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import { IValidator, MODULE_TYPE_VALIDATOR } from "erc7579/interfaces/IERC7579Module.sol";
import { IStatelessValidator } from "contracts/interfaces/standard/erc-7780/IStatelessValidator.sol";
import { EnumerableSet } from "EnumerableSet4337/EnumerableSet4337.sol";
import { PackedUserOperation } from "account-abstraction/interfaces/PackedUserOperation.sol";
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

/**
 * @title K1MeeValidator
 *
 *
 */

enum ValidationType {
    ERC1271,
    ERC7780
}

struct ValidationConfig {
    address validatorAddress;
    ValidationType validationType;
    FlatBytesLib.Bytes validationData;
}

contract K1MeeValidator is IValidator, IStatelessValidator, ERC7739Validator {
    using EnumerableSet for EnumerableSet.AddressSet;
    /*//////////////////////////////////////////////////////////////////////////
                            CONSTANTS & STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    uint256 private constant ENCODED_DATA_OFFSET = 4;

    mapping(bytes32 configId => mapping(address smartAccount => ValidationConfig config)) public configs;

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

    /*//////////////////////////////////////////////////////////////////////////
                                     CONFIG
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * Initialize the module with the given data
     *
     * @param data The data to initialize the module with
     */
    function onInstall(bytes calldata data) external override {

        // first bytes are always a flag:
        // 4 bytes - mode flag
        // 1 byte - safe senders length (n)
        // 20 bytes - custom validator address if mode flag is `custom`
        // n*20 bytes - safe senders if any
        // config validation data

        /**
         *   onInstall always uses the default configId
         *   if more configs are needed, they should be added later
         *
         *   no backwards compatibility features are needed
         *
         *   new initdata format:
         *
         *][init data]
         *     statelss validator address is required for the custom setup mode, for example for
         *     `setup-k1` mode, we can use a pre-encoded k1 stateless validator address
         *     setup modes: k1 (eoa), r1 (passkey), 1271 (isValidSig), eoa-multisig, custom.
         *     `custom` is followed by the stateless  validator address
         */

        /*
        require(data.length != 0, NoOwnerProvided());
        require(!_isInitialized(msg.sender), ModuleAlreadyInitialized());
        address newOwner = address(bytes20(data[:20]));
        require(newOwner != address(0), OwnerCannotBeZeroAddress());
        smartAccountOwners[msg.sender] = newOwner;
        if (data.length > 20) {
            _fillSafeSenders(data[20:]);
        }
        */
    }

    /**
     * De-initialize the module with the given data
     */
    function onUninstall(bytes calldata) external override {
        delete smartAccountOwners[msg.sender];
        _safeSenders.removeAll(msg.sender);
    }

    /// @notice Transfers ownership of the validator to a new owner
    /// @param newOwner The address of the new owner
    function transferOwnership(address newOwner) external {
        require(newOwner != address(0), ZeroAddressNotAllowed());
        smartAccountOwners[msg.sender] = newOwner;
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
        bytes32 activeConfigId;
        uint48 lowerBoundTimestamp;
        uint48 upperBoundTimestamp;
        bytes memory signature;
        bytes32 signedHash;
        bool sigValidationFailed = true; // do not validate by default

        // stx modes
        if (userOp.signature.length >= ENCODED_DATA_OFFSET) {
            if (userOp.signature.length < ENCODED_DATA_OFFSET + 32) {
                //  it means, there's no configId present
                // at the same time userOp.signature is too short for single eoa sig which is 65 bytes
                // so this is some custom signature scheme which should be defined under the default configId
                configId = DEFAULT_CONFIG_ID;
            }

            // take the first 32 bytes and check
            // if there's no config for this id, try the default configId
            // the default configId should always be set (onInstall)
            activeConfigId = bytes32(userOp.signature[ENCODED_DATA_OFFSET:ENCODED_DATA_OFFSET + 32]);
            if (!enabledConfigs.contains(activeConfigId)) {
                activeConfigId = DEFAULT_CONFIG_ID;
            }

            // call mode libraries: they validate the current userOp is the part of the SuperTxn
            // and returns the data (signed hash and signature) for the further sig validation
            // no mee flow is also handled there
            (signedHash, lowerBoundTimestamp, upperBoundTimestamp, signature) =
                _validateStxUserOp(userOpHash, userOp.signature);

            /*
            bytes4 sigType = bytes4(userOp.signature[0:ENCODED_DATA_OFFSET]);
            if (sigType == SIG_TYPE_SIMPLE) {
                = SimpleValidatorLib.validateStxUserOp(userOpHash, userOp.signature[ENCODED_DATA_OFFSET:], owner);
            }
            else if (sigType == SIG_TYPE_ON_CHAIN) {
                TxValidatorLib.validateStxUserOp(userOpHash, userOp.signature[ENCODED_DATA_OFFSET:userOp.signature.length], owner);
            } else if (sigType == SIG_TYPE_ERC20_PERMIT) {
                PermitValidatorLib.validateStxUserOp(userOpHash, userOp.signature[ENCODED_DATA_OFFSET:], owner);
            } else if (sigType == SIG_TYPE_SAFE_ACCOUNT) {
                SafeAccountValidatorLib.validateStxUserOp(userOpHash, userOp.signature[ENCODED_DATA_OFFSET:], owner);
            }*/

            sigValidationFailed = !configs.validateSignature({
                smartAccount: msg.sender, configId: activeConfigId, userOpHash: signedHash, signature: signature
            });

            return _packValidationData(sigValidationFailed, upperBoundTimestamp, lowerBoundTimestamp);
        }

        revert InvalidDataLength();
    }

    /**
     * Validates an ERC-1271 signature
     *
     * @param sender The sender of the ERC-1271 call to the account
     * @param dataHash The hash of the message
     * @param signature The signature of the message
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
        returns (bytes4 sigValidationResult)
    { }

    /// @notice IStatelessValidator interface
    /// @param hash The hash of the data to validate
    /// @param sig The signature data
    /// @param data The data to validate against (owner address in this case)
    function validateSignatureWithData(
        bytes32 hash,
        bytes calldata sig,
        bytes calldata data
    )
        external
        view
        returns (bool isValidSig)
    { }

    /**
     * Get the owner of the smart account
     * @param smartAccount The address of the smart account
     * @return The owner of the smart account
     */
    function getOwner(address smartAccount) public view returns (address) {
        address owner = smartAccountOwners[smartAccount];
        return owner == address(0) ? smartAccount : owner;
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

    /// @notice Internal method that does the job of validating the signature via ECDSA (secp256k1)
    /// @param owner The address of the owner
    /// @param hash The hash of the data to validate
    /// @param signature The signature data
    function _validateSignatureForOwner(
        address owner,
        bytes32 hash,
        bytes calldata signature
    )
        internal
        view
        returns (bool isValidSig)
    {
        bytes4 sigType = bytes4(signature[0:4]);

        if (sigType == SIG_TYPE_SIMPLE) {
            isValidSig = SimpleValidatorLib.validateSignatureForOwner(owner, hash, signature[4:]);
        } else if (sigType == SIG_TYPE_ON_CHAIN) {
            isValidSig = TxValidatorLib.validateSignatureForOwner(owner, hash, signature[4:]);
        } else if (sigType == SIG_TYPE_ERC20_PERMIT) {
            isValidSig = PermitValidatorLib.validateSignatureForOwner(owner, hash, signature[4:]);
        } else if (sigType == SIG_TYPE_SAFE_ACCOUNT) {
            isValidSig = SafeAccountValidatorLib.validateSignatureForOwner(owner, hash, signature[4:]);
        } else {
            // fallback flow => non MEE flow => no prefix
            isValidSig = NoMeeFlowLib.validateSignatureForOwner(owner, hash, signature);
        }
    }

    /// @notice Checks if the smart account is initialized with an owner
    /// @param smartAccount The address of the smart account
    /// @return isInitializedRet True if the smart account has an owner, false otherwise
    function _isInitialized(address smartAccount) private view returns (bool isInitializedRet) {
        isInitializedRet = smartAccountOwners[smartAccount] != address(0);
    }

    // @notice Fills the _safeSenders list from the given data
    function _fillSafeSenders(bytes calldata data) private {
        uint256 length = data.length;
        require(length % 20 == 0, SafeSendersLengthInvalid());
        for (uint256 i; i < length / 20; ++i) {
            _safeSenders.add(msg.sender, address(bytes20(data[20 * i:20 * (i + 1)])));
        }
    }

    /// @dev Returns whether the `hash` and `signature` are valid.
    ///      Obtains the authorized signer's credentials and calls some
    ///      module's specific internal function to validate the signature
    ///      against credentials.
    function _erc1271IsValidSignatureNowCalldata(
        bytes32 hash,
        bytes calldata signature
    )
        internal
        view
        override
        returns (bool isValidSig)
    {
        // call custom internal function to validate the signature against credentials

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
