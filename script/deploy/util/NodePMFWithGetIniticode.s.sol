// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "../../../contracts/node-pm/NodePaymasterFactory.sol";
import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

contract NodePMFWithGetInitcode is NodePaymasterFactory {

    function getNodePaymasterInitcode() public view returns (bytes memory) {
        return type(NodePaymaster).creationCode;
    }
}

contract DeployNodePMFWithGetInitcode is Script {
    function run() public {
        vm.startBroadcast();
        NodePMFWithGetInitcode nodePMF = new NodePMFWithGetInitcode();
        bytes memory initcode = nodePMF.getNodePaymasterInitcode();
        console2.log("node pmf with get initcode", address(nodePMF));
        console2.logBytes(initcode);
        vm.stopBroadcast();
    }
}