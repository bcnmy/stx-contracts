// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IModule } from "erc7579/interfaces/IERC7579Module.sol";

contract MockInvalidModule is IModule {
    function onInstall(bytes calldata data) external pure {
        data;
    }

    function onUninstall(bytes calldata data) external pure {
        data;
    }

    function isModuleType(uint256 moduleTypeId) external pure returns (bool) {
        return moduleTypeId == 99;
    }

    function isInitialized(address) external pure returns (bool) {
        return false;
    }
}
