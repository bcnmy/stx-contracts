// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import { Vm, console2 } from "forge-std/Test.sol";
import { PackedUserOperation } from "account-abstraction/core/UserOperationLib.sol";
import { StxValidator_Base_Test } from "./StxValidator_Base_Test.t.sol";
import { MockTarget } from "../../mock/MockTarget.sol";
import { MockAccount } from "../../mock/accounts/MockAccount.sol";
import { CopyUserOpLib } from "../../util/CopyUserOpLib.sol";
import { HashLib, SUPER_TX_MEE_USER_OP_ARRAY_TYPEHASH } from "contracts/lib/stx-validator/HashLib.sol";
import { MEEUserOpHashLib } from "contracts/lib/stx-validator/MEEUserOpHashLib.sol";
import "contracts/types/Constants.sol";
import { EfficientHashLib } from "solady/utils/EfficientHashLib.sol";
import { SimpleModeSubmodule } from "contracts/validators/stx-validator/submodules/SimpleModeSubmodule.sol";

/**
 * @title StxValidator_Simple_Mode_Multichain_Test
 * @notice Tests that a 712 simple mode signature is valid on all chains
 * @dev The signature is valid because the domain separator is the same for all chains
 *      (has no chain id, address, or version in the simple mode implementation)
 *
 *      NOTE ON FOUNDRY MULTICHAIN SIMULATION:
 *      In Foundry, `vm.chainId()` only changes the value returned by `block.chainid` - it does NOT
 *      simulate separate blockchain states. All contracts remain deployed in the same EVM state,
 *      accessible at their same addresses regardless of the "chain" being simulated.
 *
 *      This means:
 *      - StxValidator, SimpleModeSubmodule, EOAStatelessValidator exist at single addresses
 *      - Both mockAccountChain1 and mockAccountChain2 use the same validator instances
 *      - The validator's storage (config mappings) is shared across "chains"
 *
 *      In a REAL multichain deployment, each chain would have its own deployments of all contracts.
 *      However, this test is still valid because it tests that the SAME SIGNATURE can validate
 *      userOps across chains - the key property being that Simple Mode's domain separator doesn't
 *      include chainId, allowing signature reuse. The `ENTRYPOINT.getUserOpHash()` DOES include
 *      `block.chainid`, so each chain's userOp hash is different, but they're all included in the
 *      same SuperTx and validated with a single signature.
 */
