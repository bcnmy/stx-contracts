// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { StxValidator_Base_Test } from "../StxValidator_Base_Test.t.sol";
import { Vm } from "forge-std/Test.sol";
import { PackedUserOperation } from "account-abstraction/interfaces/PackedUserOperation.sol";
import { MockTarget } from "../../../../mock/MockTarget.sol";
import {
    ERC1271_SUCCESS,
    SIG_TYPE_NO_STX_P256,
    SIG_TYPE_NO_STX_VANILLA_1271_P256
} from "contracts/types/Constants.sol";
import { EIP712 } from "solady/utils/EIP712.sol";

contract StxValidator_P256_StatelessValidator_Integration_Test is StxValidator_Base_Test {
    bytes32 internal constant APP_DOMAIN_SEPARATOR = 0xa1a044077d7677adbbfa892ded5390979b33993e0e2a457e3f974bbcda53821b;

    uint256 internal p256PublicKeyX;
    uint256 internal p256PublicKeyY;
    bytes internal validationData;

    function setUp() public virtual override {
        super.setUp();

        // create a p256 signer
        (p256PublicKeyX, p256PublicKeyY) = vm.publicKeyP256(wallet.privateKey);
        validationData = abi.encodePacked(p256PublicKeyX, p256PublicKeyY);

        vm.startPrank(address(mockAccount));
        // set ownership data
        stxValidator.onInstall(abi.encodePacked(address(p256StatelessValidator), uint8(0), validationData));

        vm.stopPrank();
    }

    function test_ValidateUserOp_P256_StatelessValidator_success() public {
        uint256 counterBefore = mockTarget.counter();
        bytes memory innerCallData = abi.encodeWithSelector(MockTarget.incrementCounter.selector);

        vm.deal(address(mockAccount), 100 ether);

        PackedUserOperation memory userOp = buildUserOpWithCalldataAndGasParams({
            account: address(mockAccount),
            callData: abi.encodeWithSelector(
                mockAccount.execute.selector, address(mockTarget), uint256(0), innerCallData
            ),
            wallet: wallet,
            preVerificationGasLimit: 3e5,
            verificationGasLimit: 900e3,
            callGasLimit: 3e6
        });

        bytes32 userOpHash = ENTRYPOINT.getUserOpHash(userOp);
        (bytes32 r, bytes32 s) = vm.signP256(wallet.privateKey, userOpHash);
        bytes memory signature = abi.encodePacked(SIG_TYPE_NO_STX_P256, r, s);
        userOp.signature = signature;

        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = userOp;

        vm.startPrank(MEE_NODE_EXECUTOR_EOA);
        ENTRYPOINT.handleOps(userOps, payable(MEE_NODE_ADDRESS));
        vm.stopPrank();

        assertEq(mockTarget.counter(), counterBefore + 1);
    }

    function test_isValidSignatureWithSender_P256_StatelessValidator_7739_success() public {
        TestTemps memory t;
        t.contents = keccak256("0x1234");
        bytes32 dataToSign = toERC7739Hash(t.contents, address(mockAccount));
        (t.r, t.s) = vm.signP256(wallet.privateKey, dataToSign);
        bytes memory contentsType = "Contents(bytes32 stuff)";
        bytes memory signature =
            abi.encodePacked(t.r, t.s, APP_DOMAIN_SEPARATOR, t.contents, contentsType, uint16(contentsType.length));
        signature = abi.encodePacked(SIG_TYPE_NO_STX_P256, signature);
        bytes4 ret = mockAccount.isValidSignature(toContentsHash(t.contents), signature);
        assertEq(ret, bytes4(ERC1271_SUCCESS));
    }

    function test_isValidSignatureWithSender_P256_StatelessValidator_1271_success() public {
        TestTemps memory t;
        bytes32 dataToSign = keccak256("0x1234");
        (t.r, t.s) = vm.signP256(wallet.privateKey, dataToSign);
        bytes memory signature = abi.encodePacked(t.r, t.s);
        signature = abi.encodePacked(SIG_TYPE_NO_STX_VANILLA_1271_P256, signature);
        bytes4 ret = mockAccount.isValidSignature(dataToSign, signature);
        assertEq(ret, bytes4(ERC1271_SUCCESS));
    }

    //// ====== HELPER FUNCTIONS ====== ////

    /// @notice Generates an ERC-1271 hash for the given contents and account.
    /// @dev This function is used for ERC-7739 flow
    /// @param contents The contents hash.
    /// @param account The account address.
    /// @return The ERC-1271 hash.
    function toERC7739Hash(bytes32 contents, address account) internal view returns (bytes32) {
        bytes32 parentStructHash = keccak256(
            abi.encodePacked(
                abi.encode(
                    keccak256(
                        "TypedDataSign(Contents contents,string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)Contents(bytes32 stuff)"
                    ),
                    contents
                ),
                accountDomainStructFields(account)
            )
        );
        return keccak256(abi.encodePacked("\x19\x01", APP_DOMAIN_SEPARATOR, parentStructHash));
    }

    /// @notice Generates a contents hash.
    /// @param contents The contents hash.
    /// @return The EIP-712 hash.
    function toContentsHash(bytes32 contents) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(hex"1901", APP_DOMAIN_SEPARATOR, contents));
    }
}
