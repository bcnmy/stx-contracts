// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { StxValidator_Unit_Base_Test } from "./StxValidator_Unit_Base_Test.t.sol";
import { MODULE_TYPE_VALIDATOR } from "erc7579/interfaces/IERC7579Module.sol";
import { MODULE_TYPE_STATELESS_VALIDATOR } from "contracts/types/Constants.sol";

/// @title StxValidator Module Metadata Tests
/// @notice Tests for name, version, and isModuleType functionality
contract StxValidator_ModuleMetadata_Test is StxValidator_Unit_Base_Test {
    /*//////////////////////////////////////////////////////////////////////////
                              NAME TESTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Test name returns correct value
    function test_name_returnsStxValidator() public view {
        assertEq(stxValidator.name(), "StxValidator");
    }

    /*//////////////////////////////////////////////////////////////////////////
                              VERSION TESTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Test version returns correct value
    function test_version_returns001() public view {
        assertEq(stxValidator.version(), "0.0.1");
    }

    /*//////////////////////////////////////////////////////////////////////////
                              IS MODULE TYPE TESTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Test isModuleType returns true for MODULE_TYPE_VALIDATOR
    function test_isModuleType_returnsTrueForValidator() public view {
        assertTrue(stxValidator.isModuleType(MODULE_TYPE_VALIDATOR));
    }

    /// @notice Test isModuleType returns true for MODULE_TYPE_STATELESS_VALIDATOR
    function test_isModuleType_returnsTrueForStatelessValidator() public view {
        assertTrue(stxValidator.isModuleType(MODULE_TYPE_STATELESS_VALIDATOR));
    }

    /*//////////////////////////////////////////////////////////////////////////
                              MODULE TYPE CONSTANTS TESTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Test MODULE_TYPE_VALIDATOR constant value
    function test_moduleTypeValidator_hasCorrectValue() public pure {
        assertEq(MODULE_TYPE_VALIDATOR, 1);
    }

    /// @notice Test MODULE_TYPE_STATELESS_VALIDATOR constant value
    function test_moduleTypeStatelessValidator_hasCorrectValue() public pure {
        assertEq(MODULE_TYPE_STATELESS_VALIDATOR, 7);
    }

    /*//////////////////////////////////////////////////////////////////////////
                              FUZZ TESTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Fuzz test isModuleType returns false for arbitrary non-valid types
    function testFuzz_isModuleType_returnsFalseForInvalidTypes(uint256 typeId) public view {
        vm.assume(typeId != MODULE_TYPE_VALIDATOR && typeId != MODULE_TYPE_STATELESS_VALIDATOR);
        assertFalse(stxValidator.isModuleType(typeId));
    }
}
