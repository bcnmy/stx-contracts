// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { StxValidator_Base_Test } from "./StxValidator_Base_Test.t.sol";
import { Vm } from "forge-std/Test.sol";
import { PackedUserOperation } from "account-abstraction/core/UserOperationLib.sol";
import { MockERC20PermitToken } from "test/mock/tokens/MockERC20PermitToken.sol";
import { ERC1271_SUCCESS } from "contracts/types/Constants.sol";
import { MerkleTreeLib } from "solady/utils/MerkleTreeLib.sol";
import { EIP712 } from "solady/utils/EIP712.sol";
import { EcdsaHelperLib } from "contracts/lib/util/EcdsaHelperLib.sol";
import { CopyUserOpLib } from "../../util/CopyUserOpLib.sol";
import { SimpleModeSubmodule } from "contracts/validators/stx-validator/submodules/SimpleModeSubmodule.sol";

contract StxValidator_Simple_Mode_Test is StxValidator_Base_Test {
    using CopyUserOpLib for PackedUserOperation;

    SimpleModeSubmodule internal simpleModeSubmodule;

    function setUp() public virtual override {
        super.setUp();

        // deploy permit submodule and use it with the default config
        simpleModeSubmodule = new SimpleModeSubmodule();
        vm.prank(address(mockAccount));
        // set the default config
        stxValidator.onInstall(
            abi.encodePacked(
                address(simpleModeSubmodule), address(eoaStatelessValidator), uint8(0), abi.encodePacked(wallet.addr)
            )
        );
    }
}
