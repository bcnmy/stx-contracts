// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

/// Forwards pre-built (salt ++ initcode) payloads to the canonical deterministic
/// CREATE2 deployer from within a constructor. Wrapping the calls avoids forge's
/// broadcast-transaction inspector, which otherwise tries to match the payloads
/// against this repo's compiled artifacts (a different contracts version) and
/// aborts while mis-decoding constructor arguments.
contract Create2Replayer {
    address constant CREATE2_PROXY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    constructor(bytes[] memory payloads, address[] memory expected) {
        for (uint256 i = 0; i < payloads.length; i++) {
            (bool success, ) = CREATE2_PROXY.call(payloads[i]);
            require(success, "create2 deploy reverted");
            require(expected[i].code.length > 0, "no code at expected address");
        }
    }
}

/// Replays the exact CREATE2 deployments of the MEE v2.1.0 suite from Chiliz
/// mainnet (88888) onto Chiliz Spicy (88882). Calldata blobs are the verbatim
/// inputs of the original mainnet creation transactions, so the resulting
/// addresses and runtime bytecode are byte-identical by construction.
///
/// Mainnet source txs:
///   factory        0x9200d7c58961a5e642c4ce5086da28c84d6ef2f9e354aad38813d5b6ad293770
///   bootstrap      0x3bbed7885e595c370d38c3a4d0fe9ff38b5841887c5e54c0cbcd4e8b5ab8b002
///   implementation 0x47b9fd4737ab8ad573ab1c3d3e9c26ea2d453dd228712c6007bd3e150b01bd52
contract ReplayV210Spicy is Script {
    address constant FACTORY = 0x0000006648ED9B2B842552BE63Af870bC74af837;
    address constant BOOTSTRAP = 0x0000003eDf18913c01cBc482C978bBD3D6E8ffA3;
    address constant IMPLEMENTATION = 0x00000000383e8cBe298514674Ea60Ee1d1de50ac;

    function run() external {
        uint256 pk;
        try vm.envUint("TESTNET_PRIVATE_KEY") returns (uint256 v) {
            pk = v;
        } catch {
            pk = uint256(vm.envBytes32("TESTNET_PRIVATE_KEY"));
        }

        string[3] memory names = ["factory", "bootstrap", "implementation"];
        address[3] memory targets = [FACTORY, BOOTSTRAP, IMPLEMENTATION];

        bytes[] memory payloads = new bytes[](3);
        address[] memory expected = new address[](3);
        uint256 count = 0;

        for (uint256 i = 0; i < 3; i++) {
            if (targets[i].code.length > 0) {
                console2.log(names[i], "already deployed, skipping");
                continue;
            }
            payloads[count] = vm.parseBytes(
                vm.readFile(string.concat("script/deploy/replay-v210/", names[i], ".calldata"))
            );
            expected[count] = targets[i];
            count++;
        }

        if (count == 0) {
            console2.log("nothing to deploy");
            return;
        }

        assembly {
            mstore(payloads, count)
            mstore(expected, count)
        }

        vm.startBroadcast(pk);
        new Create2Replayer(payloads, expected);
        vm.stopBroadcast();

        for (uint256 i = 0; i < 3; i++) {
            console2.log(names[i], targets[i].code.length > 0 ? "code OK at" : "MISSING at", targets[i]);
        }
    }
}
