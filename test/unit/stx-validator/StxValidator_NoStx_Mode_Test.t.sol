import { StxValidator_Base_Test } from "./StxValidator_Base_Test.t.sol";
import { Vm } from "forge-std/Test.sol";
import { PermitSubmodule } from "../../../contracts/validators/stx-validator/submodules/PermitSubmodule.sol";
import { PackedUserOperation } from "account-abstraction/interfaces/PackedUserOperation.sol";
import { MockTarget } from "../../mock/MockTarget.sol";

contract StxValidator_NoStx_Mode_Test is StxValidator_Base_Test {
    bytes32 internal constant APP_DOMAIN_SEPARATOR = 0xa1a044077d7677adbbfa892ded5390979b33993e0e2a457e3f974bbcda53821b;

    PermitSubmodule internal permitSubmodule;

    function setUp() public virtual override {
        super.setUp();

        // deploy permit submodule and use it with the default config
        // it supports no stx mode detection for userOps
        permitSubmodule = new PermitSubmodule();
        vm.prank(address(mockAccount));
        // set the default config
        stxValidator.onInstall(
            abi.encodePacked(
                address(permitSubmodule), address(eoaStatelessValidator), uint8(0), abi.encodePacked(wallet.addr)
            )
        );
    }

    function test_noStxMode_ValidateUserOp_success() public {
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
}
