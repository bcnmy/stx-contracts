// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test, Vm } from "forge-std/Test.sol";
import { StxValidator } from "contracts/validators/stx-validator/StxValidator.sol";
import {
    ConfigManager,
    SubmoduleAddresses,
    ValidationConfig
} from "contracts/validators/stx-validator/ConfigManager.sol";
import { EOAStatelessValidator } from "contracts/validators/stx-validator/submodules/EOAStatelessValidator.sol";
import { NoStxModeVerifier } from "contracts/validators/stx-validator/submodules/NoStxModeVerifier.sol";
import { SimpleModeSubmodule } from "contracts/validators/stx-validator/submodules/SimpleModeSubmodule.sol";
import { PermitSubmodule } from "contracts/validators/stx-validator/submodules/PermitSubmodule.sol";
import { TxSubmodule } from "contracts/validators/stx-validator/submodules/TxSubmodule.sol";
import { SafeAccountSubmodule } from "contracts/validators/stx-validator/submodules/SafeAccountSubmodule.sol";
import { P256StatelessValidator } from "contracts/validators/stx-validator/submodules/p256/P256StatelessValidator.sol";

/// @title StxValidator Unit Test Base
/// @notice Base contract for StxValidator unit tests with common setup and utilities
contract StxValidator_Unit_Base_Test is Test {
    StxValidator internal stxValidator;

    EOAStatelessValidator internal eoaStatelessValidator;
    NoStxModeVerifier internal noStxModeVerifier;
    SimpleModeSubmodule internal simpleModeSubmodule;
    PermitSubmodule internal permitSubmodule;
    TxSubmodule internal txSubmodule;
    SafeAccountSubmodule internal safeAccountSubmodule;
    P256StatelessValidator internal p256StatelessValidator;

    Vm.Wallet internal owner;
    Vm.Wallet internal anotherOwner;
    address internal smartAccount;
    address internal anotherSmartAccount;

    // Custom config test data
    address internal customStxModeVerifier;
    address internal customStatelessValidator;
    bytes32 internal customConfigId;

    // Events (declared here so child contracts can use them)
    event ConfigAdded(bytes32 indexed configId, address indexed smartAccount);
    event ConfigReplaced(bytes32 indexed configId, address indexed smartAccount);
    event ConfigDeleted(bytes32 indexed configId, address indexed smartAccount);

    function setUp() public virtual {
        // Deploy all submodules
        eoaStatelessValidator = new EOAStatelessValidator();
        noStxModeVerifier = new NoStxModeVerifier();
        simpleModeSubmodule = new SimpleModeSubmodule();
        permitSubmodule = new PermitSubmodule();
        txSubmodule = new TxSubmodule();
        safeAccountSubmodule = new SafeAccountSubmodule();
        p256StatelessValidator = new P256StatelessValidator();

        // Deploy StxValidator with all submodules
        stxValidator = new StxValidator(
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

        // Create test wallets
        owner = vm.createWallet("owner");
        anotherOwner = vm.createWallet("anotherOwner");

        // Use deterministic addresses for smart accounts
        smartAccount = address(0x1234567890123456789012345678901234567890);
        anotherSmartAccount = address(0x0987654321098765432109876543210987654321);

        // Setup custom config test data
        customStxModeVerifier = address(0xCAFE);
        customStatelessValidator = address(0xBEEF);
        customConfigId = keccak256("custom-config-1");
    }

    /// @notice Helper to initialize validator for smartAccount with EOA ownership
    function _initializeValidator() internal {
        bytes memory installData =
            abi.encodePacked(address(eoaStatelessValidator), uint8(0), abi.encodePacked(owner.addr));
        vm.prank(smartAccount);
        stxValidator.onInstall(installData);
    }

    /// @notice Helper to initialize validator for a specific account with EOA ownership
    function _initializeValidatorForAccount(address account, address ownerAddr) internal {
        bytes memory installData =
            abi.encodePacked(address(eoaStatelessValidator), uint8(0), abi.encodePacked(ownerAddr));
        vm.prank(account);
        stxValidator.onInstall(installData);
    }
}
