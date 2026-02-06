// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Script, console2, console } from "node_modules/forge-std/src/Script.sol";
import { Config } from "node_modules/forge-std/src/Config.sol";
import { LibVariable, Variable, TypeKind } from "node_modules/forge-std/src/LibVariable.sol";
import { NexusProxy } from "contracts/nexus/utils/NexusProxy.sol";
import { DeterministicDeployerLib } from "script/deploy/util/DeterministicDeployerLib.sol";
import { SubmoduleAddresses } from "contracts/validators/stx-validator/ConfigManager.sol";
import { NexusBootstrap } from "contracts/nexus/utils/NexusBootstrap.sol";
import { NexusAccountFactory } from "contracts/nexus/factory/NexusAccountFactory.sol";
import { INexus } from "contracts/interfaces/nexus/INexus.sol";
import { CreateX } from "script/deploy/util/CreateX.sol";

contract DeployStxContracts is Script, Config {
    /* ===== salts ===== */
    // Note: StxValidator salt is kept for now, will need to mine a new one for production
    bytes32 constant STX_VALIDATOR_SALT = 0x0000000000000000000000000000000000000000972d15c771cbed0134f06e96; //=>
    // TODO: mine new salt for StxValidator vanity address

    // Submodule salts (arbitrary, not mined for vanity addresses)
    bytes32 constant NO_STX_MODE_VERIFIER_SALT = 0x0000000000000000000000000000000000000000000000000000000000000001;
    bytes32 constant SIMPLE_MODE_VERIFIER_SALT = 0x0000000000000000000000000000000000000000000000000000000000000002;
    bytes32 constant PERMIT_MODE_VERIFIER_SALT = 0x0000000000000000000000000000000000000000000000000000000000000003;
    bytes32 constant TX_MODE_VERIFIER_SALT = 0x0000000000000000000000000000000000000000000000000000000000000004;
    bytes32 constant SAFE_ACCOUNT_SUBMODULE_SALT = 0x0000000000000000000000000000000000000000000000000000000000000005;
    bytes32 constant EOA_STATELESS_VALIDATOR_SALT = 0x0000000000000000000000000000000000000000000000000000000000000006;
    bytes32 constant P256_STATELESS_VALIDATOR_SALT = 0x0000000000000000000000000000000000000000000000000000000000000007;

    bytes32 constant NEXUS_SALT = 0x000000000000000000000000000000000000000073a42ee9e159d8001cbebd2d; // =>
    // 0x0000000020fe2F30453074aD916eDeB653eC7E9D;

    bytes32 constant NEXUSBOOTSTRAP_SALT = 0x0000000000000000000000000000000000000000c959a6b05366e70294aeb6ac; // =>
    // 0x000000007BfEdA33ac982cb38eAaEf5D7bCC954c

    bytes32 constant NEXUS_ACCOUNT_FACTORY_SALT = 0x00000000000000000000000000000000000000001090265e9bbd0800e4822798; //
    // => 0x000000002c9A405a196f2dc766F2476B731693c3;

    bytes32 constant COMPOSABLE_EXECUTION_MODULE_SALT =
        0x00000000000000000000000000000000000000008d04585764673a01ecb09ecd; // =>
    // 0x00000000f61636C0CA71d21a004318502283aB2d

    bytes32 constant COMPOSABLE_STORAGE_SALT = 0x000000000000000000000000000000000000000070fef65fd06ba40009ce0acc; // =>
    // 0x0000000078994c6ef6A4596BE53A728b255352c2;

    bytes32 constant ETH_FORWARDER_SALT = 0x00000000000000000000000000000000000000002f5763a1f79af7033892e88a; //=>
    // 0x000000C48Cdf2b46bEc062483dBD27046dfE3b8d;

    bytes32 constant NODE_PMF_SALT = 0x0000000000000000000000000000000000000000a59717b95fe60f015cd48181; // =>
    // 0x000000003c7824c9842b71F0cD390b1805A7EF90

    bytes32 public constant DISPERSE_SALT = 0xfd73487f4e6544007a3ce4000000000000000000000000000000000000000000;
    bytes public constant DISPERSE_INITCODE =
        hex"608060405234801561001057600080fd5b506106f4806100206000396000f300608060405260043610610057576000357c0100000000000000000000000000000000000000000000000000000000900463ffffffff16806351ba162c1461005c578063c73a2d60146100cf578063e63d38ed14610142575b600080fd5b34801561006857600080fd5b506100cd600480360381019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803590602001908201803590602001919091929391929390803590602001908201803590602001919091929391929390505050610188565b005b3480156100db57600080fd5b50610140600480360381019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803590602001908201803590602001919091929391929390803590602001908201803590602001919091929391929390505050610309565b005b6101866004803603810190808035906020019082018035906020019190919293919293908035906020019082018035906020019190919293919293905050506105b0565b005b60008090505b84849050811015610301578573ffffffffffffffffffffffffffffffffffffffff166323b872dd3387878581811015156101c457fe5b9050602002013573ffffffffffffffffffffffffffffffffffffffff1686868681811015156101ef57fe5b905060200201356040518463ffffffff167c0100000000000000000000000000000000000000000000000000000000028152600401808473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1681526020018373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1681526020018281526020019350505050602060405180830381600087803b1580156102ae57600080fd5b505af11580156102c2573d6000803e3d6000fd5b505050506040513d60208110156102d857600080fd5b810190808051906020019092919050505015156102f457600080fd5b808060010191505061018e565b505050505050565b60008060009150600090505b8585905081101561034657838382818110151561032e57fe5b90506020020135820191508080600101915050610315565b8673ffffffffffffffffffffffffffffffffffffffff166323b872dd3330856040518463ffffffff167c0100000000000000000000000000000000000000000000000000000000028152600401808473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1681526020018373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1681526020018281526020019350505050602060405180830381600087803b15801561041d57600080fd5b505af1158015610431573d6000803e3d6000fd5b505050506040513d602081101561044757600080fd5b8101908080519060200190929190505050151561046357600080fd5b600090505b858590508110156105a7578673ffffffffffffffffffffffffffffffffffffffff1663a9059cbb878784818110151561049d57fe5b9050602002013573ffffffffffffffffffffffffffffffffffffffff1686868581811015156104c857fe5b905060200201356040518363ffffffff167c0100000000000000000000000000000000000000000000000000000000028152600401808373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200182815260200192505050602060405180830381600087803b15801561055457600080fd5b505af1158015610568573d6000803e3d6000fd5b505050506040513d602081101561057e57600080fd5b8101908080519060200190929190505050151561059a57600080fd5b8080600101915050610468565b50505050505050565b600080600091505b858590508210156106555785858381811015156105d157fe5b9050602002013573ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff166108fc858585818110151561061557fe5b905060200201359081150290604051600060405180830381858888f19350505050158015610647573d6000803e3d6000fd5b5081806001019250506105b8565b3073ffffffffffffffffffffffffffffffffffffffff1631905060008111156106c0573373ffffffffffffffffffffffffffffffffffffffff166108fc829081150290604051600060405180830381858888f193505050501580156106be573d6000803e3d6000fd5b505b5050505050505600a165627a7a723058204f25a733917e0bf639cd1e101d55bd927f843fb395fb2a963a7909c09ae023ed0029";

    bytes32 constant NEXUS_PROXY_SALT = 0x0000000000000000000000000000000000000000000000000000000000000001;

    address constant ENTRYPOINT_ADDRESS = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;
    address constant EEEEEE_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address constant FACTORY_OWNER_ADDRESS = 0x129443cA2a9Dec2020808a2868b38dDA457eaCC7;

    // Bytecode storage variables (populated in setUp)
    bytes private stxValidatorBytecode;
    bytes private nexusBytecode;
    bytes private nexusBootstrapBytecode;
    bytes private nexusAccountFactoryBytecode;
    bytes private composableExecutionModuleBytecode;
    bytes private composableStorageBytecode;
    bytes private etherForwarderBytecode;
    bytes private nodePaymasterFactoryBytecode;

    // Submodule bytecode storage variables
    bytes private noStxModeVerifierBytecode;
    bytes private simpleModeSubmoduleBytecode;
    bytes private permitSubmoduleBytecode;
    bytes private txSubmoduleBytecode;
    bytes private safeAccountSubmoduleBytecode;
    bytes private eoaStatelessValidatorBytecode;
    bytes private p256StatelessValidatorBytecode;

    struct ChainConfig {
        uint256 chainId;
        string name;
        bool isTestnet;
    }

    struct DeployedSubmodules {
        address noStxModeVerifier;
        address simpleModeVerifier;
        address permitModeVerifier;
        address txModeVerifier;
        address safeAccountSubmodule;
        address eoaStatelessValidator;
        address p256StatelessValidator;
    }

    struct DeployedContracts {
        address stxValidator;
        address nexus;
        address nexusBootstrap;
        address nexusAccountFactory;
        address nexusProxy;
        address composableExecutionModule;
        address composableStorage;
        address etherForwarder;
        address nodePaymasterFactory;
        address disperse;
    }

    mapping(uint256 => DeployedSubmodules) internal deployedSubmodulesPerChain;

    mapping(uint256 => DeployedContracts) internal deployedContractsPerChain;

    /**
     * @notice Build the StxValidator init data for making implementations unusable
     * @param eoaStatelessValidator The EOA stateless validator address
     * @return The encoded init data
     * @dev Format: [20 bytes statelessValidator][1 byte safeSendersCount][ownershipData]
     * Uses EEEEEE_ADDRESS as owner to make implementation unusable (impossible to sign for)
     */
    function _buildStxValidatorInitData(address eoaStatelessValidator) internal pure returns (bytes memory) {
        return abi.encodePacked(
            eoaStatelessValidator,
            uint8(0), // no safe senders
            abi.encodePacked(EEEEEE_ADDRESS) // ownership data: impossible to sign for this address
        );
    }

    mapping(uint256 => ChainConfig) internal chainConfigs;
    string internal configPath = "/script/deploy/config.toml";

    function setUp() public {
        // Load main contract bytecodes
        stxValidatorBytecode = vm.getCode("script/deploy/artifacts/stx-validator/StxValidator/StxValidator.json");
        nexusBytecode = vm.getCode("script/deploy/artifacts/Nexus/Nexus.json");
        nexusBootstrapBytecode = vm.getCode("script/deploy/artifacts/NexusBootstrap/NexusBootstrap.json");
        nexusAccountFactoryBytecode = vm.getCode("script/deploy/artifacts/NexusAccountFactory/NexusAccountFactory.json");
        composableExecutionModuleBytecode = vm.getCode("script/deploy/artifacts/ComposableExecutionModule/ComposableExecutionModule.json");
        composableStorageBytecode = vm.getCode("script/deploy/artifacts/ComposableStorage/ComposableStorage.json");
        etherForwarderBytecode = vm.getCode("script/deploy/artifacts/EtherForwarder/EtherForwarder.json");
        nodePaymasterFactoryBytecode = vm.getCode("script/deploy/artifacts/NodePaymasterFactory/NodePaymasterFactory.json");

        // Load submodule bytecodes
        noStxModeVerifierBytecode = vm.getCode("script/deploy/artifacts/stx-validator/submodules/NoStxModeVerifier/NoStxModeVerifier.json");
        simpleModeSubmoduleBytecode = vm.getCode("script/deploy/artifacts/stx-validator/submodules/SimpleModeSubmodule/SimpleModeSubmodule.json");
        permitSubmoduleBytecode = vm.getCode("script/deploy/artifacts/stx-validator/submodules/PermitSubmodule/PermitSubmodule.json");
        txSubmoduleBytecode = vm.getCode("script/deploy/artifacts/stx-validator/submodules/TxSubmodule/TxSubmodule.json");
        safeAccountSubmoduleBytecode = vm.getCode("script/deploy/artifacts/stx-validator/submodules/SafeAccountSubmodule/SafeAccountSubmodule.json");
        eoaStatelessValidatorBytecode = vm.getCode("script/deploy/artifacts/stx-validator/submodules/EOAStatelessValidator/EOAStatelessValidator.json");
        p256StatelessValidatorBytecode = vm.getCode("script/deploy/artifacts/stx-validator/submodules/P256StatelessValidator/P256StatelessValidator.json");
    }

    /**
     * @notice Deploy to specific chains
     * @param chainId The chain ID to deploy to
     * @param contractNames Array of contract names to deploy (empty array = all contracts)
     */
    function run(uint256 chainId, string[] memory contractNames) external {
        
        string memory fullConfigPath = string.concat(vm.projectRoot(), configPath);
        console.log("Loading config from:", fullConfigPath);
        
        // load config
        _loadConfig(fullConfigPath, false);

        // create fork
        console.log("Creating fork for chain:", chainId);
        uint256 forkId = vm.createFork(config.getRpcUrl(chainId));
        forkOf[chainId] = forkId;
        console.log("Fork successfully created");

        // Load configuration for each chain
        loadConfiguration(chainId);
        deployContracts(chainId, contractNames);
    }

    /**
     * @notice calculate if the specific contract is already deployed to the given chain
     * @param chainId The chain ID to deploy to
     * @param isDryRun Whether to perform a dry run (only calculate expected addresses)
     */
    function run(uint256 chainId, bool isDryRun) external {
        bytes memory args;

        // Compute submodule addresses first (they are dependencies for StxValidator)
        SubmoduleAddresses memory submoduleAddresses = computeSubmoduleAddresses();

        // StxValidator
        address expectedStxValidatorAddress = calculateStxValidatorAddress(submoduleAddresses);
        checkAndLogContractStatus(chainId, expectedStxValidatorAddress, "StxValidator", isDryRun);
        if (isDryRun) {
            console.logBytes32(keccak256(abi.encodePacked(stxValidatorBytecode, abi.encode(submoduleAddresses))));
        }

        bytes memory stxValidatorInitData = _buildStxValidatorInitData(submoduleAddresses.eoaStatelessValidator);

        // Nexus
        address expectedNexusAddress;
        (expectedNexusAddress, args) = calculateNexusAddress(expectedStxValidatorAddress, stxValidatorInitData);
        checkAndLogContractStatus(chainId, expectedNexusAddress, "Nexus", isDryRun);
        if (isDryRun) {
            console2.logBytes(args);
            console2.logBytes32(keccak256(abi.encodePacked(nexusBytecode, args)));
        }

        // NexusBootstrap
        address expectedNexusBootstrapAddress;
        (expectedNexusBootstrapAddress, args) = calculateNexusBootstrapAddress(expectedStxValidatorAddress, stxValidatorInitData);
        checkAndLogContractStatus(chainId, expectedNexusBootstrapAddress, "NexusBootstrap", isDryRun);
        if (isDryRun) {
            console2.logBytes(args);
            console2.logBytes32(keccak256(abi.encodePacked(nexusBootstrapBytecode, args)));
        }

        // NexusAccountFactory
        address expectedNexusAccountFactoryAddress;
        (expectedNexusAccountFactoryAddress, args) = calculateNexusAccountFactoryAddress(expectedNexusAddress);
        checkAndLogContractStatus(chainId, expectedNexusAccountFactoryAddress, "NexusAccountFactory", isDryRun);
        if (isDryRun) {
            console2.logBytes(args);
            console2.logBytes32(keccak256(abi.encodePacked(nexusAccountFactoryBytecode, args)));
        }

        // NexusProxy
        bytes memory initData = abi.encode(
            expectedNexusBootstrapAddress,
            abi.encodeWithSelector(
                NexusBootstrap.initNexusWithDefaultValidator.selector, abi.encodePacked(FACTORY_OWNER_ADDRESS)
            )
        );
        bytes32 initCodeHash = keccak256(
            abi.encodePacked(
                type(NexusProxy).creationCode,
                abi.encode(expectedNexusAddress, abi.encodeCall(INexus.initializeAccount, initData))
            )
        );
        address expectedNexusProxyAddress = payable(address(
            uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), expectedNexusAccountFactoryAddress, NEXUS_PROXY_SALT, initCodeHash))))
        ));
        checkAndLogContractStatus(chainId, expectedNexusProxyAddress, "NexusProxy", isDryRun);

        address expectedAddress;

        // ComposableExecutionModule
        (expectedAddress, args) = calculateComposableExecutionModuleAddress();
        checkAndLogContractStatus(chainId, expectedAddress, "ComposableExecutionModule", isDryRun);
        if (isDryRun) {
            console2.logBytes(args);
            console2.logBytes32(keccak256(abi.encodePacked(composableExecutionModuleBytecode, args)));
        }

        // ComposableStorage
        expectedAddress = calculateComposableStorageAddress();
        checkAndLogContractStatus(chainId, expectedAddress, "ComposableStorage", isDryRun);
        if (isDryRun) {
            console2.logBytes32(keccak256(composableStorageBytecode));
        }

        // EtherForwarder
        expectedAddress = calculateEtherForwarderAddress();
        checkAndLogContractStatus(chainId, expectedAddress, "EtherForwarder", isDryRun);
        if (isDryRun) {
            console2.logBytes32(keccak256(etherForwarderBytecode));
        }

        // NodePaymasterFactory
        expectedAddress = calculateNodePaymasterFactoryAddress();
        checkAndLogContractStatus(chainId, expectedAddress, "NodePaymasterFactory", isDryRun);
        if (isDryRun) {
            console2.logBytes32(keccak256(nodePaymasterFactoryBytecode));
        }
    }

    // ============ Address calculation functions ============

    function calculateStxValidatorAddress(SubmoduleAddresses memory submoduleAddresses) internal view returns (address) {
        bytes memory args = abi.encode(submoduleAddresses);
        return DeterministicDeployerLib.computeAddress(stxValidatorBytecode, args, STX_VALIDATOR_SALT);
    }

    function calculateNexusAddress(address stxValidatorAddress, bytes memory stxValidatorInitData) internal view returns (address, bytes memory) {
        bytes memory args = abi.encode(ENTRYPOINT_ADDRESS, stxValidatorAddress, stxValidatorInitData);
        address nexusAddress = DeterministicDeployerLib.computeAddress(nexusBytecode, args, NEXUS_SALT);
        return (nexusAddress, args);
    }

    function calculateNexusBootstrapAddress(address stxValidatorAddress, bytes memory stxValidatorInitData) internal view returns (address, bytes memory) {
        bytes memory args = abi.encode(stxValidatorAddress, stxValidatorInitData);
        address nexusBootstrapAddress = DeterministicDeployerLib.computeAddress(nexusBootstrapBytecode, args, NEXUSBOOTSTRAP_SALT);
        return (nexusBootstrapAddress, args);
    }

    function calculateNexusAccountFactoryAddress(address nexusAddress) internal view returns (address, bytes memory) {
        bytes memory args = abi.encode(nexusAddress, FACTORY_OWNER_ADDRESS);
        address nexusAccountFactoryAddress = DeterministicDeployerLib.computeAddress(nexusAccountFactoryBytecode, args, NEXUS_ACCOUNT_FACTORY_SALT);
        return (nexusAccountFactoryAddress, args);
    }

    function calculateComposableExecutionModuleAddress() internal view returns (address, bytes memory) {
        bytes memory args = abi.encode(ENTRYPOINT_ADDRESS);
        address composableExecutionModuleAddress = DeterministicDeployerLib.computeAddress(composableExecutionModuleBytecode, args, COMPOSABLE_EXECUTION_MODULE_SALT);
        return (composableExecutionModuleAddress, args);
    }

    function calculateComposableStorageAddress() internal view returns (address) {
        return DeterministicDeployerLib.computeAddress(composableStorageBytecode, COMPOSABLE_STORAGE_SALT);
    }

    function calculateEtherForwarderAddress() internal view returns (address) {
        return DeterministicDeployerLib.computeAddress(etherForwarderBytecode, ETH_FORWARDER_SALT);
    }

    function calculateNodePaymasterFactoryAddress() internal view returns (address) {
        return DeterministicDeployerLib.computeAddress(nodePaymasterFactoryBytecode, NODE_PMF_SALT);
    }

    /**
     * @notice Compute the deterministic addresses of all submodules
     * @return submoduleAddresses The computed submodule addresses
     */
    function computeSubmoduleAddresses() internal view returns (SubmoduleAddresses memory submoduleAddresses) {
        submoduleAddresses.noStxModeVerifier = DeterministicDeployerLib.computeAddress(noStxModeVerifierBytecode, NO_STX_MODE_VERIFIER_SALT);
        submoduleAddresses.simpleModeVerifier = DeterministicDeployerLib.computeAddress(simpleModeSubmoduleBytecode, SIMPLE_MODE_VERIFIER_SALT);
        submoduleAddresses.permitModeVerifier = DeterministicDeployerLib.computeAddress(permitSubmoduleBytecode, PERMIT_MODE_VERIFIER_SALT);
        submoduleAddresses.txModeVerifier = DeterministicDeployerLib.computeAddress(txSubmoduleBytecode, TX_MODE_VERIFIER_SALT);
        submoduleAddresses.safeAccountSubmodule = DeterministicDeployerLib.computeAddress(safeAccountSubmoduleBytecode, SAFE_ACCOUNT_SUBMODULE_SALT);
        submoduleAddresses.eoaStatelessValidator = DeterministicDeployerLib.computeAddress(eoaStatelessValidatorBytecode, EOA_STATELESS_VALIDATOR_SALT);
        submoduleAddresses.p256StatelessValidator = DeterministicDeployerLib.computeAddress(p256StatelessValidatorBytecode, P256_STATELESS_VALIDATOR_SALT);
    }

    function deployContracts(uint256 chainId, string[] memory contractNames) internal {
        ChainConfig memory config = chainConfigs[chainId];

        console.log("\n=====================================");
        console.log("Deploying to:", config.name);
        console.log("Chain ID:", chainId);
        console.log("=====================================\n");

        // Verify chain ID
        require(block.chainid == chainId, "Chain ID mismatch");

        // Pre-compute submodule addresses (needed for StxValidator init data calculation)
        SubmoduleAddresses memory submoduleAddresses = computeSubmoduleAddresses();
        bytes memory stxValidatorInitData = _buildStxValidatorInitData(submoduleAddresses.eoaStatelessValidator);

        for (uint256 i = 0; i < contractNames.length; i++) {
            // StxValidator
            if (keccak256(abi.encodePacked(contractNames[i])) == keccak256(abi.encodePacked("StxValidator"))) {
                // Deploy all submodules first, then StxValidator
                deployAllSubmodules(chainId);
                deployedContractsPerChain[chainId].stxValidator = deployStxValidator(chainId);
            } else {
                deployedSubmodulesPerChain[chainId] = DeployedSubmodules({
                    noStxModeVerifier: submoduleAddresses.noStxModeVerifier,
                    simpleModeVerifier: submoduleAddresses.simpleModeVerifier,
                    permitModeVerifier: submoduleAddresses.permitModeVerifier,
                    txModeVerifier: submoduleAddresses.txModeVerifier,
                    safeAccountSubmodule: submoduleAddresses.safeAccountSubmodule,
                    eoaStatelessValidator: submoduleAddresses.eoaStatelessValidator,
                    p256StatelessValidator: submoduleAddresses.p256StatelessValidator
                });
                deployedContractsPerChain[chainId].stxValidator = calculateStxValidatorAddress(submoduleAddresses);
            }
            // Nexus
            if (keccak256(abi.encodePacked(contractNames[i])) == keccak256(abi.encodePacked("Nexus"))) {
                deployedContractsPerChain[chainId].nexus = deployNexus(chainId);
            } else {
                (deployedContractsPerChain[chainId].nexus, ) = calculateNexusAddress(deployedContractsPerChain[chainId].stxValidator, stxValidatorInitData);
            }
            // NexusBootstrap
            if (keccak256(abi.encodePacked(contractNames[i])) == keccak256(abi.encodePacked("NexusBootstrap"))) {
                deployedContractsPerChain[chainId].nexusBootstrap = deployNexusBootstrap(chainId);
            } else {
                (deployedContractsPerChain[chainId].nexusBootstrap, ) = calculateNexusBootstrapAddress(deployedContractsPerChain[chainId].stxValidator, stxValidatorInitData);
            }
            // NexusAccountFactory
            if (keccak256(abi.encodePacked(contractNames[i])) == keccak256(abi.encodePacked("NexusAccountFactory"))) {
                deployedContractsPerChain[chainId].nexusAccountFactory = deployNexusAccountFactory(chainId);
            } else {
                (deployedContractsPerChain[chainId].nexusAccountFactory, ) = calculateNexusAccountFactoryAddress(deployedContractsPerChain[chainId].nexus);
            }
            // NexusProxy
            if (keccak256(abi.encodePacked(contractNames[i])) == keccak256(abi.encodePacked("NexusProxy"))) {
                deployedContractsPerChain[chainId].nexusProxy = deployNexusProxy(chainId);
            }
            // ComposableExecutionModule
            if (
                keccak256(abi.encodePacked(contractNames[i]))
                    == keccak256(abi.encodePacked("ComposableExecutionModule"))
            ) {
                deployedContractsPerChain[chainId].composableExecutionModule = deployComposableExecutionModule();
            } else {
                (deployedContractsPerChain[chainId].composableExecutionModule, ) = calculateComposableExecutionModuleAddress();
            }
            // ComposableStorage
            if (keccak256(abi.encodePacked(contractNames[i])) == keccak256(abi.encodePacked("ComposableStorage"))) {
                deployedContractsPerChain[chainId].composableStorage = deployComposableStorage();
            } else {
                deployedContractsPerChain[chainId].composableStorage = calculateComposableStorageAddress();
            }
            // EtherForwarder
            if (keccak256(abi.encodePacked(contractNames[i])) == keccak256(abi.encodePacked("EtherForwarder"))) {
                deployedContractsPerChain[chainId].etherForwarder = deployEtherForwarder();
            } else {
                deployedContractsPerChain[chainId].etherForwarder = calculateEtherForwarderAddress();
            }
            // Disperse
            if (keccak256(abi.encodePacked(contractNames[i])) == keccak256(abi.encodePacked("Disperse"))) {
                deployedContractsPerChain[chainId].disperse = deployDisperse();
            }
            // NodePaymasterFactory
            if (keccak256(abi.encodePacked(contractNames[i])) == keccak256(abi.encodePacked("NodePaymasterFactory"))) {
                deployedContractsPerChain[chainId].nodePaymasterFactory = deployNodePaymasterFactory();
            } else {
                deployedContractsPerChain[chainId].nodePaymasterFactory = calculateNodePaymasterFactoryAddress();
            }
        }
    }

    /**
     * @notice Deploy all submodules required for StxValidator
     * @param chainId The chain ID to deploy to
     */
    function deployAllSubmodules(uint256 chainId) internal {
        console.log("  Deploying StxValidator submodules...");

        address deployed;

        deployed = DeterministicDeployerLib.broadcastDeploy(noStxModeVerifierBytecode, NO_STX_MODE_VERIFIER_SALT);
        deployedSubmodulesPerChain[chainId].noStxModeVerifier = deployed;
        console.log("    NoStxModeVerifier:", deployed);

        deployed = DeterministicDeployerLib.broadcastDeploy(simpleModeSubmoduleBytecode, SIMPLE_MODE_VERIFIER_SALT);
        deployedSubmodulesPerChain[chainId].simpleModeVerifier = deployed;
        console.log("    SimpleModeSubmodule:", deployed);

        deployed = DeterministicDeployerLib.broadcastDeploy(permitSubmoduleBytecode, PERMIT_MODE_VERIFIER_SALT);
        deployedSubmodulesPerChain[chainId].permitModeVerifier = deployed;
        console.log("    PermitSubmodule:", deployed);

        deployed = DeterministicDeployerLib.broadcastDeploy(txSubmoduleBytecode, TX_MODE_VERIFIER_SALT);
        deployedSubmodulesPerChain[chainId].txModeVerifier = deployed;
        console.log("    TxSubmodule:", deployed);

        deployed = DeterministicDeployerLib.broadcastDeploy(safeAccountSubmoduleBytecode, SAFE_ACCOUNT_SUBMODULE_SALT);
        deployedSubmodulesPerChain[chainId].safeAccountSubmodule = deployed;
        console.log("    SafeAccountSubmodule:", deployed);

        deployed = DeterministicDeployerLib.broadcastDeploy(eoaStatelessValidatorBytecode, EOA_STATELESS_VALIDATOR_SALT);
        deployedSubmodulesPerChain[chainId].eoaStatelessValidator = deployed;
        console.log("    EOAStatelessValidator:", deployed);

        deployed = DeterministicDeployerLib.broadcastDeploy(p256StatelessValidatorBytecode, P256_STATELESS_VALIDATOR_SALT);
        deployedSubmodulesPerChain[chainId].p256StatelessValidator = deployed;
        console.log("    P256StatelessValidator:", deployed);

        console.log("  Submodules deployed successfully");
    }

    /**
     * @notice Deploy StxValidator with submodule addresses
     * @param chainId The chain ID to deploy to
     * @return The deployed StxValidator address
     */
    function deployStxValidator(uint256 chainId) internal returns (address) {
        SubmoduleAddresses memory submoduleAddresses = SubmoduleAddresses({
            noStxModeVerifier: deployedSubmodulesPerChain[chainId].noStxModeVerifier,
            simpleModeVerifier: deployedSubmodulesPerChain[chainId].simpleModeVerifier,
            permitModeVerifier: deployedSubmodulesPerChain[chainId].permitModeVerifier,
            txModeVerifier: deployedSubmodulesPerChain[chainId].txModeVerifier,
            safeAccountSubmodule: deployedSubmodulesPerChain[chainId].safeAccountSubmodule,
            eoaStatelessValidator: deployedSubmodulesPerChain[chainId].eoaStatelessValidator,
            p256StatelessValidator: deployedSubmodulesPerChain[chainId].p256StatelessValidator
        });
        bytes memory args = abi.encode(submoduleAddresses);
        address stxValidator = DeterministicDeployerLib.broadcastDeploy(stxValidatorBytecode, args, STX_VALIDATOR_SALT);
        console.log("StxValidator deployed to:", stxValidator);
        return stxValidator;
    }

    function deployNexus(uint256 chainId) internal returns (address) {
        bytes memory stxValidatorInitData = _buildStxValidatorInitData(deployedSubmodulesPerChain[chainId].eoaStatelessValidator);
        bytes memory args = abi.encode(
            ENTRYPOINT_ADDRESS, deployedContractsPerChain[chainId].stxValidator, stxValidatorInitData
        );
        address nexus = DeterministicDeployerLib.broadcastDeploy(nexusBytecode, args, NEXUS_SALT);
        console.log("Nexus deployed to:", nexus);
        return nexus;
    }

    function deployNexusBootstrap(uint256 chainId) internal returns (address) {
        bytes memory stxValidatorInitData = _buildStxValidatorInitData(deployedSubmodulesPerChain[chainId].eoaStatelessValidator);
        bytes memory args =
            abi.encode(deployedContractsPerChain[chainId].stxValidator, stxValidatorInitData);
        address nexusBootstrap = DeterministicDeployerLib.broadcastDeploy(nexusBootstrapBytecode, args, NEXUSBOOTSTRAP_SALT);
        console.log("NexusBootstrap deployed to:", nexusBootstrap);
        return nexusBootstrap;
    }

    function deployNexusAccountFactory(uint256 chainId) internal returns (address) {
        bytes memory args = abi.encode(deployedContractsPerChain[chainId].nexus, FACTORY_OWNER_ADDRESS);
        address nexusAccountFactory =
            DeterministicDeployerLib.broadcastDeploy(nexusAccountFactoryBytecode, args, NEXUS_ACCOUNT_FACTORY_SALT);
        console.log("NexusAccountFactory deployed to:", nexusAccountFactory);
        console.log("  Implementation:", deployedContractsPerChain[chainId].nexus);
        return nexusAccountFactory;
    }

    function deployNexusProxy(uint256 chainId) internal returns (address) {
        bytes memory initData = abi.encode(
            deployedContractsPerChain[chainId].nexusBootstrap,
            abi.encodeWithSelector(
                NexusBootstrap.initNexusWithDefaultValidator.selector, abi.encodePacked(FACTORY_OWNER_ADDRESS)
            )
        );
        vm.startBroadcast();
        address nexusProxy =
            NexusAccountFactory(deployedContractsPerChain[chainId].nexusAccountFactory).createAccount(initData, NEXUS_PROXY_SALT);
        vm.stopBroadcast();
        console2.log("Nexus Proxy deployed at: ", nexusProxy);
        return nexusProxy;
    }

    function deployComposableExecutionModule() internal returns (address) {
        bytes memory args = abi.encode(ENTRYPOINT_ADDRESS);
        address composableExecutionModule =
            DeterministicDeployerLib.broadcastDeploy(composableExecutionModuleBytecode, args, COMPOSABLE_EXECUTION_MODULE_SALT);
        console.log("Composable Execution Module deployed to:", composableExecutionModule);
        return composableExecutionModule;
    }

    function deployComposableStorage() internal returns (address) {
        address composableStorage = DeterministicDeployerLib.broadcastDeploy(composableStorageBytecode, COMPOSABLE_STORAGE_SALT);
        console.log("Composable Storage deployed to:", composableStorage);
        return composableStorage;
    }

    function deployEtherForwarder() internal returns (address) {
        address etherForwarder = DeterministicDeployerLib.broadcastDeploy(etherForwarderBytecode, ETH_FORWARDER_SALT);
        console.log("Ether Forwarder deployed to:", etherForwarder);
        return etherForwarder;
    }

    function deployNodePaymasterFactory() internal returns (address) {
        address nodePaymasterFactory = DeterministicDeployerLib.broadcastDeploy(nodePaymasterFactoryBytecode, NODE_PMF_SALT);
        console.log("Node Paymaster Factory deployed to:", nodePaymasterFactory);
        return nodePaymasterFactory;
    }

    function deployDisperse() internal returns (address) {
        address expectedCreateXAddress = vm.envAddress("CREATEX_ADDRESS");
        CreateX createX = CreateX(expectedCreateXAddress);
        vm.startBroadcast();
        address disperse = createX.deployCreate2(DISPERSE_SALT, DISPERSE_INITCODE);
        vm.stopBroadcast();
        console.log("Disperse deployed to:", disperse);
        return disperse;
    }

    // ============

    /**
     * @notice Load configurations for a given chain
     */
    function loadConfiguration(uint256 chainId) internal {
        // Switch to the fork for this chain (already created by _loadConfigAndForks)
        vm.selectFork(forkOf[chainId]);

        // Verify we're on the correct chain
        require(block.chainid == chainId, "Chain ID mismatch");

        // Load configuration using new StdConfig pattern
        ChainConfig memory chainConfig = loadChainConfigFromStdConfig(chainId);
        chainConfigs[chainId] = chainConfig;
    }

    /**
     * @notice Load chain configuration using StdConfig
     * @param chainId The chain ID we're loading config for
     */
    function loadChainConfigFromStdConfig(
        uint256 chainId
    )
        internal
        view
        returns (ChainConfig memory)
    {
        ChainConfig memory chainConfig;

        chainConfig.chainId = chainId;

        // Use StdConfig to read variables
        chainConfig.name = config.get(chainId, "name").toString();
        chainConfig.isTestnet = config.get(chainId, "is_testnet").toBool();

        return chainConfig;
    }

    function getCodeLength(address expectedAddress, uint256 chainId) internal returns (uint256) {
        string memory rpcUrl = vm.envString(string.concat("RPC_", vm.toString(chainId)));
        vm.createSelectFork(rpcUrl);
        uint256 codeLength = address(expectedAddress).code.length;
        return codeLength;
    }

    function logContractStatusOnChain(
        uint256 chainId,
        address expectedAddress,
        string memory contractToCheck,
        uint256 codeLength
    )
        internal
        pure
    {
        console2.log(
            string.concat(
                contractToCheck,
                " is ",
                vm.toString(codeLength),
                " bytes at ",
                vm.toString(expectedAddress),
                " on chain: ",
                vm.toString(chainId)
            )
        );
    }

    function checkAndLogContractStatus(
        uint256 chainId,
        address expectedAddress,
        string memory contractToCheck,
        bool isDryRun
    )
        internal
    {
        uint256 codeLength = 0;
        if (!isDryRun) {
            codeLength = getCodeLength(expectedAddress, chainId);
        }
        logContractStatusOnChain(chainId, expectedAddress, contractToCheck, codeLength);
    }
}
