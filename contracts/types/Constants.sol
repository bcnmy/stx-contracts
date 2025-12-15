// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

// STX Sig types
bytes3 constant SIG_TYPE_MEE_FLOW = 0x177eee;

bytes4 constant SIG_TYPE_SIMPLE = 0x177eee00;
bytes4 constant SIG_TYPE_ON_CHAIN = 0x177eee01;
bytes4 constant SIG_TYPE_ERC20_PERMIT = 0x177eee02;
// ...other sig types: ERC-7683, Permit2, etc

// EIP-1271 constants
bytes4 constant ERC1271_SUCCESS = 0x1626ba7e;
bytes4 constant ERC1271_FAILED = 0xffffffff;

// Node PM constants
bytes4 constant NODE_PM_MODE_USER = 0x170de000; // refund goes to the user
bytes4 constant NODE_PM_MODE_DAPP = 0x170de001; // refund goes to the dApp
bytes4 constant NODE_PM_MODE_KEEP = 0x170de002; // no refund as node sponsored

bytes4 constant NODE_PM_PREMIUM_PERCENT = 0x9ee4ce00; // premium percentage
bytes4 constant NODE_PM_PREMIUM_FIXED = 0x9ee4ce01;

// ERC-4337 validation constants
uint256 constant VALIDATION_SUCCESS = 0;
uint256 constant VALIDATION_FAILED = 1;

// Module type identifiers
uint256 constant MODULE_TYPE_MULTI = 0; // Module type identifier for Multitype install
uint256 constant MODULE_TYPE_VALIDATOR = 1;
uint256 constant MODULE_TYPE_EXECUTOR = 2;
uint256 constant MODULE_TYPE_FALLBACK = 3;
uint256 constant MODULE_TYPE_HOOK = 4;
uint256 constant MODULE_TYPE_STATELESS_VALIDATOR = 7;
uint256 constant MODULE_TYPE_PREVALIDATION_HOOK_ERC1271 = 8;
uint256 constant MODULE_TYPE_PREVALIDATION_HOOK_ERC4337 = 9;

// Nexus Validation modes
bytes1 constant MODE_VALIDATION = 0x00;
bytes1 constant MODE_MODULE_ENABLE = 0x01;
bytes1 constant MODE_PREP = 0x02;

// ERC-7739 support constants
bytes4 constant SUPPORTS_ERC7739 = 0x77390000;
bytes4 constant SUPPORTS_ERC7739_V1 = 0x77390001;

// Typehashes

// keccak256("ModuleEnableMode(address module,uint256 moduleType,bytes32 userOpHash,bytes initData)")
bytes32 constant MODULE_ENABLE_MODE_TYPE_HASH = 0xf6c866c1cd985ce61f030431e576c0e82887de0643dfa8a2e6efc3463e638ed0;

// keccak256("EmergencyUninstall(address hook,uint256 hookType,bytes deInitData,uint256 nonce)")
bytes32 constant EMERGENCY_UNINSTALL_TYPE_HASH = 0xd3ddfc12654178cc44d4a7b6b969cfdce7ffe6342326ba37825314cffa0fba9c;
