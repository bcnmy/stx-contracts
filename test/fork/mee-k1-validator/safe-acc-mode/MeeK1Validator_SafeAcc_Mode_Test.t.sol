// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Vm } from "forge-std/Test.sol";
import { MeeK1Validator_Base_Test } from "../../../unit/mee-k1-validator/MeeK1Validator_Base_Test.t.sol";
import { PackedUserOperation } from "account-abstraction/core/UserOperationLib.sol";
import { ISafe } from "contracts/interfaces/external/safe-smart-account/ISafe.sol";
import { SafeEnumLib } from "contracts/interfaces/external/safe-smart-account/SafeEnumLib.sol";
import { MockAccount } from "test/mock/accounts/MockAccount.sol";
import { MockERC20PermitToken } from "test/mock/tokens/MockERC20PermitToken.sol";
import { MockTarget } from "test/mock/MockTarget.sol";
import { K1MeeValidator } from "contracts/validators/stx-validator/K1MeeValidator.sol";
import { MerkleTreeLib } from "solady/utils/MerkleTreeLib.sol";
import { CopyUserOpLib } from "../../../util/CopyUserOpLib.sol";
import {
    DecodedSafeAccountSignatureFull,
    SafeTxnData
} from "contracts/lib/stx-validator/validation-modes/SafeAccountValidatorLib.sol";
import { SIG_TYPE_SAFE_ACCOUNT } from "contracts/types/Constants.sol";
import { console2 } from "forge-std/console2.sol";

