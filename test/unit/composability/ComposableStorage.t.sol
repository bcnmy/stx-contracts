// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { ComposableStorage } from "contracts/composability/ComposableStorage.sol";

contract ComposableStorageTest is Test {
    ComposableStorage public composableStorage;

    function setUp() public {
        composableStorage = new ComposableStorage();
    }

    function test_getNamespace() public {
        address alice = makeAddr("ALICE");
        address bob = makeAddr("BOB");
        bytes32 namespace = composableStorage.getNamespace(alice, bob);
        assertEq(namespace, keccak256(abi.encodePacked(alice, bob)));
    }

    function test_getNamespacedSlot() public {
        bytes32 namespace = composableStorage.getNamespace(address(this), address(this));
        bytes32 slot = keccak256(abi.encodePacked("test slot"));
        bytes32 result = composableStorage.getNamespacedSlot(namespace, slot);
        assertEq(result, keccak256(abi.encodePacked(namespace, slot)));
    }

    function test_writeStorage_expected_slot_initialized() public {
        address account = makeAddr("ACCOUNT");
        address caller = address(this);
        bytes32 namespace = composableStorage.getNamespace(account, caller);
        bytes32 slot = keccak256(abi.encodePacked("test slot"));

        bytes32 valueToWrite = keccak256(abi.encodePacked("test value"));

        composableStorage.writeStorage(slot, valueToWrite, account);

        assertTrue(composableStorage.isSlotInitialized(namespace, slot));
        assertEq(composableStorage.readStorage(namespace, slot), valueToWrite);
    }

    function test_writeStorage_same_slot_different_senders() public {
        address account = makeAddr("ACCOUNT");
        bytes32 slot = keccak256(abi.encodePacked("test slot"));

        bytes32 valueToWrite = keccak256(abi.encodePacked("test value"));
        bytes32 valueToWrite2 = keccak256(abi.encodePacked("test value 2"));

        vm.prank(makeAddr("ALICE"));
        composableStorage.writeStorage(slot, valueToWrite, account);
        vm.prank(makeAddr("BOB"));
        composableStorage.writeStorage(slot, valueToWrite2, account);

        bytes32 aliceNamespace = composableStorage.getNamespace(account, makeAddr("ALICE"));
        bytes32 bobNamespace = composableStorage.getNamespace(account, makeAddr("BOB"));

        bytes32 valueWrittenFromAlice = composableStorage.readStorage(aliceNamespace, slot);
        bytes32 valueWrittenFromBob = composableStorage.readStorage(bobNamespace, slot);
        assertEq(valueWrittenFromAlice, valueToWrite);
        assertFalse(valueWrittenFromAlice == valueWrittenFromBob);
        assertEq(valueWrittenFromBob, valueToWrite2);
    }
}
