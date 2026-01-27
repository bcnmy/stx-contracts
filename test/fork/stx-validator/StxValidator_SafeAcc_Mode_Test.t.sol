// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Vm } from "forge-std/Test.sol";
import { StxValidator_Base_Test } from "../../unit/stx-validator/StxValidator_Base_Test.t.sol";
import { PackedUserOperation } from "account-abstraction/core/UserOperationLib.sol";
import { ISafe } from "contracts/interfaces/external/safe-smart-account/ISafe.sol";
import { SafeEnumLib } from "contracts/interfaces/external/safe-smart-account/SafeEnumLib.sol";
import { MockAccount } from "test/mock/accounts/MockAccount.sol";
import { MockERC20PermitToken } from "test/mock/tokens/MockERC20PermitToken.sol";
import { MockTarget } from "test/mock/MockTarget.sol";
import { StxValidator } from "contracts/validators/stx-validator/StxValidator.sol";
import { MerkleTreeLib } from "solady/utils/MerkleTreeLib.sol";
import { CopyUserOpLib } from "../../util/CopyUserOpLib.sol";
import {
    DecodedSafeAccountSignatureFull,
    DecodedSafeAccountSignatureShort,
    SafeTxnData,
    SafeAccountSubmodule
} from "contracts/validators/stx-validator/submodules/SafeAccountSubmodule.sol";
import { ERC1271_SUCCESS } from "contracts/types/Constants.sol";
import { console2 } from "forge-std/console2.sol";

