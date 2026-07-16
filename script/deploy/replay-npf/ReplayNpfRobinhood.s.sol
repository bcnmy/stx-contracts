// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

/// Replays the default NodePaymasterFactory CREATE2 deployment (mee-node's built-in
/// `contracts.pmFactory` default, 0x000000005824a1ED617994dF733151D26a4cf03d) onto
/// Robinhood Chain (4663). Calldata is the verbatim input of the Arbitrum One creation
/// tx 0xb0a2bf004cddea0627eab9995bba0313e8bb2f96201b8b5098247de8d0fe2141, sent to the
/// canonical deterministic deployer, so address and bytecode are identical by construction.
/// The constructor wrapper avoids forge's broadcast inspector mis-decoding the initcode
/// against this repo's differently-versioned NodePaymasterFactory artifact.
contract NpfReplayer {
    constructor(bytes memory payload) {
        (bool success, ) = 0x4e59b44847b379578588920cA78FbF26c0B4956C.call(payload);
        require(success, "create2 deploy reverted");
        require(
            0x000000005824a1ED617994dF733151D26a4cf03d.code.length > 0,
            "no code at expected address"
        );
    }
}

contract ReplayNpfRobinhood is Script {
    function run() external {
        address target = 0x000000005824a1ED617994dF733151D26a4cf03d;
        require(target.code.length == 0, "already deployed");

        bytes memory payload = vm.parseBytes(
            vm.readFile("script/deploy/replay-npf/npf.calldata")
        );

        uint256 pk;
        try vm.envUint("MAINNET_PRIVATE_KEY") returns (uint256 v) {
            pk = v;
        } catch {
            pk = uint256(vm.envBytes32("MAINNET_PRIVATE_KEY"));
        }

        vm.startBroadcast(pk);
        new NpfReplayer(payload);
        vm.stopBroadcast();

        console2.log("NodePaymasterFactory code bytes:", target.code.length);
    }
}
