// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import { Vm, console2 } from "forge-std/Test.sol";
import { PackedUserOperation } from "account-abstraction/core/UserOperationLib.sol";
import { MeeK1Validator_Base_Test } from "../MeeK1Validator_Base_Test.t.sol";
import { MockTarget } from "../../../mock/MockTarget.sol";
import { CopyUserOpLib } from "../../../util/CopyUserOpLib.sol";
import "contracts/types/Constants.sol";

contract MeeK1Validator_Simple_Mode_Test is MeeK1Validator_Base_Test {
    using CopyUserOpLib for PackedUserOperation;

    function setUp() public virtual override {
        super.setUp();
    }

    // tests simple mode, where the super tx entries are MEE user operations only
    function test_simple_mode_ValidateUserOp_with_MeeUserOps_only_as_entries_success(uint256 numOfClones)
        public
        returns (PackedUserOperation[] memory)
    {
        numOfClones = bound(numOfClones, 1, 25);
        uint256 counterBefore = mockTarget.counter();
        bytes memory innerCallData = abi.encodeWithSelector(MockTarget.incrementCounter.selector);
        PackedUserOperation memory userOp = buildBasicMEEUserOpWithCalldata({
            callData: abi.encodeWithSelector(mockAccount.execute.selector, address(mockTarget), uint256(0), innerCallData),
            account: address(mockAccount),
            userOpSigner: wallet
        });

        PackedUserOperation[] memory userOps = _cloneUserOpToAnArray(userOp, wallet, numOfClones);

        userOps = _makeSimpleSuperTxWithMeeUserOpsOnlyAsEntries(userOps, wallet, address(mockAccount));

        vm.startPrank(MEE_NODE_EXECUTOR_EOA, MEE_NODE_EXECUTOR_EOA);
        ENTRYPOINT.handleOps(userOps, payable(MEE_NODE_ADDRESS));
        vm.stopPrank();

        assertEq(mockTarget.counter(), counterBefore + numOfClones + 1);
        return userOps;
    }

    /*    function test_superTxFlow_simple_mode_1271_and_WithData_success(uint256 numOfObjs) public {
        numOfObjs = bound(numOfObjs, 2, 25);
        bytes[] memory meeSigs = new bytes[](numOfObjs);
        bytes32 baseHash = keccak256(abi.encode("test"));
        meeSigs = makeSimpleSuperTxSignatures({
            baseHash: baseHash,
            total: numOfObjs,
            superTxSigner: wallet,
            mockAccount: address(mockAccount)
        });

        for (uint256 i = 0; i < numOfObjs; i++) {
            // pass the 'unsafe hash' here. however, the root is made with the 'safe' one
            // hash will rehashed in the K1MEEValidator.isValidSignatureWithSender by hashing the SA address into it
            bytes32 includedLeafHash = keccak256(abi.encode(baseHash, i));
            if (i / 2 == 0) {
                assertTrue(
                    mockAccount.validateSignatureWithData(includedLeafHash, meeSigs[i], abi.encodePacked(wallet.addr))
                );
            } else {
                assertTrue(mockAccount.isValidSignature(includedLeafHash, meeSigs[i]) == EIP1271_SUCCESS);
            }
        }
    } */

    // ==== SIMPLE SUPER TX UTILS ====

    function _makeSimpleSuperTxWithMeeUserOpsOnlyAsEntries(
        PackedUserOperation[] memory userOps,
        Vm.Wallet memory superTxSigner,
        address smartAccount
    )
        internal
        view
        returns (PackedUserOperation[] memory)
    {
        uint48 lowerBoundTimestamp = uint48(block.timestamp);
        uint48 upperBoundTimestamp = uint48(block.timestamp + 1000);
        bytes32[] memory stxItemHashes = _eip712HashMeeUserOps(userOps, lowerBoundTimestamp, upperBoundTimestamp);

        (bytes32 stxStructTypeHash, bytes32 stxEip712HashToSign) =
            _hashPureMeeUserOpsStx(userOps, smartAccount, lowerBoundTimestamp, upperBoundTimestamp);

        // eip-712 sign the stx struct
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(superTxSigner.privateKey, stxEip712HashToSign);
        bytes memory superTxHashSignature = abi.encodePacked(r, s, v);

        PackedUserOperation[] memory superTxUserOps = new PackedUserOperation[](userOps.length);
        for (uint256 i; i < userOps.length; ++i) {
            superTxUserOps[i] = userOps[i].deepCopy();

            bytes memory signature = abi.encodePacked(
                SIG_TYPE_SIMPLE,
                abi.encode(
                    stxStructTypeHash,
                    i,
                    stxItemHashes,
                    superTxHashSignature,
                    uint256((uint256(lowerBoundTimestamp) << 128) | uint256(upperBoundTimestamp))
                )
            );
            superTxUserOps[i].signature = signature;
        }
        return superTxUserOps;
    }

    /* function makeSimpleSuperTxSignatures(
        bytes32 baseHash,
        uint256 total,
        Vm.Wallet memory superTxSigner,
        address mockAccount
    )
        internal
        returns (bytes[] memory)
    {
        bytes[] memory meeSigs = new bytes[](total);
        require(total > 0, "total must be greater than 0");

        bytes32[] memory leaves = new bytes32[](total);

        bytes32 hash;
        for (uint256 i = 0; i < total; i++) {
            if (i / 2 == 0) {
                hash = keccak256(abi.encode(baseHash, i));
            } else {
                hash = keccak256(abi.encodePacked(keccak256(abi.encode(baseHash, i)), address(mockAccount)));
            }
            leaves[i] = hash;
        }

        Merkle tree = new Merkle();
        bytes32 root = tree.getRoot(leaves);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(superTxSigner.privateKey, root);
        bytes memory superTxHashSignature = abi.encodePacked(r, s, v);

        for (uint256 i = 0; i < total; i++) {
            bytes32[] memory proof = tree.getProof(leaves, i);
            bytes memory signature = abi.encodePacked(SIG_TYPE_SIMPLE, abi.encode(root, proof, superTxHashSignature));
            meeSigs[i] = signature;
        }
        return meeSigs;
    } */
}
