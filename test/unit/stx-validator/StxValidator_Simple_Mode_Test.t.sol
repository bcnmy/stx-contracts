// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Vm } from "forge-std/Test.sol";
import { StxValidator_Base_Test } from "./StxValidator_Base_Test.t.sol";
import { PackedUserOperation } from "account-abstraction/core/UserOperationLib.sol";
import { CopyUserOpLib } from "../../util/CopyUserOpLib.sol";
import { SimpleModeSubmodule } from "contracts/validators/stx-validator/submodules/SimpleModeSubmodule.sol";
import { MockTarget } from "test/mock/MockTarget.sol";
import { HashLib } from "contracts/lib/stx-validator/HashLib.sol";
import { MEEUserOpHashLib } from "contracts/lib/stx-validator/MEEUserOpHashLib.sol";
import "contracts/types/Constants.sol";

contract StxValidator_Simple_Mode_Test is StxValidator_Base_Test {
    using CopyUserOpLib for PackedUserOperation;

    SimpleModeSubmodule internal simpleModeSubmodule;

    function setUp() public virtual override {
        super.setUp();

        // deploy permit submodule and use it with the default config
        simpleModeSubmodule = new SimpleModeSubmodule();
        vm.prank(address(mockAccount));
        // set the default config
        stxValidator.onInstall(
            abi.encodePacked(
                address(simpleModeSubmodule), address(eoaStatelessValidator), uint8(0), abi.encodePacked(wallet.addr)
            )
        );
    }

    function test_superTxFlow_simple_mode_ValidateUserOp_with_MeeUserOps_only_as_entries_success(uint256 numOfClones)
        public
    {
        numOfClones = bound(numOfClones, 1, 25);
        uint256 counterBefore = mockTarget.counter();
        bytes memory innerCallData = abi.encodeWithSelector(MockTarget.incrementCounter.selector);
        PackedUserOperation memory userOp = buildBasicMEEUserOpWithCalldata({
            callData: abi.encodeWithSelector(
                mockAccount.execute.selector, address(mockTarget), uint256(0), innerCallData
            ),
            account: address(mockAccount),
            userOpSigner: wallet
        });

        PackedUserOperation[] memory userOps = _cloneUserOpToAnArray(userOp, wallet, numOfClones);

        userOps = _makeSimpleSuperTxWithMeeUserOpsOnlyAsEntries(userOps, wallet, address(mockAccount));

        vm.startPrank(MEE_NODE_EXECUTOR_EOA, MEE_NODE_EXECUTOR_EOA);
        ENTRYPOINT.handleOps(userOps, payable(MEE_NODE_ADDRESS));
        vm.stopPrank();

        assertEq(mockTarget.counter(), counterBefore + userOps.length);
    }

    // ==== SIMPLE SUPER TX UTILS ====

    /**
     * @notice Makes a simple superTx with MeeUserOps only as entries
     * @param userOps The user operations to include in the superTx
     * @param superTxSigner The signer of the superTx
     * @param smartAccount The smart account address
     * @return superTxUserOps The superTx user operations
     */
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
}
