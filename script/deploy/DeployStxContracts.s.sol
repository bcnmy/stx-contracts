// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Script, console2, console } from "node_modules/forge-std/src/Script.sol";
import { Config } from "node_modules/forge-std/src/Config.sol";
import { LibVariable, Variable, TypeKind } from "node_modules/forge-std/src/LibVariable.sol";
import { NexusProxy } from "contracts/nexus/utils/NexusProxy.sol";
import { DeterministicDeployerLib } from "script/deploy/util/DeterministicDeployerLib.sol";
import { K1MeeValidator } from "contracts/validators/stx-validator/K1MeeValidator.sol";
import { NexusBootstrap } from "contracts/nexus/utils/NexusBootstrap.sol";
import { NexusAccountFactory } from "contracts/nexus/factory/NexusAccountFactory.sol";
import { INexus } from "contracts/interfaces/nexus/INexus.sol";
import { CreateX } from "script/deploy/util/CreateX.sol";

contract DeployStxContracts is Script, Config {
    /* ===== salts ===== */
    bytes32 constant MEE_K1_VALIDATOR_SALT = 0x0000000000000000000000000000000000000000370009c6e5487202d5362d82; //=>
    // 0x0000000002d3cC5642A748B6783F32C032616E03;

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

    bytes private meeK1ValidatorBytecode;
    bytes private nexusBytecode;
    bytes private nexusBootstrapBytecode;
    bytes private nexusAccountFactoryBytecode;
    bytes private composableExecutionModuleBytecode;
    bytes private composableStorageBytecode;
    bytes private etherForwarderBytecode;
    bytes private nodePaymasterFactoryBytecode;

    struct ChainConfig {
        uint256 chainId;
        string name;
        bool isTestnet;
    }

    struct DeployedContracts {
        address meeK1Validator;
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

    mapping(uint256 => DeployedContracts) internal deployedContractsPerChain;

    mapping(uint256 => ChainConfig) internal chainConfigs;
    string internal configPath = "/script/deploy/config.toml";

    function setUp() public {
        meeK1ValidatorBytecode = vm.getCode("script/deploy/artifacts/K1MeeValidator/K1MeeValidator.json");
        nexusBytecode = vm.getCode("script/deploy/artifacts/Nexus/Nexus.json");
        nexusBootstrapBytecode = vm.getCode("script/deploy/artifacts/NexusBootstrap/NexusBootstrap.json");
        nexusAccountFactoryBytecode = vm.getCode("script/deploy/artifacts/NexusAccountFactory/NexusAccountFactory.json");
        composableExecutionModuleBytecode = vm.getCode("script/deploy/artifacts/ComposableExecutionModule/ComposableExecutionModule.json");
        composableStorageBytecode = vm.getCode("script/deploy/artifacts/Storage/Storage.json");
        etherForwarderBytecode = vm.getCode("script/deploy/artifacts/EtherForwarder/EtherForwarder.json");
        nodePaymasterFactoryBytecode = vm.getCode("script/deploy/artifacts/NodePaymasterFactory/NodePaymasterFactory.json");
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

        // K1MeeValidator
        address expecteK1MeeValidatorAddress;
        expecteK1MeeValidatorAddress = calculateK1MeeValidatorAddress(chainId);
        checkAndLogContractStatus(chainId, expecteK1MeeValidatorAddress, "K1MeeValidator", isDryRun);
        if (isDryRun) {
            console.logBytes32(keccak256(meeK1ValidatorBytecode));
        }

        // Nexus
        address expectedNexusAddress;
        (expectedNexusAddress, args) = calculateNexusAddress(chainId, expecteK1MeeValidatorAddress);
        checkAndLogContractStatus(chainId, expectedNexusAddress, "Nexus", isDryRun);
        if (isDryRun) {
            console2.logBytes(args);
            console2.logBytes32(keccak256(abi.encodePacked(nexusBytecode, args)));
        }

        address expectedNexusBootstrapAddress;
        (expectedNexusBootstrapAddress, args) = calculateNexusBootstrapAddress(chainId, expecteK1MeeValidatorAddress);
        checkAndLogContractStatus(chainId, expectedNexusBootstrapAddress, "NexusBootstrap", isDryRun);
        if (isDryRun) {
            console2.logBytes(args);
            console2.logBytes32(keccak256(abi.encodePacked(nexusBootstrapBytecode, args)));
        }

        address expectedNexusAccountFactoryAddress;
        (expectedNexusAccountFactoryAddress, args) = calculateNexusAccountFactoryAddress(chainId, expectedNexusAddress);
        checkAndLogContractStatus(chainId, expectedNexusAccountFactoryAddress, "NexusAccountFactory", isDryRun);
        if (isDryRun) {
            console2.logBytes(args);
            console2.logBytes32(keccak256(abi.encodePacked(nexusAccountFactoryBytecode, args)));
        }

        // ================================ Nexus Proxy ================================
        bytes memory initData = abi.encode(
            expectedNexusBootstrapAddress,
            // or use the pre-deloyed address,
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
        /// forge-lint:disable-end(asm-keccak256)

        // Compute the predicted address
        address expectedNexusProxyAddress = payable(address(
                uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), expectedNexusAccountFactoryAddress, NEXUS_PROXY_SALT, initCodeHash))))
            ));
        checkAndLogContractStatus(chainId, expectedNexusProxyAddress, "NexusProxy", isDryRun);
        
        // ===============================================================================

        address expectedAddress;

        // composable execution module
        (expectedAddress, args) = calculateComposableExecutionModuleAddress(chainId);
        checkAndLogContractStatus(chainId, expectedAddress, "ComposableExecutionModule", isDryRun);
        if (isDryRun) {
            console2.logBytes(args);
            console2.logBytes32(keccak256(abi.encodePacked(composableExecutionModuleBytecode, args)));
        }

        // composable storage
        expectedAddress = calculateStorageAddress(chainId);
        checkAndLogContractStatus(chainId, expectedAddress, "Storage", isDryRun);
        if (isDryRun) {
            console2.logBytes32(keccak256(abi.encodePacked(composableStorageBytecode)));
        }

        // ether forwarder
        expectedAddress = calculateEtherForwarderAddress(chainId);
        checkAndLogContractStatus(chainId, expectedAddress, "EtherForwarder", isDryRun);
        if (isDryRun) {
            console2.logBytes32(keccak256(etherForwarderBytecode));
        }

        // node paymaster factory
        expectedAddress = calculateNodePaymasterFactoryAddress(chainId);
        checkAndLogContractStatus(chainId, expectedAddress, "NodePaymasterFactory", isDryRun);
        if (isDryRun) {
            console2.logBytes32(keccak256(nodePaymasterFactoryBytecode));
        }
    }

    function calculateK1MeeValidatorAddress(uint256 chainId) internal returns (address) {
        return DeterministicDeployerLib.computeAddress(meeK1ValidatorBytecode, MEE_K1_VALIDATOR_SALT);
    }

    function calculateNexusAddress(uint256 chainId, address meeK1ValidatorAddress) internal returns (address, bytes memory) {
        bytes memory args = abi.encode(ENTRYPOINT_ADDRESS, meeK1ValidatorAddress, abi.encodePacked(EEEEEE_ADDRESS));
        address nexusAddress = DeterministicDeployerLib.computeAddress(nexusBytecode, args, NEXUS_SALT);
        return (nexusAddress, args);
    }

    function calculateNexusBootstrapAddress(uint256 chainId, address meeK1ValidatorAddress) internal returns (address, bytes memory) {
        bytes memory args = abi.encode(meeK1ValidatorAddress, abi.encodePacked(EEEEEE_ADDRESS));
        address nexusBootstrapAddress = DeterministicDeployerLib.computeAddress(nexusBootstrapBytecode, args, NEXUSBOOTSTRAP_SALT);
        return (nexusBootstrapAddress, args);
    }
    
    function calculateNexusAccountFactoryAddress(uint256 chainId, address nexusAddress) internal returns (address, bytes memory) {
        bytes memory args = abi.encode(nexusAddress, FACTORY_OWNER_ADDRESS);
        address nexusAccountFactoryAddress = DeterministicDeployerLib.computeAddress(nexusAccountFactoryBytecode, args, NEXUS_ACCOUNT_FACTORY_SALT);
        return (nexusAccountFactoryAddress, args);
    }

    function calculateComposableExecutionModuleAddress(uint256 chainId) internal returns (address, bytes memory) {
        bytes memory args = abi.encode(ENTRYPOINT_ADDRESS);
        address composableExecutionModuleAddress = DeterministicDeployerLib.computeAddress(composableExecutionModuleBytecode, args, COMPOSABLE_EXECUTION_MODULE_SALT);
        return (composableExecutionModuleAddress, args);
    }

    function calculateStorageAddress(uint256 chainId) internal returns (address) {
        return DeterministicDeployerLib.computeAddress(composableStorageBytecode, COMPOSABLE_STORAGE_SALT);
    }

    function calculateEtherForwarderAddress(uint256 chainId) internal returns (address) {
        return DeterministicDeployerLib.computeAddress(etherForwarderBytecode, ETH_FORWARDER_SALT);
    }

    function calculateNodePaymasterFactoryAddress(uint256 chainId) internal returns (address) {
        return DeterministicDeployerLib.computeAddress(nodePaymasterFactoryBytecode, NODE_PMF_SALT);
    }

    function deployContracts(uint256 chainId, string[] memory contractNames) internal {
        ChainConfig memory config = chainConfigs[chainId];

        console.log("\n=====================================");
        console.log("Deploying to:", config.name);
        console.log("Chain ID:", chainId);
        console.log("=====================================\n");


        // Fallback flow of creating a fork not via config but from .env file
        // Use the RPC_{chainId} environment variable directly
        // string memory rpcUrl = vm.envString(string.concat("RPC_", vm.toString(chainId)));
        // Create and switch to fork for the chain
        // vm.createSelectFork(rpcUrl);

        // Verify chain ID
        require(block.chainid == chainId, "Chain ID mismatch");

        for (uint256 i = 0; i < contractNames.length; i++) {
            // K1MeeValidator
            if (keccak256(abi.encodePacked(contractNames[i])) == keccak256(abi.encodePacked("K1MeeValidator"))) {
                deployedContractsPerChain[chainId].meeK1Validator = deployK1MeeValidator();
            } else {
                deployedContractsPerChain[chainId].meeK1Validator = calculateK1MeeValidatorAddress(chainId);
            }
            // Nexus
            if (keccak256(abi.encodePacked(contractNames[i])) == keccak256(abi.encodePacked("Nexus"))) {
                deployedContractsPerChain[chainId].nexus = deployNexus(chainId);
            } else {
                (deployedContractsPerChain[chainId].nexus, ) = calculateNexusAddress(chainId, deployedContractsPerChain[chainId].meeK1Validator);
            }
            // NexusBootstrap
            if (keccak256(abi.encodePacked(contractNames[i])) == keccak256(abi.encodePacked("NexusBootstrap"))) {
                deployedContractsPerChain[chainId].nexusBootstrap = deployNexusBootstrap(chainId);
            } else {
                (deployedContractsPerChain[chainId].nexusBootstrap, ) = calculateNexusBootstrapAddress(chainId, deployedContractsPerChain[chainId].meeK1Validator);
            }
            // NexusAccountFactory
            if (keccak256(abi.encodePacked(contractNames[i])) == keccak256(abi.encodePacked("NexusAccountFactory"))) {
                deployedContractsPerChain[chainId].nexusAccountFactory = deployNexusAccountFactory(chainId);
            } else {
                (deployedContractsPerChain[chainId].nexusAccountFactory, ) = calculateNexusAccountFactoryAddress(chainId, deployedContractsPerChain[chainId].nexus);
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
                (deployedContractsPerChain[chainId].composableExecutionModule, ) = calculateComposableExecutionModuleAddress(chainId);
            }
            // Storage
            if (keccak256(abi.encodePacked(contractNames[i])) == keccak256(abi.encodePacked("Storage"))) {
                deployedContractsPerChain[chainId].composableStorage = deployStorage();
            } else {
                deployedContractsPerChain[chainId].composableStorage = calculateStorageAddress(chainId);
            }
            // EtherForwarder
            if (keccak256(abi.encodePacked(contractNames[i])) == keccak256(abi.encodePacked("EtherForwarder"))) {
                deployedContractsPerChain[chainId].etherForwarder = deployEtherForwarder();
            } else {
                deployedContractsPerChain[chainId].etherForwarder = calculateEtherForwarderAddress(chainId);
            }
            // Disperse
            if (keccak256(abi.encodePacked(contractNames[i])) == keccak256(abi.encodePacked("Disperse"))) {
                deployedContractsPerChain[chainId].disperse = deployDisperse();
            } 
            // NodePaymasterFactory
            if (keccak256(abi.encodePacked(contractNames[i])) == keccak256(abi.encodePacked("NodePaymasterFactory"))) {
                deployedContractsPerChain[chainId].nodePaymasterFactory = deployNodePaymasterFactory();
            } else {
                deployedContractsPerChain[chainId].nodePaymasterFactory = calculateNodePaymasterFactoryAddress(chainId);
            }
        }
    }

    function deployK1MeeValidator() internal returns (address) {
        address meeK1Validator = DeterministicDeployerLib.broadcastDeploy(meeK1ValidatorBytecode, MEE_K1_VALIDATOR_SALT);
        console.log("K1MeeValidator deployed to:", meeK1Validator);
        return meeK1Validator;
    }

    function deployNexus(uint256 chainId) internal returns (address) {
        bytes memory args = abi.encode(
            ENTRYPOINT_ADDRESS, deployedContractsPerChain[chainId].meeK1Validator, abi.encodePacked(EEEEEE_ADDRESS)
        );
        address nexus = DeterministicDeployerLib.broadcastDeploy(nexusBytecode, args, NEXUS_SALT);
        console.log("Nexus deployed to:", nexus);
        return nexus;
    }

    function deployNexusBootstrap(uint256 chainId) internal returns (address) {
        bytes memory args =
            abi.encode(deployedContractsPerChain[chainId].meeK1Validator, abi.encodePacked(EEEEEE_ADDRESS));
        address nexusBootstrap = DeterministicDeployerLib.broadcastDeploy(nexusBootstrapBytecode, args, NEXUSBOOTSTRAP_SALT);
        console.log("NexusBootstrap deployed to:", nexusBootstrap);
        return nexusBootstrap;
    }

    function deployNexusAccountFactory(uint256 chainId) internal returns (address) {
        bytes memory args = abi.encode(deployedContractsPerChain[chainId].nexus, FACTORY_OWNER_ADDRESS);
        address nexusAccountFactory =
            DeterministicDeployerLib.broadcastDeploy(nexusAccountFactoryBytecode, args, NEXUS_ACCOUNT_FACTORY_SALT);
        console.log("NexusAccountFactory deployed to:", nexusAccountFactory, "with implementation:", NexusAccountFactory(nexusAccountFactory).ACCOUNT_IMPLEMENTATION());
        return nexusAccountFactory;
    }

    function deployNexusProxy(uint256 chainId) internal returns (address) {
        bytes memory initData = abi.encode(
            deployedContractsPerChain[chainId].nexusBootstrap,
            // or use the pre-deloyed address,
            abi.encodeWithSelector(
                NexusBootstrap.initNexusWithDefaultValidator.selector, abi.encodePacked(FACTORY_OWNER_ADDRESS)
            )
        );
        vm.startBroadcast();
        address nexusProxy =
            NexusAccountFactory(deployedContractsPerChain[chainId].nexusAccountFactory).createAccount(initData, NEXUS_PROXY_SALT);
            // or use the pre-deloyed address for the NexusAccountFactory,
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

    function deployStorage() internal returns (address) {
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
