// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Script, console2} from "node_modules/forge-std/src/Script.sol";
import {SafeSingletonDeployer} from "./SafeSingletonDeployer.sol";

contract DeployViaSafeDeployer is Script {
  function run(address expectedAddress, string memory bytecodeLocation, bytes32 salt, string memory contractName) public {

    bytes memory creationCode = vm.getCode(bytecodeLocation);

    address deployedAddress = SafeSingletonDeployer.broadcastDeploy({
      creationCode: creationCode,
      salt: salt
    });

    if (deployedAddress != expectedAddress) {
      console2.log("Deployed address ", deployedAddress, " does not match expected address ", expectedAddress);
    } else {
      console2.log("Successfully deployed ", contractName, " at expected address ", deployedAddress);
    }
  }
}