// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { StxValidator_Base_Test } from "./StxValidator_Base_Test.t.sol";
import { Vm } from "forge-std/Test.sol";
import { PackedUserOperation } from "account-abstraction/core/UserOperationLib.sol";
import { MockERC20PermitToken } from "test/mock/tokens/MockERC20PermitToken.sol";
import { ERC1271_SUCCESS } from "contracts/types/Constants.sol";
import { MerkleTreeLib } from "solady/utils/MerkleTreeLib.sol";
import { EcdsaHelperLib } from "contracts/lib/util/EcdsaHelperLib.sol";
import {
    DecodedErc20PermitSig,
    DecodedErc20PermitSigShort,
    PERMIT_TYPEHASH,
    PermitSubmodule
} from "contracts/validators/stx-validator/submodules/PermitSubmodule.sol";
import { CopyUserOpLib } from "../../util/CopyUserOpLib.sol";

contract StxValidator_Permit_Mode_Test is StxValidator_Base_Test {
    using CopyUserOpLib for PackedUserOperation;
    using MerkleTreeLib for bytes32[];

    // make token storage var to reduce stack size in some methods by not passing it as a param
    // do not forget to reinit it at every test if required
    MockERC20PermitToken token;
    PermitSubmodule internal permitSubmodule;

    function setUp() public virtual override {
        super.setUp();

        // deploy permit submodule and use it with the default config
        permitSubmodule = new PermitSubmodule();
        vm.prank(address(mockAccount));
        // set the default config
        stxValidator.onInstall(
            abi.encodePacked(
                address(permitSubmodule), address(eoaStatelessValidator), uint8(0), abi.encodePacked(wallet.addr)
            )
        );
    }

    function test_StxValidator_permit_mode_ValidateUserOp_success(uint256 numOfClones) public {
        numOfClones = bound(numOfClones, 1, 25);
        token = new MockERC20PermitToken("test", "TEST");
        deal(address(token), wallet.addr, 1000 ether); // mint erc20 tokens to the wallet
        address bob = address(0xb0bb0b);
        assertEq(token.balanceOf(bob), 0);
        uint256 amountToTransfer = 1 ether;

        // userOps will transfer tokens from wallet, not from mockAccount
        // because of permit applies in the first userop validation
        bytes memory innerCallData =
            abi.encodeWithSelector(token.transferFrom.selector, wallet.addr, bob, amountToTransfer);

        PackedUserOperation memory userOp = buildBasicMEEUserOpWithCalldata({
            callData: abi.encodeWithSelector(mockAccount.execute.selector, address(token), uint256(0), innerCallData),
            account: address(mockAccount),
            userOpSigner: wallet
        });

        PackedUserOperation[] memory userOps = _cloneUserOpToAnArray(userOp, wallet, numOfClones);

        userOps = _makePermitSuperTx({
            userOps: userOps, signer: wallet, spender: address(mockAccount), amount: amountToTransfer * userOps.length
        });

        vm.startPrank(MEE_NODE_EXECUTOR_EOA, MEE_NODE_EXECUTOR_EOA);
        ENTRYPOINT.handleOps(userOps, payable(MEE_NODE_ADDRESS));
        vm.stopPrank();

        assertEq(token.balanceOf(bob), amountToTransfer * numOfClones + 1e18);
    }

    function test_StxValidator_permit_mode_ERC1271_ERC7739_success(uint256 numOfObjs) public {
        numOfObjs = bound(numOfObjs, 2, 25);
        token = new MockERC20PermitToken("test", "TEST"); // deploy fresh token
        bytes[] memory meeSigs = new bytes[](numOfObjs);
        bytes32 baseHash = keccak256(abi.encode("test"));

        meeSigs = _makePermitSuperTxSignatures({
            baseHash: baseHash, total: numOfObjs, signer: wallet, spender: address(mockAccount), amount: 1e18
        });

        for (uint256 i; i < numOfObjs; i++) {
            bytes32 dataHash = keccak256(abi.encode(baseHash, i)); // expect every hash to be different
            assertTrue(mockAccount.isValidSignature(dataHash, meeSigs[i]) == ERC1271_SUCCESS);
        }
    }

    function test_StxValidator_permit_mode_ERC7780_success(uint256 numOfObjs) public {
        numOfObjs = bound(numOfObjs, 2, 25);
        token = new MockERC20PermitToken("test", "TEST"); // deploy fresh token
        bytes[] memory meeSigs = new bytes[](numOfObjs);
        bytes32 baseHash = keccak256(abi.encode("test"));

        bytes memory validationDataForStatelessValidator = abi.encodePacked(wallet.addr);
        bytes memory data = abi.encode(
            address(mockAccount), // account
            address(permitSubmodule), // stx mode verifier address
            address(eoaStatelessValidator), // stateless validator address
            validationDataForStatelessValidator // validation data for stateless validator
        );

        meeSigs = _makePermitSuperTxSignaturesForErc7780Flow({
            baseHash: baseHash, total: numOfObjs, signer: wallet, spender: address(mockAccount), amount: 1e18
        });

        for (uint256 i; i < numOfObjs; i++) {
            bytes32 includedLeafHash = keccak256(abi.encode(baseHash, i)); // expect every hash to be different
            assertTrue(mockAccount.validateSignatureWithData(includedLeafHash, meeSigs[i], data));
        }
    }
    // ==== PERMIT SUPER TX UTILS ====

    function _makePermitSuperTx(
        PackedUserOperation[] memory userOps,
        Vm.Wallet memory signer,
        address spender,
        uint256 amount
    )
        internal
        view
        returns (PackedUserOperation[] memory)
    {
        PackedUserOperation[] memory superTxUserOps = new PackedUserOperation[](userOps.length);
        uint48 lowerBoundTimestamp = uint48(block.timestamp);
        uint48 upperBoundTimestamp = uint48(block.timestamp + 1000);
        bytes32[] memory leaves = _buildLeavesOutOfUserOps(userOps, lowerBoundTimestamp, upperBoundTimestamp);
        (userOps, lowerBoundTimestamp, upperBoundTimestamp);

        // make a tree
        bytes32[] memory tree = leaves.build();
        bytes32 root = tree.root();

        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_TYPEHASH,
                signer.addr,
                spender,
                amount,
                token.nonces(signer.addr), //nonce
                //root //we use deadline field to store the super tx root hash
                root
            )
        );

        bytes32 dataHashToSign = EcdsaHelperLib.toTypedDataHash(token.DOMAIN_SEPARATOR(), structHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer.privateKey, dataHashToSign);

        for (uint256 i = 0; i < userOps.length; i++) {
            superTxUserOps[i] = userOps[i].deepCopy();
            bytes32[] memory proof = tree.leafProof(i);

            bytes memory signature = abi.encode(
                DecodedErc20PermitSig({
                    token: token,
                    owner: signer.addr,
                    spender: spender,
                    domainSeparator: token.DOMAIN_SEPARATOR(),
                    amount: amount,
                    nonce: token.nonces(signer.addr),
                    isPermitTx: i == 0 ? true : false,
                    superTxHash: root,
                    lowerBoundTimestamp: lowerBoundTimestamp,
                    upperBoundTimestamp: upperBoundTimestamp,
                    signature: abi.encodePacked(r, s, v),
                    proof: proof
                })
            );

            superTxUserOps[i].signature = signature;
        }
        return superTxUserOps;
    }

    function _makePermitSuperTxSignatures(
        bytes32 baseHash,
        uint256 total,
        Vm.Wallet memory signer,
        address spender,
        uint256 amount
    )
        internal
        view
        returns (bytes[] memory)
    {
        return _makePermitSuperTxSignaturesInternal(baseHash, total, signer, spender, amount, true);
    }

    function _makePermitSuperTxSignaturesForErc7780Flow(
        bytes32 baseHash,
        uint256 total,
        Vm.Wallet memory signer,
        address spender,
        uint256 amount
    )
        internal
        view
        returns (bytes[] memory)
    {
        return _makePermitSuperTxSignaturesInternal(baseHash, total, signer, spender, amount, false);
    }

    function _makePermitSuperTxSignaturesInternal(
        bytes32 baseHash,
        uint256 total,
        Vm.Wallet memory signer,
        address spender,
        uint256 amount,
        bool addRehashing
    )
        internal
        view
        returns (bytes[] memory)
    {
        bytes[] memory meeSigs = new bytes[](total);

        bytes32[] memory leaves = new bytes32[](total);

        for (uint256 i = 0; i < total; i++) {
            if (addRehashing) {
                // spender is the smart account address in this case
                leaves[i] = keccak256(abi.encodePacked(keccak256(abi.encode(baseHash, i)), spender, block.chainid));
            } else {
                leaves[i] = keccak256(abi.encode(baseHash, i));
            }
        }

        bytes32[] memory tree = leaves.build();
        bytes32 root = tree.root();

        bytes32 permitStructHash = keccak256(
            abi.encode(
                PERMIT_TYPEHASH,
                signer.addr,
                spender,
                amount,
                token.nonces(signer.addr), //nonce
                root //we use deadline field to store the super tx root hash
            )
        ); // permit struct hash

        bytes32 dataHashToSign = EcdsaHelperLib.toTypedDataHash(token.DOMAIN_SEPARATOR(), permitStructHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer.privateKey, dataHashToSign);

        for (uint256 i = 0; i < total; i++) {
            bytes32[] memory proof = tree.leafProof(i);
            bytes memory signature = abi.encode(
                DecodedErc20PermitSigShort({
                    owner: signer.addr,
                    spender: spender,
                    domainSeparator: token.DOMAIN_SEPARATOR(),
                    amount: amount,
                    nonce: token.nonces(signer.addr),
                    superTxHash: root,
                    signature: abi.encodePacked(r, s, v),
                    proof: proof
                })
            );
            meeSigs[i] = signature;
        }
        return meeSigs;
    }
}