contract StxValidator_Simple_Mode_Multichain_Test is StxValidator_Base_Test {
    using CopyUserOpLib for PackedUserOperation;
    using EfficientHashLib for *;

    // Chain IDs for testing
    uint256 constant CHAIN_1 = 8888;
    uint256 constant CHAIN_2 = 2517;

    // Mock accounts per chain
    MockAccount mockAccountChain1;
    MockAccount mockAccountChain2;

    // Mock targets per chain
    MockTarget mockTargetChain1;
    MockTarget mockTargetChain2;

    SimpleModeSubmodule internal simpleModeSubmodule;

    function setUp() public virtual override {
        super.setUp();

        // Deploy simple mode submodule once - in Foundry's single-state simulation,
        // this is accessible from all "chains"
        simpleModeSubmodule = new SimpleModeSubmodule();
    }

    /**
     * @notice Test with a more realistic scenario: single signature for all chains
     * @dev This test demonstrates that in simple mode, one signature can validate across chains
     *      because the domain separator doesn't include chainId
     */
    function test_StxValidator_simple_mode_single_signature_multiple_chains() public {
        // Save original chain ID
        uint256 originalChainId = block.chainid;

        // ============ DEPLOY ACCOUNTS ON MULTIPLE CHAINS ============
        // Note: In Foundry, contracts deployed here are accessible from all "chains"
        // Only the block.chainid value changes, not the actual EVM state
        vm.chainId(CHAIN_1);
        mockTargetChain1 = new MockTarget();
        mockAccountChain1 = deployMockAccount({ validator: address(stxValidator), handler: address(0) });
        vm.prank(address(mockAccountChain1));
        stxValidator.onInstall(
            abi.encodePacked(
                address(simpleModeSubmodule), address(eoaStatelessValidator), uint8(0), abi.encodePacked(wallet.addr)
            )
        );

        vm.chainId(CHAIN_2);
        mockTargetChain2 = new MockTarget();
        mockAccountChain2 = deployMockAccount({ validator: address(stxValidator), handler: address(0) });
        vm.prank(address(mockAccountChain2));
        stxValidator.onInstall(
            abi.encodePacked(
                address(simpleModeSubmodule), address(eoaStatelessValidator), uint8(0), abi.encodePacked(wallet.addr)
            )
        );

        // mock target 1, mock target 2, mock account 1, mock account 2
        // are as well acessible under both chainIds in fact (see above)
        // we just want it at different addresses for the testing purposes

        //make sure the accounts are deployed to the different addresses
        assertTrue(
            address(mockAccountChain1) != address(mockAccountChain2), "Chain 1 and Chain 2 accounts should be different"
        );

        // ============ CREATE USER OPS ============
        uint48 lowerBoundTimestamp = uint48(block.timestamp);
        uint48 upperBoundTimestamp = uint48(block.timestamp + 1000);

        vm.chainId(CHAIN_1);
        bytes memory innerCallDataChain1 = abi.encodeWithSelector(MockTarget.incrementCounter.selector);
        PackedUserOperation memory userOpChain1 = buildBasicMEEUserOpWithCalldata({
            callData: abi.encodeWithSelector(
                mockAccountChain1.execute.selector, address(mockTargetChain1), uint256(0), innerCallDataChain1
            ),
            account: address(mockAccountChain1),
            userOpSigner: wallet
        });

        vm.chainId(CHAIN_2);
        bytes memory innerCallDataChain2 = abi.encodeWithSelector(MockTarget.incrementCounter.selector);
        PackedUserOperation memory userOpChain2 = buildBasicMEEUserOpWithCalldata({
            callData: abi.encodeWithSelector(
                mockAccountChain2.execute.selector, address(mockTargetChain2), uint256(0), innerCallDataChain2
            ),
            account: address(mockAccountChain2),
            userOpSigner: wallet
        });

        // ============ CREATE SUPER TX WITH BOTH USER OPS ============
        PackedUserOperation[] memory userOps = new PackedUserOperation[](2);
        userOps[0] = userOpChain1;
        userOps[1] = userOpChain2;

        // Calculate item hashes
        bytes32[] memory stxItemHashes = new bytes32[](2);

        vm.chainId(CHAIN_1);
        bytes32 userOpHash1 = ENTRYPOINT.getUserOpHash(userOpChain1);
        stxItemHashes[0] =
            MEEUserOpHashLib.getMeeUserOpEip712Hash(userOpHash1, lowerBoundTimestamp, upperBoundTimestamp);

        vm.chainId(CHAIN_2);
        bytes32 userOpHash2 = ENTRYPOINT.getUserOpHash(userOpChain2);
        stxItemHashes[1] =
            MEEUserOpHashLib.getMeeUserOpEip712Hash(userOpHash2, lowerBoundTimestamp, upperBoundTimestamp);

        // ============ SIGN WITH CHAIN 1'S ACCOUNT ============
        vm.chainId(CHAIN_1);

        bytes32 stxStructTypeHash = SUPER_TX_MEE_USER_OP_ARRAY_TYPEHASH;

        bytes memory encodedData;
        bytes32[] memory a = EfficientHashLib.malloc(stxItemHashes.length);
        for (uint256 i; i < stxItemHashes.length; ++i) {
            a.set(i, stxItemHashes[i]);
        }
        encodedData = abi.encodePacked(a.hash());
        bytes32 structHash = keccak256(abi.encodePacked(stxStructTypeHash, encodedData));
        bytes32 stxEip712HashToSign = HashLib.hashTypedDataForAccount(address(mockAccountChain1), structHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wallet.privateKey, stxEip712HashToSign);
        bytes memory superTxHashSignature = abi.encodePacked(r, s, v);

        // ============ CREATE SIGNED USER OPS ============
        // Note: StxValidator simple mode doesn't use SIG_TYPE_SIMPLE prefix
        PackedUserOperation[] memory signedUserOps = new PackedUserOperation[](2);

        signedUserOps[0] = userOpChain1.deepCopy();
        signedUserOps[0].signature = abi.encode(
            stxStructTypeHash,
            uint256(0),
            stxItemHashes,
            superTxHashSignature,
            uint256((uint256(lowerBoundTimestamp) << 128) | uint256(upperBoundTimestamp))
        );

        signedUserOps[1] = userOpChain2.deepCopy();
        signedUserOps[1].signature = abi.encode(
            stxStructTypeHash,
            uint256(1),
            stxItemHashes,
            superTxHashSignature,
            uint256((uint256(lowerBoundTimestamp) << 128) | uint256(upperBoundTimestamp))
        );

        // ============ EXECUTE ON EACH CHAIN ============
        vm.chainId(CHAIN_1);
        uint256 counterBeforeChain1 = mockTargetChain1.counter();
        vm.startPrank(MEE_NODE_EXECUTOR_EOA, MEE_NODE_EXECUTOR_EOA);
        PackedUserOperation[] memory userOpArrayChain1 = new PackedUserOperation[](1);
        userOpArrayChain1[0] = signedUserOps[0];
        ENTRYPOINT.handleOps(userOpArrayChain1, payable(MEE_NODE_ADDRESS));
        vm.stopPrank();
        assertEq(mockTargetChain1.counter(), counterBeforeChain1 + 1, "Chain 1 execution failed");

        vm.chainId(CHAIN_2);
        uint256 counterBeforeChain2 = mockTargetChain2.counter();
        vm.startPrank(MEE_NODE_EXECUTOR_EOA, MEE_NODE_EXECUTOR_EOA);
        PackedUserOperation[] memory userOpArrayChain2 = new PackedUserOperation[](1);
        userOpArrayChain2[0] = signedUserOps[1];
        ENTRYPOINT.handleOps(userOpArrayChain2, payable(MEE_NODE_ADDRESS));
        vm.stopPrank();
        assertEq(mockTargetChain2.counter(), counterBeforeChain2 + 1, "Chain 2 execution failed");

        // Restore original chain ID
        vm.chainId(originalChainId);
    }
}
