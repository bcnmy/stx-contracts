// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { BaseTest } from "../../Base.t.sol";
import { MockFallbackAccount } from "../../mock/accounts/MockFallbackAccount.sol";
import { MockAccountNonRevert } from "../../mock/accounts/MockAccountNonRevert.sol";
import { ComposableExecutionModule } from "contracts/composability/ComposableExecutionModule.sol";
import { MockAccountDelegateCaller } from "../../mock/accounts/MockAccountDelegateCaller.sol";
import { MockAccountCaller } from "../../mock/accounts/MockAccountCaller.sol";
import { MockAccount } from "../../mock/accounts/MockAccount.sol";
import { ComposableStorage } from "contracts/composability/ComposableStorage.sol";
import { InputParam, Constraint, InputParamType, InputParamFetcherType } from "contracts/types/ComposabilityDataTypes.sol";
import { MockERC20Balance } from "../../mock/MockERC20Balance.sol";
import "../../mock/DummyContract.sol";

contract ComposabilityTestBase is BaseTest {
    ComposableExecutionModule internal composabilityHandler;
    MockFallbackAccount internal mockFallbackAccount;
    MockAccountDelegateCaller internal mockAccountDelegateCaller;
    MockAccountCaller internal mockAccountCaller;
    MockAccountNonRevert internal mockAccountNonRevert;
    MockAccount internal mockAccountSimple;
    MockERC20Balance internal mockERC20Balance;

    event MockAccountReceive(uint256 amount);

    ComposableStorage public storageContract;
    DummyContract public dummyContract;

    bytes32 public constant SLOT_A = keccak256("SLOT_A");
    bytes32 public constant SLOT_B = keccak256("SLOT_B");

    Constraint[] internal emptyConstraints = new Constraint[](0);

    function setUp() public virtual override {
        // no need yet. May be needed in the future when/if we test via Nexus
        // super.setUp();

        composabilityHandler = new ComposableExecutionModule(ENTRYPOINT_V07_ADDRESS);
        mockFallbackAccount = new MockFallbackAccount({
            _validator: address(0),
            _executor: address(composabilityHandler),
            _handler: address(composabilityHandler)
        });
        mockAccountCaller = new MockAccountCaller({
            _validator: address(0),
            _executor: address(composabilityHandler),
            _handler: address(composabilityHandler)
        });
        mockAccountDelegateCaller = new MockAccountDelegateCaller({ _composableModule: address(composabilityHandler) });

        vm.prank(address(mockFallbackAccount));
        composabilityHandler.onInstall(abi.encodePacked(ENTRYPOINT_V07_ADDRESS));

        mockAccountSimple = new MockAccount({ _validator: address(0), _handler: address(0xa11ce) });
        mockAccountNonRevert = new MockAccountNonRevert({ _validator: address(0), _handler: address(0xa11ce) });
        mockERC20Balance = new MockERC20Balance();

        // fund accounts
        vm.deal(address(mockFallbackAccount), 100 ether);
        vm.deal(address(mockAccountDelegateCaller), 100 ether);
        vm.deal(address(mockAccountCaller), 100 ether);
        vm.deal(address(mockAccountNonRevert), 100 ether);
        vm.deal(address(mockAccountSimple), 100 ether);
        vm.deal(address(ENTRYPOINT_V07_ADDRESS), 100 ether);

        // Deploy contracts
        storageContract = new ComposableStorage();
        dummyContract = new DummyContract();
    }

    function _createRawTargetInputParam(address target) internal returns (InputParam memory) {
        return InputParam({
            paramType: InputParamType.TARGET,
            fetcherType: InputParamFetcherType.RAW_BYTES,
            paramData: abi.encode(target),
            constraints: emptyConstraints
        });
    }

    function _createRawValueInputParam(uint256 value) internal returns (InputParam memory) {
        return InputParam({
            paramType: InputParamType.VALUE,
            fetcherType: InputParamFetcherType.RAW_BYTES,
            paramData: abi.encode(value),
            constraints: emptyConstraints
        });
    }
}
