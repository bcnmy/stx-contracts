import {
    StxValidator_Base_Test,
    NO_STX_CONFIG_ID_4337,
    NO_STX_CONFIG_ID_7739,
    NO_STX_CONFIG_ID_VANILLA_1271
} from "./StxValidator_Base_Test.t.sol";
import { Vm } from "forge-std/Test.sol";
import { PermitSubmodule } from "../../../contracts/validators/stx-validator/submodules/PermitSubmodule.sol";
import { PackedUserOperation } from "account-abstraction/interfaces/PackedUserOperation.sol";
import { MockTarget } from "../../mock/MockTarget.sol";
import { ERC1271_SUCCESS } from "contracts/types/Constants.sol";
import { EIP712 } from "solady/utils/EIP712.sol";

contract StxValidator_NoStx_Mode_Test is StxValidator_Base_Test {
    bytes32 internal constant APP_DOMAIN_SEPARATOR = 0xa1a044077d7677adbbfa892ded5390979b33993e0e2a457e3f974bbcda53821b;

    function setUp() public virtual override {
        super.setUp();

        // use permit submodule with the default config
        // it supports no stx mode detection for userOps flow
        vm.startPrank(address(mockAccount));
        // set the default config
        stxValidator.onInstall(
            abi.encodePacked(
                address(permitSubmodule), address(eoaStatelessValidator), uint8(0), abi.encodePacked(wallet.addr)
            )
        );

        stxValidator.addConfig(
            NO_STX_CONFIG_ID_4337, address(0), address(eoaStatelessValidator), abi.encodePacked(wallet.addr)
        );
        stxValidator.addConfig(
            NO_STX_CONFIG_ID_7739, address(0), address(eoaStatelessValidator), abi.encodePacked(wallet.addr)
        );
        stxValidator.addConfig(
            NO_STX_CONFIG_ID_VANILLA_1271, address(0), address(eoaStatelessValidator), abi.encodePacked(wallet.addr)
        );
        vm.stopPrank();
    }

    function test_noStxMode_ValidateUserOp_success_via_default_config() public {
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
            verificationGasLimit: 500e3,
            callGasLimit: 3e6
        });

        // we do no specific signature encoding / packing here.
        // default config should be used by the stx validator in this case
        // default config has permit submodule as stx mode verifier
        // it should detect the no stx mode and pass the correct data
        // to the eoa stateless validator, so just the sig over userOpHash should be enough
        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = userOp;

        vm.startPrank(MEE_NODE_EXECUTOR_EOA);
        ENTRYPOINT.handleOps(userOps, payable(MEE_NODE_ADDRESS));
        vm.stopPrank();

        assertEq(mockTarget.counter(), counterBefore + 1);
    }

    function test_noStxMode_ValidateUserOp_success_via_no_stx_config_4337() public {
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
            verificationGasLimit: 500e3,
            callGasLimit: 3e6
        });

        userOp.signature = abi.encodePacked(NO_STX_CONFIG_ID_4337, userOp.signature);

        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = userOp;

        vm.startPrank(MEE_NODE_EXECUTOR_EOA);
        ENTRYPOINT.handleOps(userOps, payable(MEE_NODE_ADDRESS));
        vm.stopPrank();

        assertEq(mockTarget.counter(), counterBefore + 1);
    }

    function test_noStxMode_isValidSignatureWithSender_7739_success() public {
        TestTemps memory t;
        t.contents = keccak256("0x1234");
        bytes32 dataToSign = toERC7739Hash(t.contents, address(mockAccount));
        (t.v, t.r, t.s) = vm.sign(wallet.privateKey, dataToSign);
        bytes memory contentsType = "Contents(bytes32 stuff)";
        bytes memory signature = abi.encodePacked(
            t.r, t.s, t.v, APP_DOMAIN_SEPARATOR, t.contents, contentsType, uint16(contentsType.length)
        );
        signature = abi.encodePacked(NO_STX_CONFIG_ID_7739, signature);
        bytes4 ret = mockAccount.isValidSignature(toContentsHash(t.contents), signature);
        assertEq(ret, bytes4(ERC1271_SUCCESS));
    }

    function test_noStxMode_isValidSignatureWithSender_1271_success() public {
        TestTemps memory t;
        bytes32 dataToSign = keccak256("0x1234");
        (t.v, t.r, t.s) = vm.sign(wallet.privateKey, dataToSign);
        bytes memory signature = abi.encodePacked(t.r, t.s, t.v);
        signature = abi.encodePacked(NO_STX_CONFIG_ID_VANILLA_1271, signature);
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