contract MeeK1Validator_SafeAcc_Mode_Test_Fork is MeeK1Validator_Base_Test {
    using CopyUserOpLib for PackedUserOperation;
    using MerkleTreeLib for bytes32[];

    uint256 baseSepolia;
    uint256 sepolia;

    // K1MeeValidator and MockTarget vars are created in the BaseTest contract
    MockAccount orchestrator;
    ISafe safe;

    Vm.Wallet signer1; // 0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc = anvil account
    Vm.Wallet signer2; // 0x14dC79964da2C08b23698B3D3cc7Ca32193d9955 = anvil account
    Vm.Wallet signer3; // 0x531b827c1221EC7CE13266e8F5CB1ec6Ae470be5 = biconomy account

    MockERC20PermitToken erc20;

    address receiver = address(0xb0bb0b);
    uint256 amountToTransfer = 1 ether;

    function setUp() public virtual override {
        // create a fork of baseSepolia
        string memory baseSepoliaRpcUrl = vm.envString("RPC_84532");
        string memory sepoliaRpcUrl = vm.envString("RPC_11155111_TEST");
        baseSepolia = vm.createFork(baseSepoliaRpcUrl);
        sepolia = vm.createFork(sepoliaRpcUrl);

        safe = ISafe(0x6D0Cc55Ac8F3d86e6e50de2d8eF06127d39B8Ab0);

        uint256 bicoPrivateKey = vm.envUint("TESTNET_PRIVATE_KEY");
        signer1 = vm.createWallet(uint256(0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba));
        signer2 = vm.createWallet(uint256(0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356));
        signer3 = vm.createWallet(bicoPrivateKey);

        vm.label(signer1.addr, "signer1");
        vm.label(signer2.addr, "signer2");
        vm.label(signer3.addr, "signer3");

        vm.selectFork(baseSepolia);
        _setupOrchestration();

        vm.selectFork(sepolia);
        _setupOrchestration();
    }

    function _setupOrchestration() internal {
        super.setUp();

        k1MeeValidator = new K1MeeValidator();
        // ensures consistent address for orchestrator since it is deployed with create and depends on the nonce
        vm.prank(address(0xa11ce));
        orchestrator = deployMockAccount({ validator: address(k1MeeValidator), handler: address(0) });

        vm.prank(address(mockAccount));
        k1MeeValidator.transferOwnership(address(safe));

        mockTarget = new MockTarget();

        vm.deal(address(safe), 100 ether);
        vm.deal(address(orchestrator), 100 ether);
        vm.deal(signer1.addr, 100 ether);
        vm.deal(signer2.addr, 100 ether);
        vm.deal(signer3.addr, 100 ether);

        erc20 = new MockERC20PermitToken("test", "TEST");
        deal(address(erc20), address(safe), 100 ether);

        //make sure initial balance of receiver is 0
        assertEq(erc20.balanceOf(receiver), 0);
    }

    function test_superTxFlow_safeAcc_mode_ValidateUserOp_success() public {
        // create user Ops on each chain to transfer tokens to receiver

        uint256 numOfClones = 5;

        bytes memory innerCallData = abi.encodeWithSelector(erc20.transfer.selector, receiver, amountToTransfer);

        vm.selectFork(baseSepolia);
        PackedUserOperation memory userOp_baseSepolia = buildBasicMEEUserOpWithCalldata({
            callData: abi.encodeWithSelector(orchestrator.execute.selector, address(erc20), uint256(0), innerCallData),
            account: address(orchestrator),
            userOpSigner: wallet
        });

        PackedUserOperation[] memory userOps_baseSepolia =
            _cloneUserOpToAnArray(userOp_baseSepolia, wallet, numOfClones);

        vm.selectFork(sepolia);

        PackedUserOperation memory userOp_sepolia = buildBasicMEEUserOpWithCalldata({
            callData: abi.encodeWithSelector(orchestrator.execute.selector, address(erc20), uint256(0), innerCallData),
            account: address(orchestrator),
            userOpSigner: wallet
        });

        PackedUserOperation[] memory userOps_sepolia = _cloneUserOpToAnArray(userOp_sepolia, wallet, numOfClones);

        // create a joint array of userOps
        PackedUserOperation[] memory userOps =
            new PackedUserOperation[](userOps_baseSepolia.length + userOps_sepolia.length);
        for (uint256 i = 0; i < userOps_baseSepolia.length; i++) {
            userOps[i] = userOps_baseSepolia[i].deepCopy();
        }
        for (uint256 i = 0; i < userOps_sepolia.length; i++) {
            userOps[userOps_baseSepolia.length + i] = userOps_sepolia[i].deepCopy();
        }

        Vm.Wallet[] memory signers = new Vm.Wallet[](3);
        signers[0] = signer1;
        signers[1] = signer2;
        signers[2] = signer3;

        // transfer required amount of tokens to the orchestrator
        bytes memory safeTxnCalldata =
            abi.encodeWithSelector(erc20.transfer.selector, address(orchestrator), amountToTransfer * (numOfClones + 1));

        PackedUserOperation[] memory safeOps = _makeSafeAccSuperTx(userOps, signers, safe, safeTxnCalldata);

        // on the origin chain, the safe txn should be transferring funds from the safe to the orchestrator
        // or it can be approving the orchestrator to spend tokens from the safe
        vm.selectFork(baseSepolia);
        for (uint256 i = 0; i < userOps_baseSepolia.length; i++) {
            //handleOps
            PackedUserOperation[] memory userOpToHandleAsArray = new PackedUserOperation[](1);
            userOpToHandleAsArray[0] = safeOps[i];
            vm.startPrank(MEE_NODE_EXECUTOR_EOA, MEE_NODE_EXECUTOR_EOA);
            ENTRYPOINT.handleOps(userOpToHandleAsArray, payable(MEE_NODE_ADDRESS));
            vm.stopPrank();
        }
        assertEq(erc20.balanceOf(receiver), amountToTransfer * (numOfClones + 1));

        vm.selectFork(sepolia);
        // emulate some cross-chain stuff that sends funds to the orchestrator on the sepolia chain
        deal(address(erc20), address(orchestrator), 100 ether);
        for (uint256 i = 0; i < userOps_sepolia.length; i++) {
            //handleOps
            PackedUserOperation[] memory userOpToHandleAsArray = new PackedUserOperation[](1);
            userOpToHandleAsArray[0] = safeOps[userOps_baseSepolia.length + i];
            vm.startPrank(MEE_NODE_EXECUTOR_EOA, MEE_NODE_EXECUTOR_EOA);
            ENTRYPOINT.handleOps(userOpToHandleAsArray, payable(MEE_NODE_ADDRESS));
            vm.stopPrank();
        }
        assertEq(erc20.balanceOf(receiver), amountToTransfer * (numOfClones + 1));
    }

    // ================================ UTILS ================================

    function _makeSafeAccSuperTx(
        PackedUserOperation[] memory userOps,
        Vm.Wallet[] memory signers,
        ISafe safeAccount,
        bytes memory safeTxnCalldata
    )
        internal
        returns (PackedUserOperation[] memory)
    {
        uint48 lowerBoundTimestamp = uint48(block.timestamp);
        uint48 upperBoundTimestamp = uint48(block.timestamp + 1000);
        bytes32[] memory leaves = _buildLeavesOutOfUserOps(userOps, lowerBoundTimestamp, upperBoundTimestamp);

        // make a tree
        bytes32[] memory tree = leaves.build();
        bytes32 root = tree.root();

        uint256 curNonce = safeAccount.nonce();
        bytes32 domainSeparator = safeAccount.domainSeparator();

        // create safe txn
        SafeTxnData memory safeTxnData = SafeTxnData({
            ogDomainSeparator: domainSeparator,
            to: address(erc20),
            value: 0,
            data: safeTxnCalldata,
            operation: SafeEnumLib.Operation.Call,
            safeTxGas: 0,
            baseGas: 0,
            gasPrice: 0,
            gasToken: address(0),
            refundReceiver: payable(address(0)),
            nonce: curNonce,
            signatures: ""
        });

        // add the super tx root hash to the data
        safeTxnData.data = abi.encodePacked(safeTxnData.data, root);

        vm.selectFork(baseSepolia);
        bytes32 safeTxHash = ISafe(safe)
            .getTransactionHash({
                to: safeTxnData.to,
                value: safeTxnData.value,
                data: safeTxnData.data,
                operation: safeTxnData.operation,
                safeTxGas: safeTxnData.safeTxGas,
                baseGas: safeTxnData.baseGas,
                gasPrice: safeTxnData.gasPrice,
                gasToken: safeTxnData.gasToken,
                refundReceiver: safeTxnData.refundReceiver,
                _nonce: safeTxnData.nonce
            });

        // sign this hash with each of the safe signers
        for (uint256 i = 0; i < signers.length; i++) {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(signers[i].privateKey, safeTxHash);
            safeTxnData.signatures = abi.encodePacked(safeTxnData.signatures, r, s, v);
        }

        // build the userOps
        PackedUserOperation[] memory superTxUserOps = new PackedUserOperation[](userOps.length);
        for (uint256 i = 0; i < userOps.length; i++) {
            superTxUserOps[i] = userOps[i].deepCopy();
            bytes32[] memory proof = tree.leafProof(i);
            bytes memory signature = abi.encodePacked(
                SIG_TYPE_SAFE_ACCOUNT,
                abi.encode(
                    DecodedSafeAccountSignatureFull({
                        safeTxnData: safeTxnData,
                        proof: proof,
                        executeTrigger: i == 0 ? true : false, // only the first userOp on the first chain should
                        // execute the safe transaction
                        lowerBoundTimestamp: lowerBoundTimestamp,
                        upperBoundTimestamp: upperBoundTimestamp
                    })
                )
            );
            superTxUserOps[i].signature = signature;
        }
        return superTxUserOps;
    }
}
