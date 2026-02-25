// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { StxValidator_Unit_Base_Test } from "./StxValidator_Unit_Base_Test.t.sol";
import { StxValidator } from "contracts/validators/stx-validator/StxValidator.sol";
import { SubmoduleAddresses } from "contracts/validators/stx-validator/ConfigManager.sol";

/// @title StxValidator Harness for Safe Senders Tests
/// @notice Exposes internal _erc1271CallerIsSafe function for testing
contract StxValidatorSafeSendersHarness is StxValidator {
    constructor(SubmoduleAddresses memory submoduleAddresses) StxValidator(submoduleAddresses) { }

    function exposed_erc1271CallerIsSafe(address account, address sender) external view returns (bool) {
        return _erc1271CallerIsSafe(account, sender);
    }
}

/// @title StxValidator Safe Senders Tests
/// @notice Tests for safe senders management functionality
/// @dev Tests addSafeSender, removeSafeSender, isSafeSender, and _erc1271CallerIsSafe
contract StxValidator_SafeSenders_Test is StxValidator_Unit_Base_Test {
    StxValidatorSafeSendersHarness internal stxValidatorHarness;

    address internal safeSender1;
    address internal safeSender2;
    address internal safeSender3;

    // MulticallerWithSigner canonical address
    address internal constant MULTICALLER_WITH_SIGNER = 0x000000000000D9ECebf3C23529de49815Dac1c4c;

    function setUp() public override {
        super.setUp();

        // Deploy harness for testing internal functions
        stxValidatorHarness = new StxValidatorSafeSendersHarness(
            SubmoduleAddresses({
                noStxModeVerifier: address(noStxModeVerifier),
                simpleModeVerifier: address(simpleModeSubmodule),
                permitModeVerifier: address(permitSubmodule),
                txModeVerifier: address(txSubmodule),
                safeAccountSubmodule: address(safeAccountSubmodule),
                eoaStatelessValidator: address(eoaStatelessValidator),
                p256StatelessValidator: address(p256StatelessValidator)
            })
        );

        // Create safe sender addresses
        safeSender1 = makeAddr("safeSender1");
        safeSender2 = makeAddr("safeSender2");
        safeSender3 = makeAddr("safeSender3");
    }

    /*//////////////////////////////////////////////////////////////////////////
                              ADD SAFE SENDER TESTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Test that a smart account can add a safe sender
    function test_addSafeSender_success() public {
        vm.prank(smartAccount);
        stxValidator.addSafeSender(safeSender1);

        assertTrue(stxValidator.isSafeSender(safeSender1, smartAccount));
    }

    /// @notice Test that adding the same safe sender twice doesn't fail
    /// @dev EnumerableSet.add returns false if already exists but doesn't revert
    function test_addSafeSender_duplicateDoesNotRevert() public {
        vm.startPrank(smartAccount);
        stxValidator.addSafeSender(safeSender1);
        stxValidator.addSafeSender(safeSender1); // Should not revert
        vm.stopPrank();

        assertTrue(stxValidator.isSafeSender(safeSender1, smartAccount));
    }

    /// @notice Test that a smart account can add multiple safe senders
    function test_addSafeSender_multipleSenders() public {
        vm.startPrank(smartAccount);
        stxValidator.addSafeSender(safeSender1);
        stxValidator.addSafeSender(safeSender2);
        stxValidator.addSafeSender(safeSender3);
        vm.stopPrank();

        assertTrue(stxValidator.isSafeSender(safeSender1, smartAccount));
        assertTrue(stxValidator.isSafeSender(safeSender2, smartAccount));
        assertTrue(stxValidator.isSafeSender(safeSender3, smartAccount));
    }

    /// @notice Test that adding safe sender is account-isolated
    function test_addSafeSender_accountIsolation() public {
        vm.prank(smartAccount);
        stxValidator.addSafeSender(safeSender1);

        // safeSender1 should be safe for smartAccount
        assertTrue(stxValidator.isSafeSender(safeSender1, smartAccount));
        // but not for anotherSmartAccount
        assertFalse(stxValidator.isSafeSender(safeSender1, anotherSmartAccount));
    }

    /// @notice Test that different accounts can have different safe senders
    function test_addSafeSender_differentAccountsDifferentSenders() public {
        vm.prank(smartAccount);
        stxValidator.addSafeSender(safeSender1);

        vm.prank(anotherSmartAccount);
        stxValidator.addSafeSender(safeSender2);

        // smartAccount has safeSender1 but not safeSender2
        assertTrue(stxValidator.isSafeSender(safeSender1, smartAccount));
        assertFalse(stxValidator.isSafeSender(safeSender2, smartAccount));

        // anotherSmartAccount has safeSender2 but not safeSender1
        assertFalse(stxValidator.isSafeSender(safeSender1, anotherSmartAccount));
        assertTrue(stxValidator.isSafeSender(safeSender2, anotherSmartAccount));
    }

    /// @notice Test that zero address can be added as safe sender
    function test_addSafeSender_zeroAddress() public {
        vm.prank(smartAccount);
        stxValidator.addSafeSender(address(0));

        assertTrue(stxValidator.isSafeSender(address(0), smartAccount));
    }

    /*//////////////////////////////////////////////////////////////////////////
                            REMOVE SAFE SENDER TESTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Test that a smart account can remove a safe sender
    function test_removeSafeSender_success() public {
        vm.startPrank(smartAccount);
        stxValidator.addSafeSender(safeSender1);
        assertTrue(stxValidator.isSafeSender(safeSender1, smartAccount));

        stxValidator.removeSafeSender(safeSender1);
        assertFalse(stxValidator.isSafeSender(safeSender1, smartAccount));
        vm.stopPrank();
    }

    /// @notice Test that removing a non-existent safe sender doesn't fail
    /// @dev EnumerableSet.remove returns false if doesn't exist but doesn't revert
    function test_removeSafeSender_nonExistentDoesNotRevert() public {
        vm.prank(smartAccount);
        stxValidator.removeSafeSender(safeSender1); // Should not revert

        assertFalse(stxValidator.isSafeSender(safeSender1, smartAccount));
    }

    /// @notice Test that removing a safe sender only affects that sender
    function test_removeSafeSender_onlyAffectsTargetSender() public {
        vm.startPrank(smartAccount);
        stxValidator.addSafeSender(safeSender1);
        stxValidator.addSafeSender(safeSender2);

        stxValidator.removeSafeSender(safeSender1);
        vm.stopPrank();

        assertFalse(stxValidator.isSafeSender(safeSender1, smartAccount));
        assertTrue(stxValidator.isSafeSender(safeSender2, smartAccount));
    }

    /// @notice Test that removing safe sender is account-isolated
    function test_removeSafeSender_accountIsolation() public {
        // Both accounts add safeSender1
        vm.prank(smartAccount);
        stxValidator.addSafeSender(safeSender1);

        vm.prank(anotherSmartAccount);
        stxValidator.addSafeSender(safeSender1);

        // smartAccount removes safeSender1
        vm.prank(smartAccount);
        stxValidator.removeSafeSender(safeSender1);

        // safeSender1 should be removed from smartAccount but still in anotherSmartAccount
        assertFalse(stxValidator.isSafeSender(safeSender1, smartAccount));
        assertTrue(stxValidator.isSafeSender(safeSender1, anotherSmartAccount));
    }

    /// @notice Test that a safe sender can be re-added after removal
    function test_removeSafeSender_canReAddAfterRemoval() public {
        vm.startPrank(smartAccount);
        stxValidator.addSafeSender(safeSender1);
        stxValidator.removeSafeSender(safeSender1);
        stxValidator.addSafeSender(safeSender1);
        vm.stopPrank();

        assertTrue(stxValidator.isSafeSender(safeSender1, smartAccount));
    }

    /*//////////////////////////////////////////////////////////////////////////
                            IS SAFE SENDER TESTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Test isSafeSender returns false for non-added senders
    function test_isSafeSender_returnsFalseForNonAddedSender() public view {
        assertFalse(stxValidator.isSafeSender(safeSender1, smartAccount));
    }

    /// @notice Test isSafeSender returns true for added senders
    function test_isSafeSender_returnsTrueForAddedSender() public {
        vm.prank(smartAccount);
        stxValidator.addSafeSender(safeSender1);

        assertTrue(stxValidator.isSafeSender(safeSender1, smartAccount));
    }

    /// @notice Test isSafeSender with zero address smart account
    function test_isSafeSender_zeroAddressSmartAccount() public view {
        assertFalse(stxValidator.isSafeSender(safeSender1, address(0)));
    }

    /*//////////////////////////////////////////////////////////////////////////
                      ERC1271 CALLER IS SAFE INTEGRATION TESTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Test that MulticallerWithSigner is always considered safe
    function test_erc1271CallerIsSafe_multicallerWithSignerIsAlwaysSafe() public view {
        // MulticallerWithSigner should be safe for any account
        assertTrue(stxValidatorHarness.exposed_erc1271CallerIsSafe(smartAccount, MULTICALLER_WITH_SIGNER));
        assertTrue(stxValidatorHarness.exposed_erc1271CallerIsSafe(anotherSmartAccount, MULTICALLER_WITH_SIGNER));
        assertTrue(stxValidatorHarness.exposed_erc1271CallerIsSafe(address(0), MULTICALLER_WITH_SIGNER));
    }

    /// @notice Test that the smart account itself is considered a safe sender
    /// @dev The smart account calling itself is always safe (sender == account)
    function test_erc1271CallerIsSafe_smartAccountIsSafeForItself() public view {
        assertTrue(stxValidatorHarness.exposed_erc1271CallerIsSafe(smartAccount, smartAccount));
        assertTrue(stxValidatorHarness.exposed_erc1271CallerIsSafe(anotherSmartAccount, anotherSmartAccount));
    }

    /// @notice Test that added safe senders are considered safe in _erc1271CallerIsSafe
    function test_erc1271CallerIsSafe_addedSenderIsSafe() public {
        vm.prank(smartAccount);
        stxValidatorHarness.addSafeSender(safeSender1);

        assertTrue(stxValidatorHarness.exposed_erc1271CallerIsSafe(smartAccount, safeSender1));
    }

    /// @notice Test that non-added senders are not considered safe
    function test_erc1271CallerIsSafe_nonAddedSenderIsNotSafe() public view {
        assertFalse(stxValidatorHarness.exposed_erc1271CallerIsSafe(smartAccount, safeSender1));
    }

    /// @notice Test that safe sender for one account is not safe for another
    function test_erc1271CallerIsSafe_accountIsolation() public {
        vm.prank(smartAccount);
        stxValidatorHarness.addSafeSender(safeSender1);

        assertTrue(stxValidatorHarness.exposed_erc1271CallerIsSafe(smartAccount, safeSender1));
        assertFalse(stxValidatorHarness.exposed_erc1271CallerIsSafe(anotherSmartAccount, safeSender1));
    }

    /*//////////////////////////////////////////////////////////////////////////
                              FUZZ TESTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Fuzz test for adding safe senders
    function testFuzz_addSafeSender(address sender) public {
        vm.prank(smartAccount);
        stxValidator.addSafeSender(sender);

        assertTrue(stxValidator.isSafeSender(sender, smartAccount));
    }

    /// @notice Fuzz test for removing safe senders
    function testFuzz_removeSafeSender(address sender) public {
        vm.startPrank(smartAccount);
        stxValidator.addSafeSender(sender);
        stxValidator.removeSafeSender(sender);
        vm.stopPrank();

        assertFalse(stxValidator.isSafeSender(sender, smartAccount));
    }

    /// @notice Fuzz test for account isolation
    function testFuzz_safeSender_accountIsolation(address sender, address account1, address account2) public {
        vm.assume(account1 != account2);

        vm.prank(account1);
        stxValidator.addSafeSender(sender);

        assertTrue(stxValidator.isSafeSender(sender, account1));
        assertFalse(stxValidator.isSafeSender(sender, account2));
    }
}
