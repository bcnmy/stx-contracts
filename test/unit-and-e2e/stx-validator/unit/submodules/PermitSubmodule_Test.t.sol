// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test, Vm } from "forge-std/Test.sol";
import { MerkleTreeLib } from "solady/utils/MerkleTreeLib.sol";
import { EfficientHashLib } from "solady/utils/EfficientHashLib.sol";
import { MockERC20PermitToken } from "test/mock/tokens/MockERC20PermitToken.sol";
import {
    PermitSubmodule,
    DecodedErc20PermitSig,
    DecodedErc20PermitSigShort,
    PERMIT_TYPEHASH
} from "contracts/validators/stx-validator/submodules/PermitSubmodule.sol";
import { IStxModeVerifier } from "contracts/interfaces/stx-validator/IStxModeVerifier.sol";
import { MEEUserOpHashLib } from "contracts/lib/stx-validator/MEEUserOpHashLib.sol";
import { EcdsaHelperLib } from "contracts/lib/util/EcdsaHelperLib.sol";
import { HashLib } from "contracts/lib/stx-validator/HashLib.sol";

/// @title PermitSubmodule Unit Tests
/// @notice Unit tests for PermitSubmodule functionality
/// @dev Tests individual functions in isolation. E2E tests are in StxValidator_Permit_Mode_Test.t.sol
contract PermitSubmodule_Test is Test {
    using MerkleTreeLib for bytes32[];

    PermitSubmodule internal permitSubmodule;
    MockERC20PermitToken internal token;
    Vm.Wallet internal signer;

    address internal smartAccount;
    address internal spender;

    function setUp() public {
        permitSubmodule = new PermitSubmodule();
        token = new MockERC20PermitToken("TestToken", "TEST");
        signer = vm.createWallet("signer");
        smartAccount = makeAddr("smartAccount");
        spender = makeAddr("spender");

        // Mint tokens to signer for permit tests
        deal(address(token), signer.addr, 1000 ether);
    }

    /*//////////////////////////////////////////////////////////////////////////
                        PROCESS STX USER OP DATA TESTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Test AA-4337 backwards compatibility flow (65-byte signature)
    /// @dev When sigData.length == 65, returns (0, 0, userOpHash, sigData) unchanged
    function test_processStxUserOpData_backwardsCompatibility_65ByteSignature() public {
        bytes32 userOpHash = keccak256("userOpHash");
        bytes memory sigData = abi.encodePacked(bytes32(uint256(1)), bytes32(uint256(2)), uint8(27));
        assertEq(sigData.length, 65);

        bytes memory result = permitSubmodule.processStxUserOpData(smartAccount, userOpHash, sigData);

        (uint48 lowerBound, uint48 upperBound, bytes32 returnedHash, bytes memory returnedSig) =
            abi.decode(result, (uint48, uint48, bytes32, bytes));

        assertEq(lowerBound, 0);
        assertEq(upperBound, 0);
        assertEq(returnedHash, userOpHash);
        assertEq(returnedSig, sigData);
    }

    /// @notice Test that invalid merkle proof reverts with MerkleVerificationFailed
    function test_processStxUserOpData_revertWhen_invalidMerkleProof() public {
        bytes32 userOpHash = keccak256("userOpHash");
        uint48 lowerBound = uint48(block.timestamp);
        uint48 upperBound = uint48(block.timestamp + 1000);

        // Create a valid permit signature
        (bytes memory permitSig, bytes32 superTxHash) = _createPermitSignature(1 ether);

        // Create an invalid proof (empty or wrong)
        bytes32[] memory invalidProof = new bytes32[](1);
        invalidProof[0] = keccak256("wrong proof");

        bytes memory sigData = abi.encode(
            DecodedErc20PermitSig({
                token: token,
                owner: signer.addr,
                spender: spender,
                domainSeparator: token.DOMAIN_SEPARATOR(),
                amount: 1 ether,
                nonce: token.nonces(signer.addr),
                isPermitTx: true,
                superTxHash: superTxHash,
                lowerBoundTimestamp: lowerBound,
                upperBoundTimestamp: upperBound,
                signature: permitSig,
                proof: invalidProof
            })
        );

        vm.expectRevert(IStxModeVerifier.MerkleVerificationFailed.selector);
        permitSubmodule.processStxUserOpData(smartAccount, userOpHash, sigData);
    }

    /// @notice Test isPermitTx=false path skips permit call
    /// @dev When isPermitTx=false, the permit() call is skipped
    function test_processStxUserOpData_isPermitTxFalse_skipsPermitCall() public {
        bytes32 userOpHash = keccak256("userOpHash");
        uint48 lowerBound = uint48(block.timestamp);
        uint48 upperBound = uint48(block.timestamp + 1000);

        // Build merkle tree with single leaf
        bytes32 meeUserOpHash = MEEUserOpHashLib.getMeeUserOpHash(userOpHash, lowerBound, upperBound);
        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = meeUserOpHash;
        bytes32[] memory tree = leaves.build();
        bytes32 superTxHash = tree.root();

        // Create permit signature with superTxHash as deadline
        (bytes memory permitSig,) = _createPermitSignatureWithRoot(1 ether, superTxHash);

        bytes32[] memory proof = tree.leafProof(0);

        bytes memory sigData = abi.encode(
            DecodedErc20PermitSig({
                token: token,
                owner: signer.addr,
                spender: spender,
                domainSeparator: token.DOMAIN_SEPARATOR(),
                amount: 1 ether,
                nonce: token.nonces(signer.addr),
                isPermitTx: false, // Skip permit call
                superTxHash: superTxHash,
                lowerBoundTimestamp: lowerBound,
                upperBoundTimestamp: upperBound,
                signature: permitSig,
                proof: proof
            })
        );

        // Should not revert and allowance should remain 0 (permit not called)
        uint256 allowanceBefore = token.allowance(signer.addr, spender);
        permitSubmodule.processStxUserOpData(smartAccount, userOpHash, sigData);
        uint256 allowanceAfter = token.allowance(signer.addr, spender);

        assertEq(allowanceBefore, 0);
        assertEq(allowanceAfter, 0); // Permit was NOT called
    }

    /// @notice Test isPermitTx=true executes permit successfully
    function test_processStxUserOpData_isPermitTxTrue_executesPermit() public {
        bytes32 userOpHash = keccak256("userOpHash");
        uint48 lowerBound = uint48(block.timestamp);
        uint48 upperBound = uint48(block.timestamp + 1000);

        // Build merkle tree with single leaf
        bytes32 meeUserOpHash = MEEUserOpHashLib.getMeeUserOpHash(userOpHash, lowerBound, upperBound);
        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = meeUserOpHash;
        bytes32[] memory tree = leaves.build();
        bytes32 superTxHash = tree.root();

        uint256 amount = 1 ether;
        (bytes memory permitSig,) = _createPermitSignatureWithRoot(amount, superTxHash);

        bytes32[] memory proof = tree.leafProof(0);

        bytes memory sigData = abi.encode(
            DecodedErc20PermitSig({
                token: token,
                owner: signer.addr,
                spender: spender,
                domainSeparator: token.DOMAIN_SEPARATOR(),
                amount: amount,
                nonce: token.nonces(signer.addr),
                isPermitTx: true, // Execute permit
                superTxHash: superTxHash,
                lowerBoundTimestamp: lowerBound,
                upperBoundTimestamp: upperBound,
                signature: permitSig,
                proof: proof
            })
        );

        uint256 allowanceBefore = token.allowance(signer.addr, spender);
        permitSubmodule.processStxUserOpData(smartAccount, userOpHash, sigData);
        uint256 allowanceAfter = token.allowance(signer.addr, spender);

        assertEq(allowanceBefore, 0);
        assertEq(allowanceAfter, amount); // Permit was called
    }

    /// @notice Test permit failure reverts with PermitFailed when no existing allowance
    /// @dev When permit() fails (wrong signer) AND allowance < amount, reverts with PermitFailed
    function test_processStxUserOpData_permitFailsWithWrongSigner_reverts() public {
        bytes32 userOpHash = keccak256("userOpHash");
        uint48 lowerBound = uint48(block.timestamp);
        uint48 upperBound = uint48(block.timestamp + 1000);

        assertEq(token.allowance(signer.addr, spender), 0);

        // Build merkle tree
        bytes32 meeUserOpHash = MEEUserOpHashLib.getMeeUserOpHash(userOpHash, lowerBound, upperBound);
        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = meeUserOpHash;
        bytes32[] memory tree = leaves.build();
        bytes32 superTxHash = tree.root();

        uint256 amount = 1 ether;

        // Create an INVALID permit signature (wrong signer)
        Vm.Wallet memory wrongSigner = vm.createWallet("wrongSigner");
        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, signer.addr, spender, amount, token.nonces(signer.addr), superTxHash)
        );
        bytes32 digest = EcdsaHelperLib.toTypedDataHash(token.DOMAIN_SEPARATOR(), structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongSigner.privateKey, digest);
        bytes memory invalidPermitSig = abi.encodePacked(r, s, v);

        bytes32[] memory proof = tree.leafProof(0);

        bytes memory sigData = abi.encode(
            DecodedErc20PermitSig({
                token: token,
                owner: signer.addr,
                spender: spender,
                domainSeparator: token.DOMAIN_SEPARATOR(),
                amount: amount,
                nonce: token.nonces(signer.addr),
                isPermitTx: true,
                superTxHash: superTxHash,
                lowerBoundTimestamp: lowerBound,
                upperBoundTimestamp: upperBound,
                signature: invalidPermitSig,
                proof: proof
            })
        );

        // Permit will fail (wrong signature) AND allowance is 0 (insufficient)
        vm.expectRevert(PermitSubmodule.PermitFailed.selector);
        permitSubmodule.processStxUserOpData(smartAccount, userOpHash, sigData);
    }

    /// @notice Test permit failure but sufficient allowance does NOT revert (allowance fallback)
    function test_processStxUserOpData_permitFailsButSufficientAllowance_doesNotRevert() public {
        bytes32 userOpHash = keccak256("userOpHash");
        uint48 lowerBound = uint48(block.timestamp);
        uint48 upperBound = uint48(block.timestamp + 1000);

        // Build merkle tree
        bytes32 meeUserOpHash = MEEUserOpHashLib.getMeeUserOpHash(userOpHash, lowerBound, upperBound);
        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = meeUserOpHash;
        bytes32[] memory tree = leaves.build();
        bytes32 superTxHash = tree.root();

        uint256 amount = 1 ether;

        // Pre-approve the spender (simulate permit already used)
        vm.prank(signer.addr);
        token.approve(spender, amount);

        // Create an INVALID permit signature that will fail
        Vm.Wallet memory wrongSigner = vm.createWallet("wrongSigner");
        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, signer.addr, spender, amount, token.nonces(signer.addr), superTxHash)
        );
        bytes32 digest = EcdsaHelperLib.toTypedDataHash(token.DOMAIN_SEPARATOR(), structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongSigner.privateKey, digest);
        bytes memory invalidPermitSig = abi.encodePacked(r, s, v);

        bytes32[] memory proof = tree.leafProof(0);

        bytes memory sigData = abi.encode(
            DecodedErc20PermitSig({
                token: token,
                owner: signer.addr,
                spender: spender,
                domainSeparator: token.DOMAIN_SEPARATOR(),
                amount: amount,
                nonce: token.nonces(signer.addr),
                isPermitTx: true,
                superTxHash: superTxHash,
                lowerBoundTimestamp: lowerBound,
                upperBoundTimestamp: upperBound,
                signature: invalidPermitSig,
                proof: proof
            })
        );

        // Should NOT revert because allowance is sufficient
        permitSubmodule.processStxUserOpData(smartAccount, userOpHash, sigData);
    }

    /// @notice Test that processStxUserOpData returns correct encoded data
    function test_processStxUserOpData_returnsCorrectEncodedData() public {
        bytes32 userOpHash = keccak256("userOpHash");
        uint48 lowerBound = uint48(block.timestamp);
        uint48 upperBound = uint48(block.timestamp + 1000);

        // Build merkle tree
        bytes32 meeUserOpHash = MEEUserOpHashLib.getMeeUserOpHash(userOpHash, lowerBound, upperBound);
        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = meeUserOpHash;
        bytes32[] memory tree = leaves.build();
        bytes32 superTxHash = tree.root();

        uint256 amount = 1 ether;
        uint256 nonce = token.nonces(signer.addr);
        (bytes memory permitSig,) = _createPermitSignatureWithRoot(amount, superTxHash);

        bytes32[] memory proof = tree.leafProof(0);

        bytes memory sigData = abi.encode(
            DecodedErc20PermitSig({
                token: token,
                owner: signer.addr,
                spender: spender,
                domainSeparator: token.DOMAIN_SEPARATOR(),
                amount: amount,
                nonce: nonce,
                isPermitTx: false,
                superTxHash: superTxHash,
                lowerBoundTimestamp: lowerBound,
                upperBoundTimestamp: upperBound,
                signature: permitSig,
                proof: proof
            })
        );

        bytes memory result = permitSubmodule.processStxUserOpData(smartAccount, userOpHash, sigData);

        (uint48 returnedLower, uint48 returnedUpper, bytes32 returnedHash, bytes memory returnedSig) =
            abi.decode(result, (uint48, uint48, bytes32, bytes));

        // Calculate expected signed data hash
        bytes32 expectedStructHash = _hashPermitDataStruct(signer.addr, spender, amount, nonce, superTxHash);
        bytes32 expectedSignedHash = EcdsaHelperLib.toTypedDataHash(token.DOMAIN_SEPARATOR(), expectedStructHash);

        assertEq(returnedLower, lowerBound);
        assertEq(returnedUpper, upperBound);
        assertEq(returnedHash, expectedSignedHash);
        assertEq(returnedSig, permitSig);
    }

    /*//////////////////////////////////////////////////////////////////////////
                        PROCESS STX DATA OBJECT TESTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Test that processStxDataObject reverts on invalid merkle proof
    function test_processStxDataObject_revertWhen_invalidMerkleProof() public {
        bytes32 dataHash = keccak256("dataHash");

        // Create permit signature
        (bytes memory permitSig, bytes32 superTxHash) = _createPermitSignature(1 ether);

        // Create invalid proof
        bytes32[] memory invalidProof = new bytes32[](1);
        invalidProof[0] = keccak256("wrong proof");

        bytes memory sigData = abi.encode(
            DecodedErc20PermitSigShort({
                owner: signer.addr,
                spender: spender,
                domainSeparator: token.DOMAIN_SEPARATOR(),
                amount: 1 ether,
                nonce: token.nonces(signer.addr),
                superTxHash: superTxHash,
                signature: permitSig,
                proof: invalidProof
            })
        );

        vm.expectRevert(IStxModeVerifier.MerkleVerificationFailed.selector);
        permitSubmodule.processStxDataObject(smartAccount, address(0), dataHash, sigData);
    }

    /// @notice Test that processStxDataObject rehashes with account and chainId
    /// @dev Protection against "two accounts, same owner" attack
    function test_processStxDataObject_rehashesWithAccountAndChainId() public view {
        bytes32 dataHash = keccak256("dataHash");

        // The entry hash is rehashed with account and chainId
        bytes32 entryHash = HashLib.rehashWithAccountAndChainId(dataHash, smartAccount, block.chainid);

        // Build merkle tree with rehashed entry
        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = entryHash;
        bytes32[] memory tree = leaves.build();
        bytes32 superTxHash = tree.root();

        uint256 amount = 1 ether;
        uint256 nonce = token.nonces(signer.addr);
        (bytes memory permitSig,) = _createPermitSignatureWithRoot(amount, superTxHash);

        bytes32[] memory proof = tree.leafProof(0);

        bytes memory sigData = abi.encode(
            DecodedErc20PermitSigShort({
                owner: signer.addr,
                spender: spender,
                domainSeparator: token.DOMAIN_SEPARATOR(),
                amount: amount,
                nonce: nonce,
                superTxHash: superTxHash,
                signature: permitSig,
                proof: proof
            })
        );

        // Should NOT revert - proof is valid for rehashed entry
        (bytes32 returnedHash, bytes memory returnedSig) =
            permitSubmodule.processStxDataObject(smartAccount, address(0), dataHash, sigData);

        // Verify returned hash is the permit typed data hash
        bytes32 expectedStructHash = _hashPermitDataStruct(signer.addr, spender, amount, nonce, superTxHash);
        bytes32 expectedHash = EcdsaHelperLib.toTypedDataHash(token.DOMAIN_SEPARATOR(), expectedStructHash);

        assertEq(returnedHash, expectedHash);
        assertEq(returnedSig, permitSig);
    }

    /// @notice Test that processStxDataObject fails if raw dataHash is used (not rehashed)
    function test_processStxDataObject_failsWithoutRehashing() public {
        bytes32 dataHash = keccak256("dataHash");

        // Build merkle tree with raw dataHash (NOT rehashed) - this is WRONG
        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = dataHash; // Should be rehashed but isn't
        bytes32[] memory tree = leaves.build();
        bytes32 superTxHash = tree.root();

        (bytes memory permitSig,) = _createPermitSignatureWithRoot(1 ether, superTxHash);

        bytes32[] memory proof = tree.leafProof(0);

        bytes memory sigData = abi.encode(
            DecodedErc20PermitSigShort({
                owner: signer.addr,
                spender: spender,
                domainSeparator: token.DOMAIN_SEPARATOR(),
                amount: 1 ether,
                nonce: token.nonces(signer.addr),
                superTxHash: superTxHash,
                signature: permitSig,
                proof: proof
            })
        );

        // Should revert because the proof is for raw dataHash, not rehashed
        vm.expectRevert(IStxModeVerifier.MerkleVerificationFailed.selector);
        permitSubmodule.processStxDataObject(smartAccount, address(0), dataHash, sigData);
    }

    /*//////////////////////////////////////////////////////////////////////////
                    PROCESS STX DATA OBJECT FOR 7780 FLOW TESTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Test that processStxDataObjectFor7780Flow reverts on invalid merkle proof
    function test_processStxDataObjectFor7780Flow_revertWhen_invalidMerkleProof() public {
        bytes32 dataHash = keccak256("dataHash");

        (bytes memory permitSig, bytes32 superTxHash) = _createPermitSignature(1 ether);

        bytes32[] memory invalidProof = new bytes32[](1);
        invalidProof[0] = keccak256("wrong proof");

        bytes memory sigData = abi.encode(
            DecodedErc20PermitSigShort({
                owner: signer.addr,
                spender: spender,
                domainSeparator: token.DOMAIN_SEPARATOR(),
                amount: 1 ether,
                nonce: token.nonces(signer.addr),
                superTxHash: superTxHash,
                signature: permitSig,
                proof: invalidProof
            })
        );

        vm.expectRevert(IStxModeVerifier.MerkleVerificationFailed.selector);
        permitSubmodule.processStxDataObjectFor7780Flow(smartAccount, dataHash, sigData);
    }

    /// @notice Test that processStxDataObjectFor7780Flow does NOT rehash (unlike processStxDataObject)
    function test_processStxDataObjectFor7780Flow_doesNotRehash() public view {
        bytes32 dataHash = keccak256("dataHash");

        // Build merkle tree with raw dataHash (no rehashing in 7780 flow)
        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = dataHash; // Raw hash, NOT rehashed
        bytes32[] memory tree = leaves.build();
        bytes32 superTxHash = tree.root();

        uint256 amount = 1 ether;
        uint256 nonce = token.nonces(signer.addr);
        (bytes memory permitSig,) = _createPermitSignatureWithRoot(amount, superTxHash);

        bytes32[] memory proof = tree.leafProof(0);

        bytes memory sigData = abi.encode(
            DecodedErc20PermitSigShort({
                owner: signer.addr,
                spender: spender,
                domainSeparator: token.DOMAIN_SEPARATOR(),
                amount: amount,
                nonce: nonce,
                superTxHash: superTxHash,
                signature: permitSig,
                proof: proof
            })
        );

        // Should NOT revert - 7780 flow uses raw dataHash
        (bytes32 returnedHash, bytes memory returnedSig) =
            permitSubmodule.processStxDataObjectFor7780Flow(smartAccount, dataHash, sigData);

        bytes32 expectedStructHash = _hashPermitDataStruct(signer.addr, spender, amount, nonce, superTxHash);
        bytes32 expectedHash = EcdsaHelperLib.toTypedDataHash(token.DOMAIN_SEPARATOR(), expectedStructHash);

        assertEq(returnedHash, expectedHash);
        assertEq(returnedSig, permitSig);
    }

    /// @notice Test that 7780 flow would fail with rehashed hash (proving no rehashing occurs)
    function test_processStxDataObjectFor7780Flow_failsWithRehashedHash() public {
        bytes32 dataHash = keccak256("dataHash");

        // Build merkle tree with REHASHED entry (wrong for 7780 flow)
        bytes32 rehashedEntry = HashLib.rehashWithAccountAndChainId(dataHash, smartAccount, block.chainid);
        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = rehashedEntry;
        bytes32[] memory tree = leaves.build();
        bytes32 superTxHash = tree.root();

        (bytes memory permitSig,) = _createPermitSignatureWithRoot(1 ether, superTxHash);

        bytes32[] memory proof = tree.leafProof(0);

        bytes memory sigData = abi.encode(
            DecodedErc20PermitSigShort({
                owner: signer.addr,
                spender: spender,
                domainSeparator: token.DOMAIN_SEPARATOR(),
                amount: 1 ether,
                nonce: token.nonces(signer.addr),
                superTxHash: superTxHash,
                signature: permitSig,
                proof: proof
            })
        );

        // Should revert because 7780 flow expects raw dataHash, not rehashed
        vm.expectRevert(IStxModeVerifier.MerkleVerificationFailed.selector);
        permitSubmodule.processStxDataObjectFor7780Flow(smartAccount, dataHash, sigData);
    }

    /*//////////////////////////////////////////////////////////////////////////
                            SIGNED DATA HASH TESTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Test that the signed data hash is correctly computed with PERMIT_TYPEHASH
    function test_signedDataHash_usesCorrectPermitTypehash() public view {
        bytes32 dataHash = keccak256("dataHash");

        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = dataHash;
        bytes32[] memory tree = leaves.build();
        bytes32 superTxHash = tree.root();

        uint256 amount = 123 ether;
        uint256 nonce = 42;

        // Create permit signature with specific values
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, signer.addr, spender, amount, nonce, superTxHash));
        bytes32 digest = EcdsaHelperLib.toTypedDataHash(token.DOMAIN_SEPARATOR(), structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer.privateKey, digest);
        bytes memory permitSig = abi.encodePacked(r, s, v);

        bytes32[] memory proof = tree.leafProof(0);

        bytes memory sigData = abi.encode(
            DecodedErc20PermitSigShort({
                owner: signer.addr,
                spender: spender,
                domainSeparator: token.DOMAIN_SEPARATOR(),
                amount: amount,
                nonce: nonce,
                superTxHash: superTxHash,
                signature: permitSig,
                proof: proof
            })
        );

        (bytes32 returnedHash,) = permitSubmodule.processStxDataObjectFor7780Flow(smartAccount, dataHash, sigData);

        // Manually compute expected hash
        bytes32 expectedStructHash = _hashPermitDataStruct(signer.addr, spender, amount, nonce, superTxHash);
        bytes32 expectedHash = EcdsaHelperLib.toTypedDataHash(token.DOMAIN_SEPARATOR(), expectedStructHash);

        assertEq(returnedHash, expectedHash);
    }

    /*//////////////////////////////////////////////////////////////////////////
                            FUZZ TESTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Fuzz test for 65-byte backwards compatibility
    function testFuzz_processStxUserOpData_65ByteSignature(bytes32 userOpHash, bytes32 r, bytes32 s, uint8 v) public {
        bytes memory sigData = abi.encodePacked(r, s, v);
        assertEq(sigData.length, 65);

        bytes memory result = permitSubmodule.processStxUserOpData(smartAccount, userOpHash, sigData);

        (uint48 lowerBound, uint48 upperBound, bytes32 returnedHash, bytes memory returnedSig) =
            abi.decode(result, (uint48, uint48, bytes32, bytes));

        assertEq(lowerBound, 0);
        assertEq(upperBound, 0);
        assertEq(returnedHash, userOpHash);
        assertEq(returnedSig, sigData);
    }

    /// @notice Fuzz test that permit executes successfully with various amounts
    function testFuzz_processStxUserOpData_permitExecutesWithVariousAmounts(uint256 amount) public {
        // Bound amount to reasonable range (avoid 0 which might have edge cases)
        amount = bound(amount, 1, type(uint128).max);

        bytes32 userOpHash = keccak256("userOpHash");
        uint48 lowerBound = uint48(block.timestamp);
        uint48 upperBound = uint48(block.timestamp + 1000);

        // Build merkle tree
        bytes32 meeUserOpHash = MEEUserOpHashLib.getMeeUserOpHash(userOpHash, lowerBound, upperBound);
        bytes32[] memory leaves = new bytes32[](1);
        leaves[0] = meeUserOpHash;
        bytes32[] memory tree = leaves.build();
        bytes32 superTxHash = tree.root();

        uint256 nonce = token.nonces(signer.addr);
        (bytes memory permitSig,) = _createPermitSignatureWithRootAndAmount(amount, superTxHash);

        bytes32[] memory proof = tree.leafProof(0);

        bytes memory sigData = abi.encode(
            DecodedErc20PermitSig({
                token: token,
                owner: signer.addr,
                spender: spender,
                domainSeparator: token.DOMAIN_SEPARATOR(),
                amount: amount,
                nonce: nonce,
                isPermitTx: true, // Execute permit
                superTxHash: superTxHash,
                lowerBoundTimestamp: lowerBound,
                upperBoundTimestamp: upperBound,
                signature: permitSig,
                proof: proof
            })
        );

        // Verify allowance is 0 before
        assertEq(token.allowance(signer.addr, spender), 0);

        // Execute permit
        permitSubmodule.processStxUserOpData(smartAccount, userOpHash, sigData);

        // Verify allowance is set to amount after permit
        assertEq(token.allowance(signer.addr, spender), amount);
    }

    /*//////////////////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    function _createPermitSignature(uint256 amount) internal view returns (bytes memory sig, bytes32 superTxHash) {
        superTxHash = keccak256("superTxHash");
        return _createPermitSignatureWithRoot(amount, superTxHash);
    }

    function _createPermitSignatureWithRoot(
        uint256 amount,
        bytes32 root
    )
        internal
        view
        returns (bytes memory sig, bytes32)
    {
        bytes32 structHash =
            keccak256(abi.encode(PERMIT_TYPEHASH, signer.addr, spender, amount, token.nonces(signer.addr), root));
        bytes32 digest = EcdsaHelperLib.toTypedDataHash(token.DOMAIN_SEPARATOR(), structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer.privateKey, digest);
        return (abi.encodePacked(r, s, v), root);
    }

    function _createPermitSignatureWithRootAndAmount(
        uint256 amount,
        bytes32 root
    )
        internal
        view
        returns (bytes memory sig, bytes32)
    {
        bytes32 structHash =
            keccak256(abi.encode(PERMIT_TYPEHASH, signer.addr, spender, amount, token.nonces(signer.addr), root));
        bytes32 digest = EcdsaHelperLib.toTypedDataHash(token.DOMAIN_SEPARATOR(), structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer.privateKey, digest);
        return (abi.encodePacked(r, s, v), root);
    }

    function _hashPermitDataStruct(
        address owner,
        address _spender,
        uint256 amount,
        uint256 nonce,
        bytes32 superTxHash
    )
        internal
        pure
        returns (bytes32)
    {
        return EfficientHashLib.hash(
            uint256(PERMIT_TYPEHASH),
            uint256(uint160(owner)),
            uint256(uint160(_spender)),
            amount,
            nonce,
            uint256(superTxHash)
        );
    }
}
