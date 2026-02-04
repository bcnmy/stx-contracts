// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Vm } from "forge-std/Test.sol";
import { StxValidator_Base_Test } from "../../../unit/stx-validator/StxValidator_Base_Test.t.sol";
import { StxValidator } from "contracts/validators/stx-validator/StxValidator.sol";
import { P256StatelessValidator } from "contracts/validators/stx-validator/submodules/p256/P256StatelessValidator.sol";
import { SimpleModeSubmodule } from "contracts/validators/stx-validator/submodules/SimpleModeSubmodule.sol";

contract P256StatelessValidator_Fork_Test is StxValidator_Base_Test {
    address constant RIP_7212_PRECOMPILE = address(0x100);

    uint256 internal p256PublicKeyX;
    uint256 internal p256PublicKeyY;
    bytes internal p256ValidationData;
    bytes internal p256Signature;
    bytes internal p256InvalidSignature;
    bytes32 internal hashToSign;

    uint256 mainnet;
    uint256 optimism;
    uint256 polygon;

    function setUp() public virtual override {
        super.setUp();

        string memory ethereumRpcUrl = vm.envString("RPC_1");
        string memory optimismRpcUrl = vm.envString("RPC_10");
        string memory polygonRpcUrl = vm.envString("RPC_137");

        mainnet = vm.createFork(ethereumRpcUrl);
        optimism = vm.createFork(optimismRpcUrl);
        polygon = vm.createFork(polygonRpcUrl);

        // create a p256 signer
        (p256PublicKeyX, p256PublicKeyY) = vm.publicKeyP256(wallet.privateKey);
        p256ValidationData = abi.encodePacked(p256PublicKeyX, p256PublicKeyY);

        hashToSign = keccak256(abi.encodePacked("test"));
        (bytes32 r, bytes32 s) = vm.signP256(wallet.privateKey, hashToSign);
        p256Signature = abi.encodePacked(r, s);
        p256InvalidSignature = abi.encodePacked(r, uint256(s) + 1);

        vm.selectFork(mainnet);
        _prepareFork(true);

        vm.selectFork(optimism);
        _prepareFork(true);

        vm.selectFork(polygon);
        _prepareFork(false); // IRL, Polygon hash no precompile at the time of writing this test
    }

    function _prepareFork(bool etchP25Precompile) public {
        vm.startPrank(address(0xa11ce));
        p256StatelessValidator = new P256StatelessValidator();
        vm.stopPrank();

        if (etchP25Precompile) {
            // p256StatelessValidator mimics the real precompile interface with its fallback function
            vm.etch(RIP_7212_PRECOMPILE, address(p256StatelessValidator).code);
        }
    }

    function test_etched_precompile_mimics_real_precompile() public {
        // this is a real data : hash, r, s, x, y
        // you can test it is valid by calling
        // cast call 0x0000000000000000000000000000000000000100 $DATA --rpc_url $MAINNET_URL
        bytes memory testData =
            hex"bb5a52f42f9c9261ed4361f59422a1e30036e7c32b270c8807a419feca6050232ba3a8be6b94d5ec80a6d9d1190a436effe50d85a1eee859b8cc6af9bd5c2e184cd60b855d442f5b3c7b11eb6c4e0ae7525fe710fab9aa7c77a67f79e6fadd762927b10512bae3eddcfe467828128bad2903269919f7086069c8c4df6c732838c7787964eaac00e5921fb1498a60f4606766b3d9685001558d1a974e7341513e";

        //expected etched precompile to return true
        vm.selectFork(mainnet);
        assertTrue(_isValidP256SigViaPrecompile(testData));
        vm.selectFork(optimism);
        assertTrue(_isValidP256SigViaPrecompile(testData));
        vm.selectFork(polygon);
        assertFalse(_isValidP256SigViaPrecompile(testData));
    }

    function test_P256StatelessValidator_returns_true_for_valid_signature_with_precompile() public {
        vm.selectFork(mainnet);
        assertTrue(p256StatelessValidator.validateSignatureWithData(hashToSign, p256Signature, p256ValidationData));
        // assert it is reproducible on other forks with precompile deployed
        vm.selectFork(optimism);
        assertTrue(p256StatelessValidator.validateSignatureWithData(hashToSign, p256Signature, p256ValidationData));
    }

    function test_P256StatelessValidator_returns_true_for_valid_signature_via_solidity_fallback() public {
        // even though the precompile is not deployed, the fallback should be used
        // and should return true for the valid signature
        vm.selectFork(polygon);
        assertTrue(p256StatelessValidator.validateSignatureWithData(hashToSign, p256Signature, p256ValidationData));
    }

    function test_P256StatelessValidator_returns_false_for_invalid_signature_with_precompile() public {
        vm.selectFork(mainnet);
        assertFalse(
            p256StatelessValidator.validateSignatureWithData(hashToSign, p256InvalidSignature, p256ValidationData)
        );
        // assert it is reproducible on other forks with precompile deployed
        vm.selectFork(optimism);
        assertFalse(
            p256StatelessValidator.validateSignatureWithData(hashToSign, p256InvalidSignature, p256ValidationData)
        );
    }

    function test_P256StatelessValidator_returns_false_for_invalid_signature_via_solidity_fallback() public {
        // even though the precompile is not deployed, the fallback should be used
        // and should return false for the invalid signature
        vm.selectFork(polygon);
        assertFalse(
            p256StatelessValidator.validateSignatureWithData(hashToSign, p256InvalidSignature, p256ValidationData)
        );
    }

    function _isValidP256SigViaPrecompile(bytes memory data) internal returns (bool) {
        (bool success, bytes memory ret) = RIP_7212_PRECOMPILE.staticcall(data);
        return success && ret.length > 0 && abi.decode(ret, (uint256)) == 1;
    }
}
