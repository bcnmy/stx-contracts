// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Script, console2, console } from "node_modules/forge-std/src/Script.sol";
import { Config } from "node_modules/forge-std/src/Config.sol";
import { LibVariable, Variable, TypeKind } from "node_modules/forge-std/src/LibVariable.sol";

import { DeterministicDeployerLib } from "script/deploy/util/DeterministicDeployerLib.sol";
import { K1MeeValidator } from "contracts/validators/stx-validator/K1MeeValidator.sol";
import { NexusBootstrap } from "contracts/nexus/utils/NexusBootstrap.sol";
import { NexusAccountFactory } from "contracts/nexus/factory/NexusAccountFactory.sol";
import { CreateX } from "script/deploy/util/CreateX.sol";

contract DeployStxContracts is Script, Config {
    /* ===== salts ===== */
    bytes32 constant MEE_K1_VALIDATOR_SALT = 0x00000000000000000000000000000000000000005ec01b7f9f6e300427d823ea; //=>
    // 0x00000002987de8E966e1202534f018B028384eaC;

    bytes32 constant NEXUS_SALT = 0x0000000000000000000000000000000000000000657b02ac499d6d001a3fda49; // =>
    // 0x00000099da5B22B6d0D64f966f7138e0c70FAf57;

    bytes32 constant NEXUSBOOTSTRAP_SALT = 0x0000000000000000000000000000000000000000d1daf021ab489402fcf69290; // =>
    // 0x000000dD827476e7Ba18C12d0a754124Fe84d6f6

    bytes32 constant NEXUS_ACCOUNT_FACTORY_SALT = 0x0000000000000000000000000000000000000000b41ef430bf3b3b04dcce4193; //
    // => 0x0000009FD552C6c8D9F2F139b254Ec9b0C132360;

    bytes32 constant COMPOSABLE_EXECUTION_MODULE_SALT =
        0x0000000000000000000000000000000000000000a7f26e3d794af2032a4a54a4; // =>
    // 0x000000e0Ac0Bcd4Cbc716B152fecbA0F706d6605
    bytes32 constant COMPOSABLE_STORAGE_SALT = 0x00000000000000000000000000000000000000000e67edf598940102c215065c; // =>
    // 0x0000000671eb337E12fe5dB0e788F32e1D71B183;

    bytes32 constant ETH_FORWARDER_SALT = 0x0000000000000000000000000000000000000000f9941fb84509c0031a6fc104; //=>
    // 0x000000Afe527A978Ecb761008Af475cfF04132a1;

    bytes32 constant NODE_PMF_SALT = 0x0000000000000000000000000000000000000000b2c8417146408700c86d4370; // =>
    // 0x000000006fcc00f06a507E4284cc17e767189b04

    bytes32 public constant DISPERSE_SALT = 0xfd73487f4e6544007a3ce4000000000000000000000000000000000000000000;
    bytes public constant DISPERSE_INITCODE =
        hex"608060405234801561001057600080fd5b506106f4806100206000396000f300608060405260043610610057576000357c0100000000000000000000000000000000000000000000000000000000900463ffffffff16806351ba162c1461005c578063c73a2d60146100cf578063e63d38ed14610142575b600080fd5b34801561006857600080fd5b506100cd600480360381019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803590602001908201803590602001919091929391929390803590602001908201803590602001919091929391929390505050610188565b005b3480156100db57600080fd5b50610140600480360381019080803573ffffffffffffffffffffffffffffffffffffffff169060200190929190803590602001908201803590602001919091929391929390803590602001908201803590602001919091929391929390505050610309565b005b6101866004803603810190808035906020019082018035906020019190919293919293908035906020019082018035906020019190919293919293905050506105b0565b005b60008090505b84849050811015610301578573ffffffffffffffffffffffffffffffffffffffff166323b872dd3387878581811015156101c457fe5b9050602002013573ffffffffffffffffffffffffffffffffffffffff1686868681811015156101ef57fe5b905060200201356040518463ffffffff167c0100000000000000000000000000000000000000000000000000000000028152600401808473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1681526020018373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1681526020018281526020019350505050602060405180830381600087803b1580156102ae57600080fd5b505af11580156102c2573d6000803e3d6000fd5b505050506040513d60208110156102d857600080fd5b810190808051906020019092919050505015156102f457600080fd5b808060010191505061018e565b505050505050565b60008060009150600090505b8585905081101561034657838382818110151561032e57fe5b90506020020135820191508080600101915050610315565b8673ffffffffffffffffffffffffffffffffffffffff166323b872dd3330856040518463ffffffff167c0100000000000000000000000000000000000000000000000000000000028152600401808473ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1681526020018373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1681526020018281526020019350505050602060405180830381600087803b15801561041d57600080fd5b505af1158015610431573d6000803e3d6000fd5b505050506040513d602081101561044757600080fd5b8101908080519060200190929190505050151561046357600080fd5b600090505b858590508110156105a7578673ffffffffffffffffffffffffffffffffffffffff1663a9059cbb878784818110151561049d57fe5b9050602002013573ffffffffffffffffffffffffffffffffffffffff1686868581811015156104c857fe5b905060200201356040518363ffffffff167c0100000000000000000000000000000000000000000000000000000000028152600401808373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200182815260200192505050602060405180830381600087803b15801561055457600080fd5b505af1158015610568573d6000803e3d6000fd5b505050506040513d602081101561057e57600080fd5b8101908080519060200190929190505050151561059a57600080fd5b8080600101915050610468565b50505050505050565b600080600091505b858590508210156106555785858381811015156105d157fe5b9050602002013573ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff166108fc858585818110151561061557fe5b905060200201359081150290604051600060405180830381858888f19350505050158015610647573d6000803e3d6000fd5b5081806001019250506105b8565b3073ffffffffffffffffffffffffffffffffffffffff1631905060008111156106c0573373ffffffffffffffffffffffffffffffffffffffff166108fc829081150290604051600060405180830381858888f193505050501580156106be573d6000803e3d6000fd5b505b5050505050505600a165627a7a723058204f25a733917e0bf639cd1e101d55bd927f843fb395fb2a963a7909c09ae023ed0029";

    address constant ENTRYPOINT_ADDRESS = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;
    address constant EEEEEE_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address constant FACTORY_OWNER_ADDRESS = 0x129443cA2a9Dec2020808a2868b38dDA457eaCC7;

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

    /**
     * @notice Deploy to specific chains
     * @param chainId The chain ID to deploy to
     * @param contractNames Array of contract names to deploy (empty array = all contracts)
     */
    function run(uint256 chainId, string[] memory contractNames) external {
        // Load configuration and setup forks (enable write-back to save deployed addresses)
        string memory fullConfigPath = string.concat(vm.projectRoot(), configPath);
        console.log("Loading config from:", fullConfigPath);
        _loadConfigAndForks(fullConfigPath, true);

        // Load configuration for each chain
        loadConfigurations(chainId, contractNames);

        // Move above to the base contract

        deployContracts(chainId, contractNames);
    }

    /**
     * @notice calculate if the specific contract is already deployed to the given chain
     * @param chainId The chain ID to deploy to
     * @param isDryRun Whether to perform a dry run (only calculate expected addresses)
     */
    function run(uint256 chainId, bool isDryRun) external {
        bytes memory bytecode = vm.getCode("script/deploy/artifacts/K1MeeValidator/K1MeeValidator.json");
        address expectedAddress = DeterministicDeployerLib.computeAddress(bytecode, MEE_K1_VALIDATOR_SALT);
        checkAndLogContractStatus(chainId, expectedAddress, "K1MeeValidator", isDryRun);
        if (isDryRun) {
            console.logBytes32(keccak256(bytecode));
        }

        bytecode = vm.getCode("script/deploy/artifacts/Nexus/Nexus.json");
        bytes memory args = abi.encode(
            ENTRYPOINT_ADDRESS, deployedContractsPerChain[chainId].meeK1Validator, abi.encodePacked(EEEEEE_ADDRESS)
        );
        expectedAddress = DeterministicDeployerLib.computeAddress(bytecode, args, NEXUS_SALT);
        checkAndLogContractStatus(chainId, expectedAddress, "Nexus", isDryRun);
        if (isDryRun) {
            console2.logBytes(args);
            console2.logBytes32(keccak256(abi.encodePacked(bytecode, args)));
        }

        bytecode = vm.getCode("script/deploy/artifacts/NexusBootstrap/NexusBootstrap.json");
        args = abi.encode(deployedContractsPerChain[chainId].meeK1Validator, abi.encodePacked(EEEEEE_ADDRESS));
        expectedAddress = DeterministicDeployerLib.computeAddress(bytecode, args, NEXUSBOOTSTRAP_SALT);
        checkAndLogContractStatus(chainId, expectedAddress, "NexusBootstrap", isDryRun);
        if (isDryRun) {
            console2.logBytes(args);
            console2.logBytes32(keccak256(abi.encodePacked(bytecode, args)));
        }

        bytecode = vm.getCode("script/deploy/artifacts/NexusAccountFactory/NexusAccountFactory.json");
        args = abi.encode(deployedContractsPerChain[chainId].nexus, FACTORY_OWNER_ADDRESS);
        expectedAddress = DeterministicDeployerLib.computeAddress(bytecode, args, NEXUS_ACCOUNT_FACTORY_SALT);
        checkAndLogContractStatus(chainId, expectedAddress, "NexusAccountFactory", isDryRun);
        if (isDryRun) {
            console2.logBytes(args);
            console2.logBytes32(keccak256(abi.encodePacked(bytecode, args)));
        }

        bytecode = vm.getCode("script/deploy/artifacts/ComposableExecutionModule/ComposableExecutionModule.json");
        args = abi.encode(ENTRYPOINT_ADDRESS);
        expectedAddress = DeterministicDeployerLib.computeAddress(bytecode, args, COMPOSABLE_EXECUTION_MODULE_SALT);
        checkAndLogContractStatus(chainId, expectedAddress, "ComposableExecutionModule", isDryRun);
        if (isDryRun) {
            console2.logBytes(args);
            console2.logBytes32(keccak256(abi.encodePacked(bytecode, args)));
        }

        bytecode = vm.getCode("script/deploy/artifacts/ComposableStorage/ComposableStorage.json");
        expectedAddress = DeterministicDeployerLib.computeAddress(bytecode, COMPOSABLE_STORAGE_SALT);
        checkAndLogContractStatus(chainId, expectedAddress, "ComposableStorage", isDryRun);
        if (isDryRun) {
            console2.logBytes32(keccak256(bytecode));
        }

        bytecode = vm.getCode("script/deploy/artifacts/EtherForwarder/EtherForwarder.json");
        expectedAddress = DeterministicDeployerLib.computeAddress(bytecode, ETH_FORWARDER_SALT);
        checkAndLogContractStatus(chainId, expectedAddress, "EtherForwarder", isDryRun);
        if (isDryRun) {
            console2.logBytes32(keccak256(bytecode));
        }

        bytecode = vm.getCode("script/deploy/artifacts/NodePaymasterFactory/NodePaymasterFactory.json");
        expectedAddress = DeterministicDeployerLib.computeAddress(bytecode, NODE_PMF_SALT);
        checkAndLogContractStatus(chainId, expectedAddress, "NodePaymasterFactory", isDryRun);
        if (isDryRun) {
            console2.logBytes32(keccak256(bytecode));
        }
    }

    function deployContracts(uint256 chainId, string[] memory contractNames) internal {
        ChainConfig memory config = chainConfigs[chainId];

        console.log("\n=====================================");
        console.log("Deploying to:", config.name);
        console.log("Chain ID:", chainId);
        console.log("=====================================\n");

        // Use the RPC_{chainId} environment variable directly
        string memory rpcUrl = vm.envString(string.concat("RPC_", vm.toString(chainId)));

        // Create and switch to fork for the chain
        vm.createSelectFork(rpcUrl);

        // Verify chain ID
        require(block.chainid == chainId, "Chain ID mismatch");

        for (uint256 i = 0; i < contractNames.length; i++) {
            if (keccak256(abi.encodePacked(contractNames[i])) == keccak256(abi.encodePacked("K1MeeValidator"))) {
                address meeK1Validator = deployK1MeeValidator();
                deployedContractsPerChain[chainId].meeK1Validator = meeK1Validator;
            }
            if (keccak256(abi.encodePacked(contractNames[i])) == keccak256(abi.encodePacked("Nexus"))) {
                deployedContractsPerChain[chainId].nexus = deployNexus(chainId);
            }
            if (keccak256(abi.encodePacked(contractNames[i])) == keccak256(abi.encodePacked("NexusBootstrap"))) {
                deployedContractsPerChain[chainId].nexusBootstrap = deployNexusBootstrap(chainId);
            }
            if (keccak256(abi.encodePacked(contractNames[i])) == keccak256(abi.encodePacked("NexusAccountFactory"))) {
                deployedContractsPerChain[chainId].nexusAccountFactory = deployNexusAccountFactory(chainId);
            }
            if (keccak256(abi.encodePacked(contractNames[i])) == keccak256(abi.encodePacked("NexusProxy"))) {
                deployedContractsPerChain[chainId].nexusProxy = deployNexusProxy(chainId);
            }
            if (
                keccak256(abi.encodePacked(contractNames[i]))
                    == keccak256(abi.encodePacked("ComposableExecutionModule"))
            ) {
                deployedContractsPerChain[chainId].composableExecutionModule = deployComposableExecutionModule();
            }
            if (keccak256(abi.encodePacked(contractNames[i])) == keccak256(abi.encodePacked("StorageContract"))) {
                deployedContractsPerChain[chainId].composableStorage = deployComposableStorage();
            }
            if (keccak256(abi.encodePacked(contractNames[i])) == keccak256(abi.encodePacked("EtherForwarder"))) {
                deployedContractsPerChain[chainId].etherForwarder = deployEtherForwarder();
            }
            if (keccak256(abi.encodePacked(contractNames[i])) == keccak256(abi.encodePacked("Disperse"))) {
                deployedContractsPerChain[chainId].disperse = deployDisperse();
            }
        }
    }

    function deployK1MeeValidator() internal returns (address) {
        bytes memory bytecode = vm.getCode("script/deploy/artifacts/K1MeeValidator/K1MeeValidator.json");
        address meeK1Validator = DeterministicDeployerLib.broadcastDeploy(bytecode, MEE_K1_VALIDATOR_SALT);
        console.log("K1MeeValidator deployed to:", meeK1Validator);
        return meeK1Validator;
    }

    function deployNexus(uint256 chainId) internal returns (address) {
        bytes memory bytecode = vm.getCode("script/deploy/artifacts/Nexus/Nexus.json");
        bytes memory args = abi.encode(
            ENTRYPOINT_ADDRESS, deployedContractsPerChain[chainId].meeK1Validator, abi.encodePacked(EEEEEE_ADDRESS)
        );
        address nexus = DeterministicDeployerLib.broadcastDeploy(bytecode, args, NEXUS_SALT);
        console.log("Nexus deployed to:", nexus);
        return nexus;
    }

    function deployNexusBootstrap(uint256 chainId) internal returns (address) {
        bytes memory bytecode = vm.getCode("script/deploy/artifacts/NexusBootstrap/NexusBootstrap.json");
        bytes memory args =
            abi.encode(deployedContractsPerChain[chainId].meeK1Validator, abi.encodePacked(EEEEEE_ADDRESS));
        address nexusBootstrap = DeterministicDeployerLib.broadcastDeploy(bytecode, args, NEXUSBOOTSTRAP_SALT);
        console.log("NexusBootstrap deployed to:", nexusBootstrap);
        return nexusBootstrap;
    }

    function deployNexusAccountFactory(uint256 chainId) internal returns (address) {
        bytes memory bytecode = vm.getCode("script/deploy/artifacts/NexusAccountFactory/NexusAccountFactory.json");
        bytes memory args = abi.encode(deployedContractsPerChain[chainId].nexus, FACTORY_OWNER_ADDRESS);
        address nexusAccountFactory =
            DeterministicDeployerLib.broadcastDeploy(bytecode, args, NEXUS_ACCOUNT_FACTORY_SALT);
        console.log("NexusAccountFactory deployed to:", nexusAccountFactory);
        return nexusAccountFactory;
    }

    function deployNexusProxy(uint256 chainId) internal returns (address) {
        bytes32 salt = 0x0000000000000000000000000000000000000000000000000000000000000001;
        bytes memory initData = abi.encode(
            deployedContractsPerChain[chainId].nexusBootstrap,
            abi.encodeWithSelector(
                NexusBootstrap.initNexusWithDefaultValidator.selector, abi.encodePacked(EEEEEE_ADDRESS)
            )
        );
        vm.startBroadcast();
        address nexusProxy =
            NexusAccountFactory(deployedContractsPerChain[chainId].nexusAccountFactory).createAccount(initData, salt);
        vm.stopBroadcast();
        console2.log("Nexus Proxy deployed at: ", nexusProxy);
        return nexusProxy;
    }

    function deployComposableExecutionModule() internal returns (address) {
        bytes memory bytecode =
            vm.getCode("script/deploy/artifacts/ComposableExecutionModule/ComposableExecutionModule.json");
        bytes memory args = abi.encode(ENTRYPOINT_ADDRESS);
        address composableExecutionModule =
            DeterministicDeployerLib.broadcastDeploy(bytecode, args, COMPOSABLE_EXECUTION_MODULE_SALT);
        console.log("Composable Execution Module deployed to:", composableExecutionModule);
        return composableExecutionModule;
    }

    function deployComposableStorage() internal returns (address) {
        bytes memory bytecode = vm.getCode("script/deploy/artifacts/ComposableStorage/ComposableStorage.json");
        address composableStorage = DeterministicDeployerLib.broadcastDeploy(bytecode, COMPOSABLE_STORAGE_SALT);
        console.log("Composable Storage deployed to:", composableStorage);
        return composableStorage;
    }

    function deployEtherForwarder() internal returns (address) {
        bytes memory bytecode = vm.getCode("script/deploy/artifacts/EtherForwarder/EtherForwarder.json");
        address etherForwarder = DeterministicDeployerLib.broadcastDeploy(bytecode, ETH_FORWARDER_SALT);
        console.log("Ether Forwarder deployed to:", etherForwarder);
        return etherForwarder;
    }

    function deployNodePaymasterFactory() internal returns (address) {
        bytes memory bytecode = vm.getCode("script/deploy/artifacts/NodePaymasterFactory/NodePaymasterFactory.json");
        address nodePaymasterFactory = DeterministicDeployerLib.broadcastDeploy(bytecode, NODE_PMF_SALT);
        console.log("Node Paymaster Factory deployed to:", nodePaymasterFactory);
        return nodePaymasterFactory;
    }

    function deployDisperse() internal returns (address) {
        address expectedCreateXAddress = vm.envAddress("CREATEX_ADDRESS");
        CreateX createX = CreateX(expectedCreateXAddress);
        address disperse = createX.deployCreate2(DISPERSE_SALT, DISPERSE_INITCODE);
        console.log("Disperse deployed to:", disperse);
        return disperse;
    }

    // ============

    /**
     * @notice Load configurations for all target chains
     */
    function loadConfigurations(uint256 chainId, string[] memory contractNames) internal {
        // Switch to the fork for this chain (already created by _loadConfigAndForks)
        vm.selectFork(forkOf[chainId]);

        // Verify we're on the correct chain
        require(block.chainid == chainId, "Chain ID mismatch");

        // Load configuration using new StdConfig pattern
        ChainConfig memory chainConfig = loadChainConfigFromStdConfig(chainId, contractNames);
        chainConfigs[chainId] = chainConfig;
    }

    /**
     * @notice Load chain configuration using StdConfig
     * @param chainId The chain ID we're loading config for
     */
    function loadChainConfigFromStdConfig(
        uint256 chainId,
        string[] memory contractNames
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
