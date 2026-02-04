// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Vm, console2 } from "forge-std/Test.sol";
import { StxValidator_Base_Test } from "./StxValidator_Base_Test.t.sol";
import { PackedUserOperation } from "account-abstraction/core/UserOperationLib.sol";
import { CopyUserOpLib } from "../../util/CopyUserOpLib.sol";
import { MockTarget } from "test/mock/MockTarget.sol";
import { HashLib } from "contracts/lib/stx-validator/HashLib.sol";
import { MEEUserOpHashLib } from "contracts/lib/stx-validator/MEEUserOpHashLib.sol";
import "contracts/types/Constants.sol";
import { EcdsaHelperLib } from "contracts/lib/util/EcdsaHelperLib.sol";

contract StxValidator_Simple_Mode_Test is StxValidator_Base_Test {
    using CopyUserOpLib for PackedUserOperation;

    error InvalidSignatureTypeForSimpleMode();

    bytes internal p256ValidationData;
    uint256 internal p256PublicKeyX;
    uint256 internal p256PublicKeyY;

    // some random domain separator
    bytes32 internal constant APP_DOMAIN_SEPARATOR = 0xa1a044077d7677adbbfa892ded5390979b33993e0e2a457e3f974bbcda53821b;

    bytes internal defaultConfigData;

    function setUp() public virtual override {
        super.setUp();

        (p256PublicKeyX, p256PublicKeyY) = vm.publicKeyP256(wallet.privateKey);
        p256ValidationData = abi.encodePacked(p256PublicKeyX, p256PublicKeyY);

        vm.startPrank(address(mockAccount));

        defaultConfigData = abi.encodePacked(address(eoaStatelessValidator), uint8(0), abi.encodePacked(wallet.addr));

        // set the default config
        stxValidator.onInstall(defaultConfigData);

        stxValidator.setOwnershipData(address(p256StatelessValidator), p256ValidationData);
        vm.stopPrank();
    }

    function test_stxValidator_simple_mode_ValidateUserOp_with_MeeUserOps_only_as_entries_EOAsig_success(uint256 numOfClones)
        public
    {
        numOfClones = bound(numOfClones, 1, 25);
        _validateUserOp_with_MeeUserOps_only_as_entries(numOfClones, 500_000, _signWithSecp256k1);
    }

    function test_stxValidator_simple_mode_ValidateUserOp_with_MeeUserOps_only_as_entries_P256Sig_success(uint256 numOfClones)
        public
    {
        numOfClones = bound(numOfClones, 1, 25);

        _validateUserOp_with_MeeUserOps_only_as_entries(numOfClones, 900_000, _signWithP256);
    }

    function _validateUserOp_with_MeeUserOps_only_as_entries(
        uint256 numOfClones,
        uint256 verificationGasLimit,
        function(Vm.Wallet memory, bytes32) internal view returns (bytes memory) signatureFunction
    )
        internal
    {
        uint256 counterBefore = mockTarget.counter();
        bytes memory innerCallData = abi.encodeWithSelector(MockTarget.incrementCounter.selector);
        PackedUserOperation memory userOp = buildBasicMEEUserOpWithCalldata({
            callData: abi.encodeWithSelector(
                mockAccount.execute.selector, address(mockTarget), uint256(0), innerCallData
            ),
            account: address(mockAccount),
            userOpSigner: wallet
        });

        // repack new verificationGasLimit into accountGasLimits
        uint128 callGasLimit = uint128(unpackCallGasLimitMemory(userOp));
        userOp.accountGasLimits = bytes32(abi.encodePacked(uint128(verificationGasLimit), callGasLimit)); // verification
        // and call

        PackedUserOperation[] memory userOps = _cloneUserOpToAnArray(userOp, wallet, numOfClones);

        userOps = _makeSimpleSuperTxWithMeeUserOpsOnlyAsEntries({
            userOps: userOps,
            superTxSigner: wallet,
            smartAccount: address(mockAccount),
            signatureFunction: signatureFunction
        });

        vm.startPrank(MEE_NODE_EXECUTOR_EOA, MEE_NODE_EXECUTOR_EOA);
        ENTRYPOINT.handleOps(userOps, payable(MEE_NODE_ADDRESS));
        vm.stopPrank();
        assertEq(mockTarget.counter(), counterBefore + userOps.length);
    }

    // Now test SuperTx with mixed types of entries
    function test_StxValidator_simple_mode_ERC1271_ERC7739_with_MixedTypes_EOASig_success(uint256 numOfClones) public {
        numOfClones = bound(numOfClones, 1, 9);

        (, NonUserOpEntryData[] memory nonUserOpEntryDatas) = _prepareDataAndDoUserOpValidation({
            numOfClones: numOfClones,
            applyErc7739: true,
            verificationGasLimit: 500_000,
            signatureFunction: _signWithSecp256k1
        });

        // Now validate the rest of the entries via - isValidSignature  (expect it to go via erc-7739)
        for (uint256 i; i < nonUserOpEntryDatas.length; i++) {
            assertTrue(
                mockAccount.isValidSignature(
                    nonUserOpEntryDatas[i].entryHash, nonUserOpEntryDatas[i].packedSignatureForEntry
                ) == ERC1271_SUCCESS
            );
        }
    }

    function test_StxValidator_simple_mode_ERC1271_ERC7739_with_MixedTypes_P256Sig_success(uint256 numOfClones) public {
        numOfClones = bound(numOfClones, 1, 9);

        vm.prank(address(mockAccount));
        /*
        stxValidator.replaceConfig(
            bytes32(0), address(simpleModeSubmodule), address(p256StatelessValidator), p256ValidationData
        );
        */

        (, NonUserOpEntryData[] memory nonUserOpEntryDatas) = _prepareDataAndDoUserOpValidation({
            numOfClones: numOfClones,
            applyErc7739: true,
            verificationGasLimit: 900_000,
            signatureFunction: _signWithP256
        });

        // Now validate the rest of the entries via - isValidSignature  (expect it to go via erc-7739)
        for (uint256 i; i < nonUserOpEntryDatas.length; i++) {
            assertTrue(
                mockAccount.isValidSignature(
                    nonUserOpEntryDatas[i].entryHash, nonUserOpEntryDatas[i].packedSignatureForEntry
                ) == ERC1271_SUCCESS
            );
        }

        // revert to the default config
        vm.prank(address(mockAccount));
        /*
        stxValidator.replaceConfig(
            bytes32(0),
            address(simpleModeSubmodule),
            address(eoaStatelessValidator),
            abi.encodePacked(wallet.addr)
        );
        */
    }

    // validate userOps via validateUserOp and data objects via validateSignatureWithData (7780 flow)
    function test_StxValidator_simple_mode_ERC7780_with_MixedTypes_EOASig_success(uint256 numOfClones) public {
        numOfClones = bound(numOfClones, 1, 9);

        (, NonUserOpEntryData[] memory nonUserOpEntryDatas) = _prepareDataAndDoUserOpValidation({
            numOfClones: numOfClones,
            applyErc7739: false,
            verificationGasLimit: 500_000,
            signatureFunction: _signWithSecp256k1
        });

        // compose data
        bytes memory validationDataForStatelessValidator = abi.encodePacked(wallet.addr);
        bytes memory data = abi.encode(
            address(mockAccount), // account
            address(simpleModeSubmodule), // stx mode verifier address
            address(eoaStatelessValidator), // stateless validator address
            validationDataForStatelessValidator // validation data for stateless validator
        );

        // Now validate the rest of the entries via
        // - validateSignatureWithData
        // - isValidSignature (no 7739 flow needed for simple mode)
        for (uint256 i; i < nonUserOpEntryDatas.length; i++) {
            assertTrue(
                mockAccount.validateSignatureWithData(
                    nonUserOpEntryDatas[i].entryHash, nonUserOpEntryDatas[i].packedSignatureForEntry, data
                )
            );
        }
    }

    function test_StxValidator_simple_mode_ERC7780_with_MixedTypes_P256Sig_success(uint256 numOfClones) public {
        numOfClones = bound(numOfClones, 1, 9);

        vm.prank(address(mockAccount));
        /*
        stxValidator.replaceConfig(
            bytes32(0), address(simpleModeSubmodule), address(p256StatelessValidator), p256ValidationData
        );
        */

        (, NonUserOpEntryData[] memory nonUserOpEntryDatas) = _prepareDataAndDoUserOpValidation({
            numOfClones: numOfClones,
            applyErc7739: false,
            verificationGasLimit: 900_000,
            signatureFunction: _signWithP256
        });

        // compose data
        bytes memory data = abi.encode(
            address(mockAccount), // account
            address(simpleModeSubmodule), // stx mode verifier address
            address(p256StatelessValidator), // stateless validator address
            p256ValidationData
        );

        // Now validate the rest of the entries via
        // - validateSignatureWithData
        // - isValidSignature (no 7739 flow needed for simple mode)
        for (uint256 i; i < nonUserOpEntryDatas.length; i++) {
            assertTrue(
                mockAccount.validateSignatureWithData(
                    nonUserOpEntryDatas[i].entryHash, nonUserOpEntryDatas[i].packedSignatureForEntry, data
                )
            );
        }

        // revert to the default config
        vm.prank(address(mockAccount));
        /*
        stxValidator.replaceConfig(
            bytes32(0),
            address(simpleModeSubmodule),
            address(eoaStatelessValidator),
            abi.encodePacked(wallet.addr)
        );
        */
    }

    // ===== 1271/7739/7780 test helper =====

    function _prepareDataAndDoUserOpValidation(
        uint256 numOfClones,
        bool applyErc7739,
        uint256 verificationGasLimit,
        function(Vm.Wallet memory, bytes32) internal view returns (bytes memory) signatureFunction
    )
        internal
        returns (PackedUserOperation[] memory, NonUserOpEntryData[] memory)
    {
        uint256 counterBefore = mockTarget.counter();

        // prepare user ops
        bytes memory innerCallData = abi.encodeWithSelector(MockTarget.incrementCounter.selector);
        PackedUserOperation memory userOp = buildBasicMEEUserOpWithCalldata({
            callData: abi.encodeWithSelector(
                mockAccount.execute.selector, address(mockTarget), uint256(0), innerCallData
            ),
            account: address(mockAccount),
            userOpSigner: wallet
        });

        // repack new verificationGasLimit into accountGasLimits
        uint128 callGasLimit = uint128(unpackCallGasLimitMemory(userOp));
        userOp.accountGasLimits = bytes32(abi.encodePacked(uint128(verificationGasLimit), callGasLimit));

        PackedUserOperation[] memory userOps = _cloneUserOpToAnArray(userOp, wallet, numOfClones);

        (PackedUserOperation[] memory superTxUserOps, NonUserOpEntryData[] memory nonUserOpEntryDatas) =
            _makeSimpleSuperTxWithMixedTypes(userOps, wallet, address(mockAccount), applyErc7739, signatureFunction);

        // make sure userOps are handled correctly
        // sending them one by one to emulate the real world scenario
        // where most handleOps calls are made with just one userOp in the array
        vm.startPrank(MEE_NODE_EXECUTOR_EOA, MEE_NODE_EXECUTOR_EOA);
        for (uint256 i = 0; i < superTxUserOps.length; i++) {
            PackedUserOperation[] memory userOpToHandleAsArray = new PackedUserOperation[](1);
            userOpToHandleAsArray[0] = superTxUserOps[i];
            ENTRYPOINT.handleOps(userOpToHandleAsArray, payable(MEE_NODE_ADDRESS));
        }
        vm.stopPrank();
        assertEq(mockTarget.counter(), counterBefore + userOps.length);

        return (superTxUserOps, nonUserOpEntryDatas);
    }

    // ==== SIGNATURE FUNCTIONS ====

    function _signWithSecp256k1(Vm.Wallet memory signer, bytes32 dataToSign) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signer.privateKey, dataToSign);
        return abi.encodePacked(r, s, v);
    }

    function _signWithP256(Vm.Wallet memory signer, bytes32 dataToSign) internal view returns (bytes memory) {
        (bytes32 r, bytes32 s) = vm.signP256(signer.privateKey, dataToSign);
        return abi.encodePacked(r, s);
    }

    // ==== SIMPLE SUPER TX UTILS ====

    /**
     * @notice Makes a simple superTx with MeeUserOps only as entries
     * @param userOps The user operations to include in the superTx
     * @param superTxSigner The signer of the superTx
     * @param smartAccount The smart account address
     * @return superTxUserOps The superTx user operations
     */
    function _makeSimpleSuperTxWithMeeUserOpsOnlyAsEntries(
        PackedUserOperation[] memory userOps,
        Vm.Wallet memory superTxSigner,
        address smartAccount,
        function(Vm.Wallet memory, bytes32) internal view returns (bytes memory) signatureFunction
    )
        internal
        view
        returns (PackedUserOperation[] memory)
    {
        uint48 lowerBoundTimestamp = uint48(block.timestamp);
        uint48 upperBoundTimestamp = uint48(block.timestamp + 1000);
        bytes32[] memory stxItemHashes = _eip712HashMeeUserOps(userOps, lowerBoundTimestamp, upperBoundTimestamp);

        (bytes32 stxStructTypeHash, bytes32 stxEip712HashToSign) =
            _hashPureMeeUserOpsStx(userOps, smartAccount, lowerBoundTimestamp, upperBoundTimestamp);

        // sign the stx struct
        bytes memory superTxHashSignature = signatureFunction(superTxSigner, stxEip712HashToSign);

        bytes4 sigType;
        if (signatureFunction == _signWithSecp256k1) {
            sigType = SIG_TYPE_SIMPLE;
        } else if (signatureFunction == _signWithP256) {
            sigType = SIG_TYPE_SIMPLE_P256;
        } else {
            revert InvalidSignatureTypeForSimpleMode();
        }

        PackedUserOperation[] memory superTxUserOps = new PackedUserOperation[](userOps.length);
        for (uint256 i; i < userOps.length; ++i) {
            superTxUserOps[i] = userOps[i].deepCopy();

            bytes memory signature = abi.encodePacked(
                sigType,
                abi.encode(
                    stxStructTypeHash,
                    i,
                    stxItemHashes,
                    superTxHashSignature,
                    uint256((uint256(lowerBoundTimestamp) << 128) | uint256(upperBoundTimestamp))
                )
            );
            superTxUserOps[i].signature = signature;
        }
        return superTxUserOps;
    }

    struct NonUserOpEntryData {
        bytes32 entryHash;
        uint256 entryIndex;
        bytes packedSignatureForEntry;
    }

    enum EntryType {
        MEE_USER_OP,
        ENTRY_TYPE_A,
        ENTRY_TYPE_B,
        ENTRY_TYPE_C
    }

    struct StxEntryData {
        uint256 entryIndex;
        EntryType entryType;
    }

    /**
     * @notice Makes a simple superTx with mixed types
     * Dynamically creates the superTx struct and according typehash
     * @param userOps The user operations to include in the superTx
     * @param superTxSigner The signer of the superTx
     * @param smartAccount The smart account address
     * @return superTxUserOps The superTx user operations
     * @return nonUserOpEntryDatas The non-userOp entry data
     */
    function _makeSimpleSuperTxWithMixedTypes(
        PackedUserOperation[] memory userOps,
        Vm.Wallet memory superTxSigner,
        address smartAccount,
        bool applyErc7739,
        function(Vm.Wallet memory, bytes32) internal view returns (bytes memory) signatureFunction
    )
        internal
        view
        returns (PackedUserOperation[] memory, NonUserOpEntryData[] memory)
    {
        uint48 lowerBoundTimestamp = uint48(block.timestamp);
        uint48 upperBoundTimestamp = uint48(block.timestamp + 1000);

        uint256 userOpsLength = userOps.length;
        uint256 everyNonUserOpEntryTypeEntriesCount = userOpsLength;
        uint256 otherEntriesLength = userOpsLength * 3;
        StxEntryData[] memory stxLayout;
        NonUserOpEntryData[] memory nonUserOpEntryDatas = new NonUserOpEntryData[](otherEntriesLength);
        string memory dynamicStxStructDefinition;

        //create other entries
        string memory entryTypeADefinition = "EntryTypeA(uint256 foo,bytes32 bar,address baz)";
        string memory entryTypeBDefinition = "EntryTypeB(string qux,address corge)";
        string memory entryTypeCDefinition = "EntryTypeC(uint128[] waldo,bytes16 grault)";
        bytes32 entryTypeATypeHash = keccak256(bytes(entryTypeADefinition));
        bytes32 entryTypeBTypeHash = keccak256(bytes(entryTypeBDefinition));
        bytes32 entryTypeCTypeHash = keccak256(bytes(entryTypeCDefinition));

        // ==== STEP 1: Fill stxLayout array with mixed entry types ====
        // Strategy: Distribute entries evenly - interleave UserOps with other entry types
        // Pattern: UserOp, EntryTypeA, UserOp, EntryTypeB, UserOp, EntryTypeC, etc.

        uint256 totalEntries = userOpsLength + otherEntriesLength;
        stxLayout = new StxEntryData[](totalEntries);

        uint256 userOpIndex = 0;
        uint256 entryAIndex = 0;
        uint256 entryBIndex = 0;
        uint256 entryCIndex = 0;

        // Fill layout: interleave UserOps with other entry types in round-robin fashion
        // Pattern: UserOp, EntryTypeA, UserOp, EntryTypeB, UserOp, EntryTypeC, etc.
        for (uint256 i = 0; i < totalEntries; i++) {
            if (i % 2 == 0) {
                // Even positions: UserOp (if available)
                if (userOpIndex < userOpsLength) {
                    stxLayout[i] = StxEntryData({ entryIndex: i, entryType: EntryType.MEE_USER_OP });
                    userOpIndex++;
                } else {
                    // No more UserOps, fill with remaining entry types
                    if (entryAIndex < everyNonUserOpEntryTypeEntriesCount) {
                        stxLayout[i] = StxEntryData({ entryIndex: i, entryType: EntryType.ENTRY_TYPE_A });
                        entryAIndex++;
                    } else if (entryBIndex < everyNonUserOpEntryTypeEntriesCount) {
                        stxLayout[i] = StxEntryData({ entryIndex: i, entryType: EntryType.ENTRY_TYPE_B });
                        entryBIndex++;
                    } else if (entryCIndex < everyNonUserOpEntryTypeEntriesCount) {
                        stxLayout[i] = StxEntryData({ entryIndex: i, entryType: EntryType.ENTRY_TYPE_C });
                        entryCIndex++;
                    }
                }
            } else {
                // Odd positions: Cycle through EntryTypeA, B, C
                uint256 cycleIndex = (i - 1) / 2; // Convert to 0-based cycle index
                if (cycleIndex % 3 == 0 && entryAIndex < everyNonUserOpEntryTypeEntriesCount) {
                    stxLayout[i] = StxEntryData({ entryIndex: i, entryType: EntryType.ENTRY_TYPE_A });
                    entryAIndex++;
                } else if (cycleIndex % 3 == 1 && entryBIndex < everyNonUserOpEntryTypeEntriesCount) {
                    stxLayout[i] = StxEntryData({ entryIndex: i, entryType: EntryType.ENTRY_TYPE_B });
                    entryBIndex++;
                } else if (entryCIndex < everyNonUserOpEntryTypeEntriesCount) {
                    stxLayout[i] = StxEntryData({ entryIndex: i, entryType: EntryType.ENTRY_TYPE_C });
                    entryCIndex++;
                } else if (entryAIndex < everyNonUserOpEntryTypeEntriesCount) {
                    stxLayout[i] = StxEntryData({ entryIndex: i, entryType: EntryType.ENTRY_TYPE_A });
                    entryAIndex++;
                } else if (entryBIndex < everyNonUserOpEntryTypeEntriesCount) {
                    stxLayout[i] = StxEntryData({ entryIndex: i, entryType: EntryType.ENTRY_TYPE_B });
                    entryBIndex++;
                } else if (userOpIndex < userOpsLength) {
                    stxLayout[i] = StxEntryData({ entryIndex: i, entryType: EntryType.MEE_USER_OP });
                    userOpIndex++;
                }
            }
        }

        // ==== STEP 2: Create all item hashes (both UserOps and other entry types) ====
        // Allocate array for all entry hashes in the order they appear in stxLayout
        bytes32[] memory stxItemHashes = new bytes32[](totalEntries);
        bytes32[] memory preErc7739ItemHashes = new bytes32[](totalEntries);

        uint256 entryACounter = 0;
        uint256 entryBCounter = 0;
        uint256 entryCCounter = 0;
        uint256 userOpCounter = 0;
        uint256 nonUserOpDataCounter = 0;

        // Process each entry in stxLayout and generate its hash
        for (uint256 i = 0; i < totalEntries; i++) {
            if (stxLayout[i].entryType == EntryType.MEE_USER_OP) {
                // Hash MeeUserOp as: hashStruct(MeeUserOp) = keccak256(MEE_USER_OP_TYPEHASH ‖ userOpHash ‖
                // lowerBound
                // ‖ upperBound)
                bytes32 userOpHash = ENTRYPOINT.getUserOpHash(userOps[userOpCounter]);
                stxItemHashes[i] =
                    MEEUserOpHashLib.getMeeUserOpEip712Hash(userOpHash, lowerBoundTimestamp, upperBoundTimestamp);
                userOpCounter++;
            } else if (stxLayout[i].entryType == EntryType.ENTRY_TYPE_A) {
                // Create unique EntryTypeA: EntryTypeA(uint256 foo, bytes32 bar, address baz)
                uint256 foo = uint256(keccak256(abi.encode("entryA", entryACounter)));
                bytes32 bar = keccak256(abi.encode("bar", entryACounter));
                address baz = address(uint160(uint256(keccak256(abi.encode("baz", entryACounter)))));

                // Hash as per EIP-712: hashStruct(s) = keccak256(typeHash ‖ encodeData(s))
                // encodeData for EntryTypeA = encode(foo, bar, baz)
                bytes32 entryHash = keccak256(abi.encodePacked(entryTypeATypeHash, abi.encode(foo, bar, baz)));
                preErc7739ItemHashes[i] = entryHash;
                if (applyErc7739) {
                    // hash as per erc-7739
                    bytes32 erc7739StructHash = keccak256(
                        abi.encodePacked(
                            abi.encode(
                                keccak256(
                                    "TypedDataSign(EntryTypeA contents,string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)EntryTypeA(uint256 foo,bytes32 bar,address baz)"
                                ),
                                entryHash
                            ),
                            accountDomainStructFields(smartAccount)
                        )
                    );
                    entryHash = keccak256(abi.encodePacked("\x19\x01", APP_DOMAIN_SEPARATOR, erc7739StructHash));
                }
                stxItemHashes[i] = entryHash;
                entryACounter++;
            } else if (stxLayout[i].entryType == EntryType.ENTRY_TYPE_B) {
                // Create unique EntryTypeB: EntryTypeB(string qux, address corge)
                string memory qux = string(abi.encodePacked("qux_", _uintToString(entryBCounter)));
                address corge = address(uint160(uint256(keccak256(abi.encode("corge", entryBCounter)))));

                // Hash as per EIP-712: for string types, we hash them first
                // encodeData for EntryTypeB = encode(keccak256(qux), corge)
                bytes32 entryHash =
                    keccak256(abi.encodePacked(entryTypeBTypeHash, abi.encode(keccak256(bytes(qux)), corge)));
                preErc7739ItemHashes[i] = entryHash;
                if (applyErc7739) {
                    // hash as per erc-7739
                    bytes32 erc7739StructHash = keccak256(
                        abi.encodePacked(
                            abi.encode(
                                keccak256(
                                    "TypedDataSign(EntryTypeB contents,string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)EntryTypeB(string qux,address corge)"
                                ),
                                entryHash
                            ),
                            accountDomainStructFields(smartAccount)
                        )
                    );
                    entryHash = keccak256(abi.encodePacked("\x19\x01", APP_DOMAIN_SEPARATOR, erc7739StructHash));
                }
                stxItemHashes[i] = entryHash;
                entryBCounter++;
            } else if (stxLayout[i].entryType == EntryType.ENTRY_TYPE_C) {
                // Create unique EntryTypeC: EntryTypeC(uint128[] waldo, bytes16 grault)
                uint128[] memory waldo = new uint128[](3);
                waldo[0] = uint128(entryCCounter + 1);
                waldo[1] = uint128(entryCCounter + 2);
                waldo[2] = uint128(entryCCounter + 3);
                bytes16 grault = bytes16(keccak256(abi.encode("grault", entryCCounter)));

                // Hash as per EIP-712: for array types, we hash the array first
                // encodeData for EntryTypeC = encode(keccak256(encodeData(waldo)), grault)
                bytes32 entryHash = keccak256(
                    abi.encodePacked(entryTypeCTypeHash, abi.encode(keccak256(abi.encodePacked(waldo)), grault))
                );
                preErc7739ItemHashes[i] = entryHash;
                if (applyErc7739) {
                    // hash as per erc-7739
                    bytes32 erc7739StructHash = keccak256(
                        abi.encodePacked(
                            abi.encode(
                                keccak256(
                                    "TypedDataSign(EntryTypeC contents,string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)EntryTypeC(uint128[] waldo,bytes16 grault)"
                                ),
                                entryHash
                            ),
                            accountDomainStructFields(smartAccount)
                        )
                    );
                    entryHash = keccak256(abi.encodePacked("\x19\x01", APP_DOMAIN_SEPARATOR, erc7739StructHash));
                }
                stxItemHashes[i] = entryHash;
                entryCCounter++;
            }
        }

        // ==== STEP 3: Build dynamic SuperTx struct definition ====
        // Format: SuperTx(Type1 entry1,Type2 entry2,...)‖MeeUserOpDef‖EntryTypeADef‖EntryTypeBDef‖EntryTypeCDef

        // Build array of entry type names in the order they appear in stxLayout
        string[] memory entryTypeNames = new string[](totalEntries);
        for (uint256 i = 0; i < totalEntries; i++) {
            if (stxLayout[i].entryType == EntryType.MEE_USER_OP) {
                entryTypeNames[i] = "MeeUserOp";
            } else if (stxLayout[i].entryType == EntryType.ENTRY_TYPE_A) {
                if (applyErc7739) {
                    entryTypeNames[i] = "TypedDataSign";
                } else {
                    entryTypeNames[i] = "EntryTypeA";
                }
            } else if (stxLayout[i].entryType == EntryType.ENTRY_TYPE_B) {
                if (applyErc7739) {
                    entryTypeNames[i] = "TypedDataSign";
                } else {
                    entryTypeNames[i] = "EntryTypeB";
                }
            } else if (stxLayout[i].entryType == EntryType.ENTRY_TYPE_C) {
                if (applyErc7739) {
                    entryTypeNames[i] = "TypedDataSign";
                } else {
                    entryTypeNames[i] = "EntryTypeC";
                }
            }
        }

        // Prepare type definitions
        uint256 otherTypeDefinitionsCount = applyErc7739 ? 6 : 3;
        string[] memory otherTypeDefinitions = new string[](otherTypeDefinitionsCount);
        string memory meeUserOpDefinition =
            "MeeUserOp(bytes32 userOpHash,uint256 lowerBoundTimestamp,uint256 upperBoundTimestamp)";
        otherTypeDefinitions[0] = entryTypeADefinition;
        otherTypeDefinitions[1] = entryTypeBDefinition;
        otherTypeDefinitions[2] = entryTypeCDefinition;
        if (applyErc7739) {
            otherTypeDefinitions[3] =
                "TypedDataSign(EntryTypeA contents,string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)";
            otherTypeDefinitions[4] =
                "TypedDataSign(EntryTypeB contents,string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)";
            otherTypeDefinitions[5] =
                "TypedDataSign(EntryTypeC contents,string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)";
        }

        // Build the complete dynamic struct definition using the helper function
        dynamicStxStructDefinition =
            _buildDynamicStxStructDefinition(entryTypeNames, meeUserOpDefinition, otherTypeDefinitions);

        // ==== STEP 4: Calculate stxStructTypeHash ====
        // As per EIP-712: typeHash = keccak256(dynamicStxStructDefinition)
        bytes32 stxStructTypeHash = keccak256(bytes(dynamicStxStructDefinition));

        // ==== STEP 5: Calculate superTxEip712Hash ====
        // As per EIP-712: hashStruct(s) = keccak256(typeHash ‖ encodeData(s))
        // For a struct with multiple entries: encodeData(s) = encode(value1, value2, ..., valueN)
        // Since all our values are bytes32 hashes, we concatenate them
        bytes32 structHash = keccak256(abi.encodePacked(stxStructTypeHash, stxItemHashes));

        // Now wrap with domain separator as per EIP-712: "\x19\x01" ‖ domainSeparator ‖ hashStruct(message)
        bytes32 superTxEip712Hash = HashLib.hashTypedDataForAccount(smartAccount, structHash);

        // ==== STEP 6: Sign the superTxEip712Hash ====
        // Use the superTxSigner's private key to sign the EIP-712 hash
        /*
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(superTxSigner.privateKey, superTxEip712Hash);
        bytes memory superTxHashSignature = abi.encodePacked(r, s, v);
        */
        bytes memory superTxHashSignature = signatureFunction(superTxSigner, superTxEip712Hash);

        // ==== STEP 7: Build individual signatures for each entry ====
        // Each entry's signature contains: encode(stxStructTypeHash, index, stxItemHashes,
        // superTxHashSignature) + timestamps for userOp entries

        // Reset counters for processing
        userOpCounter = 0;
        nonUserOpDataCounter = 0;

        PackedUserOperation[] memory superTxUserOps = new PackedUserOperation[](userOpsLength);

        for (uint256 i = 0; i < totalEntries; i++) {
            bytes memory signature;

            if (stxLayout[i].entryType == EntryType.MEE_USER_OP) {
                // For MeeUserOps: signature includes timestamps
                signature = abi.encode(
                    stxStructTypeHash,
                    i, // index in the SuperTx
                    stxItemHashes,
                    superTxHashSignature,
                    uint256((uint256(lowerBoundTimestamp) << 128) | uint256(upperBoundTimestamp))
                );

                // Copy the userOp and replace its signature
                superTxUserOps[userOpCounter] = userOps[userOpCounter].deepCopy();
                superTxUserOps[userOpCounter].signature = signature;
                userOpCounter++;
            } else {
                // For non-UserOp entries: signature does NOT include timestamps
                bytes memory erc7739Signature;
                if (applyErc7739) {
                    bytes memory contentsType;
                    if (stxLayout[i].entryType == EntryType.ENTRY_TYPE_A) {
                        contentsType = bytes(entryTypeADefinition);
                    } else if (stxLayout[i].entryType == EntryType.ENTRY_TYPE_B) {
                        contentsType = bytes(entryTypeBDefinition);
                    } else if (stxLayout[i].entryType == EntryType.ENTRY_TYPE_C) {
                        contentsType = bytes(entryTypeCDefinition);
                    }
                    // add erc-7739 payload to the signature
                    erc7739Signature = abi.encodePacked(
                        superTxHashSignature,
                        APP_DOMAIN_SEPARATOR,
                        preErc7739ItemHashes[i], // contents
                        contentsType,
                        uint16(contentsType.length) // contentsTypeLength
                    );
                }
                // wrap as per Simple Mode
                signature = abi.encode(
                    stxStructTypeHash,
                    i, // index in the SuperTx
                    stxItemHashes,
                    applyErc7739 ? erc7739Signature : superTxHashSignature
                );

                bytes32 hashForIsValidSignature;
                if (applyErc7739) {
                    // this will be passed to isValidSignature as dataHash
                    // and this will go to erc7739 methods to make 7739 hash out of it
                    // using the data appended to the signature
                    hashForIsValidSignature =
                        EcdsaHelperLib.toTypedDataHash(APP_DOMAIN_SEPARATOR, preErc7739ItemHashes[i]);
                } else {
                    hashForIsValidSignature = stxItemHashes[i];
                }

                // Store in NonUserOpEntryData array
                nonUserOpEntryDatas[nonUserOpDataCounter] = NonUserOpEntryData({
                    //entryHash: stxItemHashes[i], entryIndex: i, packedSignatureForEntry: signature
                    entryHash: hashForIsValidSignature,
                    entryIndex: i,
                    packedSignatureForEntry: signature
                });
                nonUserOpDataCounter++;
            }
        }

        // ==== STEP 8: Return all results ====
        return (superTxUserOps, nonUserOpEntryDatas);
    }
}
