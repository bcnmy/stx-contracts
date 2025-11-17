// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

// ==========================
// Standard Library Imports
// ==========================
import "forge-std/console2.sol";
import "forge-std/Test.sol";
import "forge-std/Vm.sol";

// ==========================
// Utility Libraries
// ==========================
import "solady/utils/ECDSA.sol";
import { EIP712 } from "solady/utils/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

// ==========================
// Constants
// ==========================
import "contracts/types/Constants.sol";

// ==========================
// Account Abstraction Imports
// ==========================
import { EntryPoint } from "account-abstraction/core/EntryPoint.sol";
import { IEntryPoint } from "account-abstraction/interfaces/IEntryPoint.sol";
import "account-abstraction/interfaces/PackedUserOperation.sol";

// ==========================
// ModeLib Import
// ==========================
import "contracts/lib/erc-7579/ModeLib.sol";
import "contracts/lib/erc-7579/ExecLib.sol";
import "contracts/lib/erc-7579/ModuleTypeLib.sol";

// ==========================
// Interface Imports
// ==========================
import "contracts/interfaces/nexus/base/IAccountConfig.sol";
import "contracts/interfaces/nexus/base/IModuleManager.sol";
import {
    IModule,
    IValidator,
    IExecutor,
    IHook,
    IPreValidationHookERC1271,
    IPreValidationHookERC4337,
    IFallback
} from "erc7579/interfaces/IERC7579Module.sol";
import "contracts/interfaces/nexus/base/IStorage.sol";
import "contracts/interfaces/nexus/INexus.sol";

// ==========================
// Contract Implementations
// ==========================
import "contracts/nexus/Nexus.sol";
import "contracts/nexus/factory/NexusAccountFactory.sol";
import { K1MeeValidator } from "contracts/validators/stx-validator/K1MeeValidator.sol";
import "contracts/nexus/factory/Stakeable.sol";
import "../mock/accounts/ExposedNexus.sol";

// ==========================
// Mock Contracts for Testing
// ==========================
import { MockPaymaster } from "../mock/MockPaymaster.sol";
import { MockInvalidModule } from "../mock/modules/MockInvalidModule.sol";
import { MockExecutor } from "../mock/modules/MockExecutor.sol";
import { MockHandler } from "../mock/modules/MockHandler.sol";
import { MockValidator } from "../mock/modules/MockValidator.sol";
import { MockHook } from "../mock/modules/MockHook.sol";
import { MockToken } from "../mock/tokens/MockToken.sol";
import { MockMultiModule } from "../mock/modules/MockMultiModule.sol";
import { MockSafe1271Caller } from "../mock/modules/MockSafe1271Caller.sol";
import { MockPreValidationHook } from "../mock/modules/MockPreValidationHook.sol";
import { MockDelegateTarget } from "../mock/MockDelegateTarget.sol";
import "../mock/tokens/MockNFT.sol";
import "../mock/Counter.sol";

// ==========================
// Additional Contract Imports
// ==========================
import "contracts/nexus/utils/NexusBootstrap.sol";
import "./NexusBootstrapLib.sol";
import "../mock/tokens/MockNFT.sol";
import "../mock/tokens/MockToken.sol";

// ==========================
// Sentinel List Helper
// ==========================
import { SentinelListLib } from "sentinellist/SentinelList.sol";
import { SentinelListHelper } from "sentinellist/SentinelListHelper.sol";

contract Imports {
    // This contract acts as a single point of import for Foundry tests.
    // It does not require any logic, as its sole purpose is to consolidate imports.

    }
