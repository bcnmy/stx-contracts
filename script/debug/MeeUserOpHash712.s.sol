// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { MEEUserOpHashLib, MEE_USER_OP_TYPEHASH } from "contracts/lib/stx-validator/MEEUserOpHashLib.sol";
import { HashLib, SUPER_TX_MEE_USER_OP_ARRAY_TYPEHASH, _DOMAIN_TYPEHASH } from "contracts/lib/stx-validator/HashLib.sol";
import { EfficientHashLib } from "solady/utils/EfficientHashLib.sol";
import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

contract MeeUserOpHash712_test_script is Script {

    using EfficientHashLib for *;

    function run() public pure {
        
        /*
        bytes32 userOpHash = bytes32(uint256(0xb487febac9f1d06d0f5510f23ba4b5c52faabfe58ba771cbd62ec551be34e795));
        uint256 lowerBoundTimestamp = uint256(0);
        uint256 upperBoundTimestamp = uint256(0x69303e17);
        bytes32 hash = MEEUserOpHashLib.getMeeUserOpEip712Hash(userOpHash, lowerBoundTimestamp, upperBoundTimestamp);
        console2.logBytes32(hash);
        */

        // testHashingForAccount();
        produceStxHash();
    }



    function produceStxHash() internal pure returns (bytes32) {

        uint256 lowerBoundTimestamp = uint256(0);
        uint256 upperBoundTimestamp = uint256(111);
        
        bytes32 userOpHash1 = 0xb487febac9f1d06d0f5510f23ba4b5c52faabfe58ba771cbd62ec551be34e795;
        bytes32 userOpHash2 = 0xa525b841e423641448ae79b8eb0f60e42baf0cb497278c251dfe49da7dc1da48;
        
        bytes32 meeUserOpHash1 = MEEUserOpHashLib.getMeeUserOpEip712Hash(userOpHash1, lowerBoundTimestamp, upperBoundTimestamp);
        bytes32 meeUserOpHash2 = MEEUserOpHashLib.getMeeUserOpEip712Hash(userOpHash2, lowerBoundTimestamp, upperBoundTimestamp);

        //console2.logBytes32(meeUserOpHash1);
        //console2.logBytes32(meeUserOpHash2);

        bytes32[] memory itemHashes = new bytes32[](2);
        itemHashes[0] = meeUserOpHash1;
        itemHashes[1] = meeUserOpHash2;
        
        uint256 length = itemHashes.length;
        bytes32[] memory a = EfficientHashLib.malloc(length);
        for (uint256 i; i < length; ++i) {
            a.set(i, itemHashes[i]);
        }
        bytes32 encodedData = a.hash();
        bytes32 structHash = EfficientHashLib.hash(SUPER_TX_MEE_USER_OP_ARRAY_TYPEHASH, encodedData);

        string memory name = "Nexus";
        bytes32 nameHash = keccak256(bytes(name));

        bytes32 stxHash = hashTypedDataForAccount1(name, structHash);
        console2.logBytes32(stxHash);
    }


    /////====================   

    function testHashingForAccount() public pure {
        string memory name = "Nexus";
        bytes32 structHash = bytes32(keccak256(abi.encodePacked("test"))); // random struct hash
        
        bytes32 digest1 = hashTypedDataForAccount1(name, structHash);
        console2.logBytes32(digest1);
        bytes32 digest2 = hashTypedDataForAccount2(name, structHash);
        console2.logBytes32(digest2);
    }


    function hashTypedDataForAccount1(string memory name, bytes32 structHash) public pure returns (bytes32) {
        bytes32 digest;
        assembly {
            //Rebuild domain separator out of 712 domain
            let m := mload(0x40) // Load the free memory pointer.
            mstore(m, _DOMAIN_TYPEHASH)
            mstore(add(m, 0x20), keccak256(add(name, 0x20), mload(name))) // Name hash.
            digest := keccak256(m, 0x40) //domain separator

            // Hash typed data
            mstore(0x00, 0x1901000000000000) // Store "\x19\x01".
            mstore(0x1a, digest) // Store the domain separator.
            mstore(0x3a, structHash) // Store the struct hash.
            digest := keccak256(0x18, 0x42)
            // Restore the part of the free memory slot that was overwritten.
            mstore(0x3a, 0)
        }
        return digest;
    }

    function hashTypedDataForAccount2(string memory name, bytes32 structHash) public pure returns (bytes32) {
        bytes32 domainSeparator = keccak256(abi.encodePacked(_DOMAIN_TYPEHASH, keccak256(bytes(name))));

        bytes32 typedDataHash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        return typedDataHash;
    }
}