contract StxValidator_SafeAcc_Mode_Test_Fork is StxValidator_Base_Test {
    using CopyUserOpLib for PackedUserOperation;
    using MerkleTreeLib for bytes32[];

    uint256 baseSepolia;
    uint256 sepolia;

    // StxValidator and MockTarget vars are created in the BaseTest contract
    MockAccount orchestrator;
    ISafe safe;

    // signers should be sorted!
    Vm.Wallet signer1; // 0x14dC79964da2C08b23698B3D3cc7Ca32193d9955 = anvil account
    Vm.Wallet signer2; // 0x531b827c1221EC7CE13266e8F5CB1ec6Ae470be5 = biconomy account
    Vm.Wallet signer3; // 0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc = anvil account

    MockERC20PermitToken erc20;
    SafeAccountSubmodule safeAccountSubmodule;

    address receiver = address(0xb0bb0b);
    uint256 amountToTransfer = 1 ether;

    function setUp() public virtual override {
        // create a fork of baseSepolia
        string memory baseSepoliaRpcUrl = vm.envString("RPC_84532");
        string memory sepoliaRpcUrl = vm.envString("RPC_11155111_TEST");
        baseSepolia = vm.createFork(baseSepoliaRpcUrl);
        sepolia = vm.createFork(sepoliaRpcUrl);

        // pre-deployed on both chains
        safe = ISafe(0x6D0Cc55Ac8F3d86e6e50de2d8eF06127d39B8Ab0);

        uint256 bicoPrivateKey = vm.envUint("TESTNET_PRIVATE_KEY");
        signer1 = vm.createWallet(uint256(0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356)); // 0x14dC79964da2C08b23698B3D3cc7Ca32193d9955
        signer2 = vm.createWallet(bicoPrivateKey); // 0x531b827c1221EC7CE13266e8F5CB1ec6Ae470be5
        signer3 = vm.createWallet(uint256(0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba)); // 0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc

        vm.label(signer1.addr, "signer1 anvil");
        vm.label(signer2.addr, "signer2 biconomy");
        vm.label(signer3.addr, "signer3 anvil");

        vm.selectFork(baseSepolia);
        _setupOrchestration();

        vm.selectFork(sepolia);
        _setupOrchestration();
    }

    function _setupOrchestration() internal {
        super.setUp();

        // ensures consistent addresses for the contracts
        // since they are deployed with CREATE thus addresses depend on the nonce
        vm.startPrank(address(0xa11ce));
        stxValidator = new StxValidator();
        safeAccountSubmodule = new SafeAccountSubmodule();
        orchestrator = deployMockAccount({ validator: address(stxValidator), handler: address(0) });
        mockTarget = new MockTarget();
        erc20 = new MockERC20PermitToken("test", "TEST");
        vm.stopPrank();

        // Install StxValidator config for orchestrator
        // SafeAccountSubmodule implements both IStxModeVerifier and IStatelessValidator
        // so we pass address(0) as statelessValidatorAddress (it will use stxModeVerifierAddress)
        // validationData contains: safe account address + smart account address
        vm.prank(address(orchestrator));
        stxValidator.onInstall(
            abi.encodePacked(
                address(safeAccountSubmodule), // stxModeVerifier
                address(0), // statelessValidator (use stxModeVerifier since SafeAccountSubmodule implements both)
                uint8(0), // no safe senders
                abi.encodePacked(address(safe), address(orchestrator)) // validationData: safeAccount + smartAccount
            )
        );

        vm.deal(address(safe), 100 ether);
        vm.deal(address(orchestrator), 100 ether);
        vm.deal(signer1.addr, 100 ether);
        vm.deal(signer2.addr, 100 ether);
        vm.deal(signer3.addr, 100 ether);

        deal(address(erc20), address(safe), 100 ether);

        //make sure initial balance of receiver is 0
        assertEq(erc20.balanceOf(receiver), 0);
    }

    function test_StxValidator_superTxFlow_safeAcc_mode_ValidateUserOp_success(uint256 numOfClones) public {
        numOfClones = bound(numOfClones, 1, 25);

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

        Vm.Wallet[] memory signers = _getSigners();

        // transfer required amount of tokens to the orchestrator
        bytes memory safeTxnCalldata = abi.encodeWithSelector(
            erc20.transfer.selector, address(orchestrator), amountToTransfer * (numOfClones + 1)
        );

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

    function test_StxValidator_superTxFlow_safeAcc_mode_7780_success(uint256 numOfObjs) public {
        numOfObjs = bound(numOfObjs, 2, 25);

        (bytes[] memory meeSigs, bytes32 baseHash) = _prepareDataFor7780Or1271(false, numOfObjs);

        bytes memory validationData = abi.encode(
            address(orchestrator), // account
            address(safeAccountSubmodule), // stx mode verifier address
            address(safeAccountSubmodule), // stateless validator (use stx mode verifier since SafeAccountSubmodule
            // implements both)
            abi.encodePacked(address(safe), address(orchestrator)) // validationData: safeAccount + smartAccount
        );

        vm.selectFork(baseSepolia);
        for (uint256 i; i < numOfObjs; i++) {
            bytes32 includedLeafHash = keccak256(abi.encode(baseHash, i));
            // Test validateSignatureWithData (stateless validator interface)
            assertTrue(orchestrator.validateSignatureWithData(includedLeafHash, meeSigs[i], validationData));
        }

        vm.selectFork(sepolia);
        for (uint256 i; i < numOfObjs; i++) {
            bytes32 includedLeafHash = keccak256(abi.encode(baseHash, i));
            // Test validateSignatureWithData (stateless validator interface)
            assertTrue(orchestrator.validateSignatureWithData(includedLeafHash, meeSigs[i], validationData));
        }
    }

    function _prepareDataFor7780Or1271(bool addRehashing, uint256 numOfObjs) public returns (bytes[] memory, bytes32) {
        vm.selectFork(baseSepolia);
        bytes[] memory meeSigs = new bytes[](numOfObjs);
        bytes32 baseHash = keccak256(abi.encode("test"));

        meeSigs = _makeSafeAccSuperTxSignatures({
            baseHash: baseHash,
            total: numOfObjs,
            signers: _getSigners(),
            safeAccount: safe,
            safeTxnCalldata: abi.encodeWithSelector(erc20.transfer.selector, address(orchestrator), 1 ether),
            smartAccount: address(orchestrator),
            addRehashing: addRehashing
        });

        return (meeSigs, baseHash);
    }

    // ================================ UTILS ================================

    function _getSigners() internal view returns (Vm.Wallet[] memory) {
        Vm.Wallet[] memory signers = new Vm.Wallet[](3);
        signers[0] = signer1;
        signers[1] = signer2;
        signers[2] = signer3;
        return signers;
    }

    function _makeSafeAccSuperTx(
        PackedUserOperation[] memory userOps,
        Vm.Wallet[] memory signers,
        ISafe safeAccount,
        bytes memory safeTxnCalldata
    )
        internal
        returns (PackedUserOperation[] memory)
    {
        // setting fixed timestamps
        // because block.timestamp turned out to be not deterministic in the multifork environment
        uint48 lowerBoundTimestamp = 0;
        uint48 upperBoundTimestamp = 2_763_994_636;

        bytes32[] memory leaves = new bytes32[](userOps.length);

        // We have to switch forks because building leaves involves getting the userOpHash, which is chain specific
        {
            uint256 halfLength = userOps.length / 2;

            // base sepolia
            vm.selectFork(baseSepolia);
            bytes32[] memory leaves_baseSepolia =
                _buildLeavesOutOfUserOps(userOps, lowerBoundTimestamp, upperBoundTimestamp);

            // sepolia
            vm.selectFork(sepolia);
            bytes32[] memory leaves_sepolia =
                _buildLeavesOutOfUserOps(userOps, lowerBoundTimestamp, upperBoundTimestamp);

            // combine the leaves
            // we take only the first half of the leaves from base sepolia
            // and the second half from sepolia
            // because they are build with appropriate chain id for each chain
            for (uint256 i = 0; i < halfLength; i++) {
                leaves[i] = leaves_baseSepolia[i];
            }
            for (uint256 i = halfLength; i < userOps.length; i++) {
                leaves[i] = leaves_sepolia[i];
            }
        }

        // make a tree
        bytes32[] memory tree = leaves.build();
        bytes32 root = tree.root();

        // we need those params for the source chain
        // so => switch to the base sepolia fork
        vm.selectFork(baseSepolia);
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

        // current fork is base sepolia
        // we are signing for the source chain
        // which is base sepolia, so the safe txn hash should be built on the base sepolia fork
        // since it is also chain specific
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

            // StxValidator signature format: no SIG_TYPE prefix, just abi.encode the struct
            // DecodedSafeAccountSignatureFull includes safeAccount address as first field
            bytes memory signature = abi.encode(
                DecodedSafeAccountSignatureFull({
                    safeAccount: address(safe),
                    safeTxnData: safeTxnData,
                    proof: proof,
                    executeTrigger: i == 0 ? true : false, // only the first userOp on the first chain should
                    // execute the safe transaction
                    lowerBoundTimestamp: lowerBoundTimestamp,
                    upperBoundTimestamp: upperBoundTimestamp
                })
            );
            superTxUserOps[i].signature = signature;
        }
        return superTxUserOps;
    }

    function _makeSafeAccSuperTxSignatures(
        bytes32 baseHash,
        uint256 total,
        Vm.Wallet[] memory signers,
        ISafe safeAccount,
        bytes memory safeTxnCalldata,
        address smartAccount,
        bool addRehashing
    )
        internal
        view
        returns (bytes[] memory)
    {
        bytes[] memory meeSigs = new bytes[](total);
        require(total > 0, "total must be greater than 0");

        bytes32[] memory leaves = new bytes32[](total);

        for (uint256 i; i < total; i++) {
            if (addRehashing) {
                leaves[i] = keccak256(abi.encodePacked(keccak256(abi.encode(baseHash, i)), smartAccount));
            } else {
                leaves[i] = keccak256(abi.encode(baseHash, i));
            }
        }

        // Build merkle tree
        bytes32[] memory tree = leaves.build();
        bytes32 root = tree.root();

        // Get Safe transaction parameters
        uint256 curNonce = safeAccount.nonce();
        bytes32 domainSeparator = safeAccount.domainSeparator();

        // Add the super tx root hash to the data
        safeTxnCalldata = abi.encodePacked(safeTxnCalldata, root);

        bytes memory signatures = "";
        {
            // Get safe transaction hash
            bytes32 safeTxHash = ISafe(safeAccount)
                .getTransactionHash({
                    to: address(erc20),
                    value: 0,
                    data: safeTxnCalldata,
                    operation: SafeEnumLib.Operation.Call,
                    safeTxGas: 0,
                    baseGas: 0,
                    gasPrice: 0,
                    gasToken: address(0),
                    refundReceiver: payable(address(0)),
                    _nonce: curNonce
                });

            // Sign with all safe signers
            for (uint256 i = 0; i < signers.length; i++) {
                (uint8 v, bytes32 r, bytes32 s) = vm.sign(signers[i].privateKey, safeTxHash);
                signatures = abi.encodePacked(signatures, r, s, v);
            }
        }

        // Encode signatures for each leaf
        for (uint256 i; i < total; i++) {
            bytes32[] memory proof = tree.leafProof(i);
            bytes memory signature = abi.encode(
                DecodedSafeAccountSignatureShort({
                    safeTxnData: SafeTxnData({
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
                        signatures: signatures
                    }),
                    proof: proof
                })
            );
            meeSigs[i] = signature;
        }
        return meeSigs;
    }
}
