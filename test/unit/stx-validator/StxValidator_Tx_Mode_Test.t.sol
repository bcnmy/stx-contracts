import { StxValidator_Base_Test } from "./StxValidator_Base_Test.t.sol";
import { Vm } from "forge-std/Test.sol";
import { PackedUserOperation } from "account-abstraction/core/UserOperationLib.sol";
import { MockERC20PermitToken } from "test/mock/tokens/MockERC20PermitToken.sol";
import { ERC1271_SUCCESS } from "contracts/types/Constants.sol";
import { CopyUserOpLib } from "../../util/CopyUserOpLib.sol";
import { MerkleTreeLib } from "solady/utils/MerkleTreeLib.sol";
import { SIG_TYPE_ON_CHAIN } from "contracts/types/Constants.sol";
import { LibRLP } from "solady/utils/LibRLP.sol";
import { MockTarget } from "../../mock/MockTarget.sol";
import { TxSubmodule } from "../../../contracts/validators/stx-validator/submodules/TxSubmodule.sol";

contract StxValidator_Tx_Mode_Test is StxValidator_Base_Test {
    using CopyUserOpLib for PackedUserOperation;
    using LibRLP for LibRLP.List;
    using MerkleTreeLib for bytes32[];

    TxSubmodule internal txSubmodule;
    MockERC20PermitToken internal token;

    function setUp() public virtual override {
        super.setUp();

        txSubmodule = new TxSubmodule();
        vm.prank(address(mockAccount));
        stxValidator.onInstall(
            abi.encodePacked(
                address(txSubmodule), address(eoaStatelessValidator), uint8(0), abi.encodePacked(wallet.addr)
            )
        );
    }

    function test_StxValidator_tx_mode_ValidateUserOp_success(uint256 numOfClones) public {
        numOfClones = bound(numOfClones, 1, 25);
        token = new MockERC20PermitToken("test", "TEST");
        deal(address(token), wallet.addr, 1000 ether); // mint erc20 tokens to the wallet
        address bob = address(0xb0bb0b);
        assertEq(token.balanceOf(bob), 0);
        uint256 amountToTransfer = 1 ether;

        bytes memory innerCallData = abi.encodeWithSelector(token.transfer.selector, bob, amountToTransfer); // mock
        // Account transfers tokens to bob
        PackedUserOperation memory userOp = buildBasicMEEUserOpWithCalldata({
            callData: abi.encodeWithSelector(mockAccount.execute.selector, address(token), uint256(0), innerCallData),
            account: address(mockAccount),
            userOpSigner: wallet
        });

        PackedUserOperation[] memory userOps = _cloneUserOpToAnArray(userOp, wallet, numOfClones);

        // simulate the txn execution
        vm.startPrank(wallet.addr);
        token.transfer(address(mockAccount), amountToTransfer * (numOfClones + 1));
        vm.stopPrank();

        // it is not possible to get the actual executed and serialized txn (above) from Foundry tests
        // so this is just some calldata for testing purposes
        bytes memory callData =
            hex"a9059cbb000000000000000000000000c7183455a4c133ae270771860664b6b7ec320bb100000000000000000000000000000000000000000000000053444835ec580000";

        userOps = _makeOnChainTxnSuperTx(userOps, wallet, callData);

        vm.startPrank(MEE_NODE_EXECUTOR_EOA, MEE_NODE_EXECUTOR_EOA);
        ENTRYPOINT.handleOps(userOps, payable(MEE_NODE_ADDRESS));
        vm.stopPrank();

        assertEq(token.balanceOf(bob), amountToTransfer * (numOfClones + 1));
    }

    function test_StxValidator_tx_mode_ERC1271_withSecuredHash_success(uint256 numOfObjs) public {
        numOfObjs = bound(numOfObjs, 2, 25);
        bytes[] memory meeSigs = new bytes[](numOfObjs);
        bytes32 baseHash = keccak256(abi.encode("test"));
        bytes memory callData = abi.encodeWithSelector(MockTarget.incrementCounter.selector);

        meeSigs = _makeOnchainTxSuperTxSignatures1271Flow({
            baseHash: baseHash,
            total: numOfObjs,
            callData: callData,
            superTxSigner: wallet,
            smartAccount: address(mockAccount)
        });

        for (uint256 i; i < numOfObjs; i++) {
            bytes32 includedLeafHash = keccak256(abi.encode(baseHash, i)); // expect every hash to be different
            assertTrue(mockAccount.isValidSignature(includedLeafHash, meeSigs[i]) == ERC1271_SUCCESS);
        }
    }

    function test_StxValidator_tx_mode_ERC7780_success(uint256 numOfObjs) public {
        numOfObjs = bound(numOfObjs, 2, 25);
        bytes[] memory meeSigs = new bytes[](numOfObjs);
        bytes32 baseHash = keccak256(abi.encode("test"));
        bytes memory callData = abi.encodeWithSelector(MockTarget.incrementCounter.selector);

        meeSigs = _makeOnchainTxSuperTxSignaturesForErc7780Flow({
            baseHash: baseHash,
            total: numOfObjs,
            callData: callData,
            superTxSigner: wallet,
            smartAccount: address(mockAccount)
        });

        bytes memory validationDataForStatelessValidator = abi.encodePacked(wallet.addr);
        bytes memory data = abi.encode(
            address(mockAccount), // account
            address(txSubmodule), // stx mode verifier address
            address(eoaStatelessValidator), // stateless validator address
            validationDataForStatelessValidator // validation data for stateless validator
        );

        for (uint256 i; i < numOfObjs; i++) {
            bytes32 includedLeafHash = keccak256(abi.encode(baseHash, i)); // expect every hash to be different
            assertTrue(mockAccount.validateSignatureWithData(includedLeafHash, meeSigs[i], data));
        }
    }
    // =============================================================

    function _makeOnChainTxnSuperTx(
        PackedUserOperation[] memory userOps,
        Vm.Wallet memory superTxSigner,
        bytes memory callData
    )
        internal
        view
        returns (PackedUserOperation[] memory)
    {
        PackedUserOperation[] memory superTxUserOps = new PackedUserOperation[](userOps.length);
        uint48 lowerBoundTimestamp = uint48(block.timestamp);
        uint48 upperBoundTimestamp = uint48(block.timestamp + 1000);
        bytes32[] memory leaves = _buildLeavesOutOfUserOps(userOps, lowerBoundTimestamp, upperBoundTimestamp);

        // make a tree
        bytes32[] memory tree = leaves.build();
        bytes32 root = tree.root();

        callData = abi.encodePacked(callData, root);

        bytes memory serializedTx = _getSerializedTxn(callData, address(0xa11cebeefb0bdecaf0), superTxSigner);

        for (uint256 i = 0; i < userOps.length; i++) {
            superTxUserOps[i] = userOps[i].deepCopy();
            bytes32[] memory proof = tree.leafProof(i);
            bytes memory signature = abi.encodePacked(
                serializedTx, abi.encodePacked(proof), uint8(proof.length), lowerBoundTimestamp, upperBoundTimestamp
            );
            superTxUserOps[i].signature = signature;
        }
        return superTxUserOps;
    }

    function _makeOnchainTxSuperTxSignatures1271Flow(
        bytes32 baseHash,
        uint256 total,
        bytes memory callData,
        Vm.Wallet memory superTxSigner,
        address smartAccount
    )
        internal
        view
        returns (bytes[] memory)
    {
        bytes[] memory meeSigs = new bytes[](total);
        require(total > 0, "total must be greater than 0");

        bytes32[] memory leaves = new bytes32[](total);

        for (uint256 i = 0; i < total; i++) {
            leaves[i] = keccak256(abi.encodePacked(keccak256(abi.encode(baseHash, i)), smartAccount, block.chainid));
        }

        bytes32[] memory tree = leaves.build();
        return _makeOnchainTxSuperTxSignatures(total, callData, superTxSigner, tree);
    }

    function _makeOnchainTxSuperTxSignaturesForErc7780Flow(
        bytes32 baseHash,
        uint256 total,
        bytes memory callData,
        Vm.Wallet memory superTxSigner,
        address smartAccount
    )
        internal
        view
        returns (bytes[] memory)
    {
        bytes[] memory meeSigs = new bytes[](total);
        require(total > 0, "total must be greater than 0");

        bytes32[] memory leaves = new bytes32[](total);

        // no need to hash smart account address in case of erc-7780
        for (uint256 i = 0; i < total; i++) {
            leaves[i] = keccak256(abi.encode(baseHash, i));
        }

        bytes32[] memory tree = leaves.build();
        return _makeOnchainTxSuperTxSignatures(total, callData, superTxSigner, tree);
    }

    function _makeOnchainTxSuperTxSignatures(
        uint256 total,
        bytes memory callData,
        Vm.Wallet memory superTxSigner,
        bytes32[] memory tree
    )
        internal
        view
        returns (bytes[] memory)
    {
        bytes[] memory meeSigs = new bytes[](total);
        bytes32 root = tree.root();
        callData = abi.encodePacked(callData, root);

        bytes memory serializedTx = _getSerializedTxn(callData, address(0xa11cebeefb0bdecaf0), superTxSigner);

        for (uint256 i = 0; i < total; i++) {
            bytes32[] memory proof = tree.leafProof(i);
            bytes memory signature = abi.encodePacked(serializedTx, abi.encodePacked(proof), uint8(proof.length));
            meeSigs[i] = signature;
        }
        return meeSigs;
    }

    function _getSerializedTxn(
        bytes memory txnData, // calldata + root
        address to,
        Vm.Wallet memory signer
    )
        internal
        view
        returns (bytes memory)
    {
        LibRLP.List memory accessList = LibRLP.p();

        LibRLP.List memory serializedTxList = LibRLP.p(block.chainid).p(0).p(uint256(1)).p(uint256(20))
            .p(uint256(50_000)).p(to).p(uint256(0)).p(txnData) // chainId
            // nonce
            // maxPriorityFeePerGas
            // maxFeePerGas
            // gasLimit
            // to
            // value
            // txn data
            .p(accessList); // empty access list

        bytes32 uTxHash = keccak256(abi.encodePacked(hex"02", serializedTxList.encode()));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer.privateKey, uTxHash);

        serializedTxList = serializedTxList.p(v == 28 ? true : false).p(uint256(r)).p(uint256(s)); // add v, r, s to the
        // list
        return abi.encodePacked(hex"02", serializedTxList.encode()); // add tx type to the list
    }
}
