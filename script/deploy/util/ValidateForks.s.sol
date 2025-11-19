// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Script, console2, console } from "node_modules/forge-std/src/Script.sol";
import { Config } from "node_modules/forge-std/src/Config.sol";

/**
 * @notice Validate forks for a given set of chain IDs
 * @dev This script tries to create forks for a given set of chain IDs
 * If some RPC url is not valid, the fork won't be created and the script will fail.
 */
contract ValidateForks is Script, Config {
    string internal configPath = "/script/deploy/config.toml";

    function run(uint256[] memory chainIds) external {
        string memory fullConfigPath = string.concat(vm.projectRoot(), configPath);
        console.log("Loading config from:", fullConfigPath);

        // load config
        _loadConfig(fullConfigPath, false);

        // validate forks
        tryCreateForks(chainIds);
    }

    function tryCreateForks(uint256[] memory chainIds) internal {
        // validate forks
        console.log("Validating forks...");
        for (uint256 i = 0; i < chainIds.length; i++) {
            uint256 chainId = chainIds[i];
            uint256 forkId = vm.createFork(config.getRpcUrl(chainId));
        }
    }
}