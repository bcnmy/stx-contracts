// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { StxValidator_Unit_Base_Test } from "./StxValidator_Unit_Base_Test.t.sol";
import { Vm } from "forge-std/Vm.sol";

/// @title StxValidator validateSignatureWithData Tests
/// @notice Unit tests for validateSignatureWithData (IStatelessValidator interface)
/// @dev Full STX signature validation with merkle proofs is tested in e2e tests.
contract StxValidator_validateSignatureWithData_Test is StxValidator_Unit_Base_Test {
    /// @notice Test that validateSignatureWithData uses account from data parameter (not msg.sender)
    /// @dev Proves routing by:
    ///      1. Adding custom config for smartAccount only
    ///      2. Creating a valid signature using vm.sign
    ///      3. Verifying validation passes when smartAccount is in data (config exists)
    ///      4. Verifying validation fails when anotherSmartAccount is in data (no config)
    function test_validateSignatureWithData_usesAccountFromDataParam() public {
        // Add custom config ONLY for smartAccount using NoStxModeVerifier (passes hash through)
        vm.prank(smartAccount);
        stxValidator.addConfig(customConfigId, address(noStxModeVerifier), address(eoaStatelessValidator));

        // Set ownership data for smartAccount
        vm.prank(smartAccount);
        stxValidator.setOwnershipData(address(eoaStatelessValidator), abi.encodePacked(owner.addr));

        bytes32 hash = keccak256("test data");

        // Create valid signature using vm.sign
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(owner.privateKey, hash);

        // SIG_TYPE_CUSTOM signature: [4 bytes sigType][32 bytes configId][signature]
        bytes memory sig = abi.encodePacked(bytes4(0x177eeeff), customConfigId, r, s, v);

        // Case 1: Encode smartAccount in data - should PASS validation
        bytes memory dataWithSmartAccount = abi.encode(smartAccount, abi.encodePacked(owner.addr));

        // Call from arbitrary address - proves msg.sender is not used for routing
        vm.prank(address(0x9999));
        bool result1 = stxValidator.validateSignatureWithData(hash, sig, dataWithSmartAccount);
        assertTrue(result1); // Valid signature, correct routing

        // Case 2: Encode anotherSmartAccount in data - should FAIL
        // Config doesn't exist for anotherSmartAccount, so stxModeVerifier is address(0)
        bytes memory dataWithAnotherAccount = abi.encode(anotherSmartAccount, abi.encodePacked(owner.addr));

        vm.prank(address(0x9999));
        vm.expectRevert(); // Call to address(0) reverts
        stxValidator.validateSignatureWithData(hash, sig, dataWithAnotherAccount);
    }

    /// @notice Test that validateSignatureWithData uses ownershipData from data parameter (not storage)
    /// @dev Proves by:
    ///      1. Setting owner A's address in storage
    ///      2. Signing with owner B's key
    ///      3. Passing owner B's address in data param - should PASS
    ///      4. Passing owner A's address in data param - should FAIL
    function test_validateSignatureWithData_usesOwnershipDataFromDataParam() public {
        Vm.Wallet memory ownerB = vm.createWallet("ownerB");

        // Add custom config
        vm.prank(smartAccount);
        stxValidator.addConfig(customConfigId, address(noStxModeVerifier), address(eoaStatelessValidator));

        // Set owner A (original owner) in STORAGE
        vm.prank(smartAccount);
        stxValidator.setOwnershipData(address(eoaStatelessValidator), abi.encodePacked(owner.addr));

        bytes32 hash = keccak256("test data");

        // Sign with owner B's key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerB.privateKey, hash);
        bytes memory sig = abi.encodePacked(bytes4(0x177eeeff), customConfigId, r, s, v);

        // Case 1: Pass owner B in data param - should PASS (matches signer)
        bytes memory dataWithOwnerB = abi.encode(smartAccount, abi.encodePacked(ownerB.addr));
        bool result1 = stxValidator.validateSignatureWithData(hash, sig, dataWithOwnerB);
        assertTrue(result1);

        // Case 2: Pass owner A in data param - should FAIL (doesn't match signer)
        // Even though owner A is in storage, function uses data param
        bytes memory dataWithOwnerA = abi.encode(smartAccount, abi.encodePacked(owner.addr));
        bool result2 = stxValidator.validateSignatureWithData(hash, sig, dataWithOwnerA);
        assertFalse(result2);
    }
}
