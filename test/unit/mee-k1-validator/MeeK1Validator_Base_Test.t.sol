// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Vm } from "forge-std/Test.sol";
import { PackedUserOperation } from "account-abstraction/core/UserOperationLib.sol";
import { EfficientHashLib } from "solady/utils/EfficientHashLib.sol";
import { BaseTest } from "../../Base.t.sol";
import { MEEUserOpHashLib } from "../../../contracts/lib/util/MEEUserOpHashLib.sol";
import { MockAccount } from "../../mock/MockAccount.sol";
import { CopyUserOpLib } from "../../util/CopyUserOpLib.sol";
import { HashLib, SUPER_TX_MEE_USER_OP_ARRAY_TYPEHASH } from "contracts/lib/util/HashLib.sol";
import "contracts/types/Constants.sol";

contract MeeK1Validator_Base_Test is BaseTest {
    using CopyUserOpLib for PackedUserOperation;
    using EfficientHashLib for *;

    Vm.Wallet wallet;
    MockAccount mockAccount;
    uint256 valueToSet;

    function setUp() public virtual override {
        super.setUp();
        wallet = createAndFundWallet("wallet", 5 ether);
        mockAccount = deployMockAccount({ validator: address(k1MeeValidator), handler: address(0) });
        vm.prank(address(mockAccount));
        k1MeeValidator.transferOwnership(wallet.addr);
        valueToSet = MEE_NODE_HEX;
    }

    // ==== MEE USER OP UTILS ====

    /**
     * @notice Builds a basic MEE user operation with a given calldata
     * @param callData The calldata to execute
     * @param account The account to execute the calldata on
     * @param userOpSigner The signer of the user operation
     * @return userOp The built user operation
     */
    /* solhint-disable foundry-test-functions */
    function buildBasicMEEUserOpWithCalldata(
        bytes memory callData,
        address account,
        Vm.Wallet memory userOpSigner
    )
        public
        view
        returns (PackedUserOperation memory)
    {
        PackedUserOperation memory userOp = buildUserOpWithCalldata({
            account: account,
            callData: callData,
            wallet: userOpSigner,
            preVerificationGasLimit: 3e5,
            verificationGasLimit: 500e3,
            callGasLimit: 3e6
        });

        userOp = _makeMEEUserOp({
            userOp: userOp,
            pmValidationGasLimit: 40_000,
            pmPostOpGasLimit: 50_000,
            _wallet: userOpSigner,
            sigType: bytes4(0)
        });

        return userOp;
    }

    /**
     * @notice Internal function to make a MEE user operation out of a AA user operation
     * adds appropriate paymaster and data to the user operation
     * and adds MEE type prefix to the signature
     *
     * @param userOp The user operation to make MEE
     * @param pmValidationGasLimit The validation gas limit for the PM
     * @param pmPostOpGasLimit The post-op gas limit for the PM
     * @param _wallet The wallet to sign the user operation
     * @param sigType The signature type
     * @return userOp The built user operation
     */
    function _makeMEEUserOp(
        PackedUserOperation memory userOp,
        uint128 pmValidationGasLimit,
        uint128 pmPostOpGasLimit,
        Vm.Wallet memory _wallet,
        bytes4 sigType
    )
        internal
        view
        returns (PackedUserOperation memory)
    {
        // refund mode = user
        // premium mode = percentage premium
        userOp.paymasterAndData = abi.encodePacked(
            address(NODE_PAYMASTER),
            pmValidationGasLimit, // pm validation gas limit
            pmPostOpGasLimit, // pm post-op gas limit
            NODE_PM_MODE_USER,
            NODE_PM_PREMIUM_PERCENT,
            uint192(1_700_000)
        );

        userOp.signature = signUserOp(_wallet, userOp);
        if (sigType != bytes4(0)) {
            userOp.signature = abi.encodePacked(sigType, userOp.signature);
        }
        return userOp;
    }

    /**
     * @notice Creates an array of identical user operations with incremented nonces
     * @param userOp The user operation to clone
     * @param userOpSigner The signer of the user operation
     * @param numOfClones The number of clones to create
     * @return userOps The array of user operations
     */
    function _cloneUserOpToAnArray(
        PackedUserOperation memory userOp,
        Vm.Wallet memory userOpSigner,
        uint256 numOfClones
    )
        internal
        view
        returns (PackedUserOperation[] memory)
    {
        PackedUserOperation[] memory userOps = new PackedUserOperation[](numOfClones + 1);
        userOps[0] = userOp;
        for (uint256 i = 0; i < numOfClones; i++) {
            assertEq(userOps[i].nonce, i);
            userOps[i + 1] = _duplicateUserOpAndIncrementNonce(userOps[i], userOpSigner);
        }
        return userOps;
    }

    /**
     * @notice Helper function to duplicate a user operation and increment the nonce
     * @param userOp The user operation to duplicate
     * @param userOpSigner The signer of the user operation
     * @return userOp The duplicated user operation
     */
    function _duplicateUserOpAndIncrementNonce(
        PackedUserOperation memory userOp,
        Vm.Wallet memory userOpSigner
    )
        internal
        view
        returns (PackedUserOperation memory)
    {
        PackedUserOperation memory newUserOp = userOp.deepCopy();
        newUserOp.nonce = userOp.nonce + 1;
        newUserOp.signature = signUserOp(userOpSigner, newUserOp);
        return newUserOp;
    }

    /**
     * @notice Hashes a super tx with only MeeUserOps as entries
     * @param superTxUserOps The array of user operations to hash
     * @param smartAccount The smart account to hash the super tx for
     * @param lowerBoundTimestamp The lower bound timestamp
     * @param upperBoundTimestamp The upper bound timestamp
     * @return stxStructTypeHash The type hash of the super tx
     * @return stxEip712HashToSign The EIP-712 hash of the SuperTx(MeeUserOp[] meeUserOps) to sign
     */
    function _hashPureMeeUserOpsStx(
        PackedUserOperation[] memory superTxUserOps,
        address smartAccount,
        uint48 lowerBoundTimestamp,
        uint48 upperBoundTimestamp
    )
        internal
        view
        returns (bytes32 stxStructTypeHash, bytes32 stxEip712HashToSign)
    {
        // since in this function stx is built of MeeUserOps only, we treat it as an array of MeeUserOps structs
        // SuperTx(MeeUserOp[] meeUserOps)
        stxStructTypeHash = SUPER_TX_MEE_USER_OP_ARRAY_TYPEHASH;
        // and thus we also have to hash the encoded data as an array of MeeUserOps structs
        // encode data for an array of structs is "keccak256 hash of the concatenated encodeData
        // of their contents" as per eip-712
        bytes memory encodedData;
        bytes32[] memory a = EfficientHashLib.malloc(superTxUserOps.length);
        for (uint256 i; i < superTxUserOps.length; ++i) {
            bytes32 userOpHash = ENTRYPOINT.getUserOpHash(superTxUserOps[i]);
            bytes32 meeUserOpEip712Hash =
                MEEUserOpHashLib.getMeeUserOpEip712Hash(userOpHash, lowerBoundTimestamp, upperBoundTimestamp);
            a.set(i, meeUserOpEip712Hash);
        }
        encodedData = abi.encodePacked(a.hash());
        // now has the struct as per eip-712
        bytes32 structHash = keccak256(abi.encodePacked(stxStructTypeHash, encodedData));
        // and make the final hash to sign with the domain separator
        stxEip712HashToSign = HashLib.hashTypedDataForAccount(smartAccount, structHash);
    }

    // TODO: function _hashMixedTypeStx()

    /**
     * @notice Hashes every user operation in the array with the given lower and upper bound timestamps
     * @param userOps The array of user operations to hash
     * @param lowerBoundTimestamp The lower bound timestamp
     * @param upperBoundTimestamp The upper bound timestamp
     * @return itemHashes The array of hashed data structs: MEEUserOp(bytes32 userOpHash,uint256
     * lowerBoundTimestamp,uint256 upperBoundTimestamp)
     */
    function _eip712HashMeeUserOps(
        PackedUserOperation[] memory userOps,
        uint48 lowerBoundTimestamp,
        uint48 upperBoundTimestamp
    )
        internal
        view
        returns (bytes32[] memory)
    {
        bytes32[] memory itemHashes = new bytes32[](userOps.length);
        for (uint256 i; i < userOps.length; ++i) {
            bytes32 userOpHash = ENTRYPOINT.getUserOpHash(userOps[i]);
            itemHashes[i] = MEEUserOpHashLib.getMeeUserOpEip712Hash(userOpHash, lowerBoundTimestamp, upperBoundTimestamp);
        }
        return itemHashes;
    }
}
