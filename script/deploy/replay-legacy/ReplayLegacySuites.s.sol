// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

/// Replays the v1.1.0, v2.0.0 and v2.1.0 MEE contract suites onto a new chain via the
/// canonical deterministic CREATE2 deployer. Payloads are verbatim creation-tx inputs
/// harvested from Chiliz mainnet (see creations.json in the scratchpad of the 2026-07-10
/// session, or re-harvest via routescan). Constructor wrapper avoids forge's broadcast
/// inspector mis-decoding old initcode against current artifacts.
contract SuiteReplayer {
    constructor(bytes[] memory payloads, address[] memory expected) {
        for (uint256 i = 0; i < payloads.length; i++) {
            if (expected[i].code.length > 0) continue;
            (bool success, ) = 0x4e59b44847b379578588920cA78FbF26c0B4956C.call(payloads[i]);
            require(success, "create2 deploy reverted");
            require(expected[i].code.length > 0, "no code at expected address");
        }
    }
}

contract ReplayLegacySuites is Script {
    string constant DIR = "script/deploy/replay-legacy/";

    function run() external {
        uint256 pk;
        try vm.envUint("MAINNET_PRIVATE_KEY") returns (uint256 v) {
            pk = v;
        } catch {
            pk = uint256(vm.envBytes32("MAINNET_PRIVATE_KEY"));
        }

        vm.startBroadcast(pk);
        _suite110();
        _suite200();
        _suite210();
        vm.stopBroadcast();
    }

    function _suite110() internal {
        string[6] memory names = ["v110-implementation", "v110-bootstrap", "v110-validator", "v110-composable", "v110-forwarder", "v110-factory"];
        address[] memory expected = new address[](6);
        expected[0] = 0x000000001964d23C59962Fc7A912872EE8fB3b6A;
        expected[1] = 0x000000c4781Be3349F81d341027fd7A4EdFa4Dd2;
        expected[2] = 0x00000000E894100bEcFc7c934Ab7aC8FBA08A44c;
        expected[3] = 0x000000eff5C221A6bdB12381868307c9Db5eB462;
        expected[4] = 0x000000001f1c68bD5bF69aa1cCc1d429700D41Da;
        expected[5] = 0x0000000C8B6b3329cEa5d15C9d8C15F1f254ec3C;
        _deploy(_payloads6(names), expected, "v1.1.0");
    }

    function _suite200() internal {
        string[5] memory names5 = ["v200-validator", "shared-forwarder", "v200-implementation", "v200-bootstrap", "v200-factory"];
        address[] memory expected = new address[](5);
        expected[0] = 0x00000000d12897DDAdC2044614A9677B191A2d95;
        expected[1] = 0x000000Afe527A978Ecb761008Af475cfF04132a1;
        expected[2] = 0x000000004F43C49e93C970E84001853a70923B03;
        expected[3] = 0x00000000D3254452a909E4eeD47455Af7E27C289;
        expected[4] = 0x000000001D1D5004a02bAfAb9de2D6CE5b7B13de;
        bytes[] memory payloads = new bytes[](5);
        for (uint256 i = 0; i < 5; i++) payloads[i] = _read(names5[i]);
        _deploy(payloads, expected, "v2.0.0");
    }

    function _suite210() internal {
        string[4] memory names4 = ["v210-validator", "v210-implementation", "v210-bootstrap", "v210-factory"];
        address[] memory expected = new address[](4);
        expected[0] = 0x0000000031ef4155C978d48a8A7d4EDba03b04fE;
        expected[1] = 0x00000000383e8cBe298514674Ea60Ee1d1de50ac;
        expected[2] = 0x0000003eDf18913c01cBc482C978bBD3D6E8ffA3;
        expected[3] = 0x0000006648ED9B2B842552BE63Af870bC74af837;
        bytes[] memory payloads = new bytes[](4);
        for (uint256 i = 0; i < 4; i++) payloads[i] = _read(names4[i]);
        _deploy(payloads, expected, "v2.1.0");
    }

    function _payloads6(string[6] memory names) internal view returns (bytes[] memory payloads) {
        payloads = new bytes[](6);
        for (uint256 i = 0; i < 6; i++) payloads[i] = _read(names[i]);
    }

    function _read(string memory name) internal view returns (bytes memory) {
        return vm.parseBytes(vm.readFile(string.concat(DIR, name, ".calldata")));
    }

    function _deploy(bytes[] memory payloads, address[] memory expected, string memory label) internal {
        new SuiteReplayer(payloads, expected);
        console2.log(label, "suite deployed/verified");
    }
}
