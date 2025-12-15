# STX Contracts Deployment Scripts

A script for deploying Biconomy STX contracts across multiple EVM chains using deterministic deployment (CREATE2) to ensure consistent addresses.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Usage](#usage)
- [Contracts Deployed](#contracts-deployed)
- [Directory Structure](#directory-structure)
- [Advanced Configuration](#advanced-configuration)
- [Troubleshooting](#troubleshooting)

---

## Overview

The deployment system provides automated, multi-chain deployment of STX contracts with the following features:

- **Deterministic Deployment**: Uses CREATE2 for consistent contract addresses across chains
- **Multi-Chain Support**: Deploy to one, several, or all configured chains in a single run
- **Idempotent**: Automatically detects already-deployed contracts and skips them
- **Prerequisite Management**: Automatically deploys dependencies (Create2Factory, EntryPoint v0.7, CreateX)
- **Contract Verification**: Optional automatic verification on block explorers
- **Comprehensive Logging**: Detailed logs for each deployment step
- **Gas Optimization**: Configurable gas prices and gas estimation multipliers per chain

### Main Script

**`deploy-stx.sh`** - The primary deployment orchestrator that:
1. Validates environment variables and RPC endpoints
2. Computes expected contract addresses via dry-run
3. Deploys contracts to one or more chains in parallel
4. Logs all operations to `deploy-logs/` directory

---

## Architecture

### Deployment Flow

```
deploy-stx.sh
    ├─> Validates environment (.env file)
    ├─> Validates RPC URLs (ValidateForks.s.sol)
    ├─> Computes expected addresses (DeployStxContracts.s.sol dry-run)
    ├─> User confirmation
    └─> For each chain:
            deploy-chain.sh
                ├─> Deploy prerequisites (Create2Factory, EntryPoint, CreateX)
                ├─> Identify contracts to deploy (dry-run)
                ├─> Deploy contracts (DeployStxContracts.s.sol)
                └─> Verify contracts (optional)
```

### Key Components

| File | Purpose |
|------|---------|
| **deploy-stx.sh** | Main orchestrator - handles multi-chain deployment |
| **deploy-chain.sh** | Per-chain deployment logic |
| **config.toml** | Chain configuration (RPC URLs, gas settings, verification) |
| **DeployStxContracts.s.sol** | Solidity script for contract deployment |
| **build-artifacts.sh** | Build and prepare contract artifacts |

---

## Deployment Configuration

### Chain Configuration (config.toml)

The [config.toml](config.toml) file defines all supported chains and their deployment parameters.

#### Configuration Structure

```toml
[<chain_id>]
endpoint_url = "${RPC_<chain_id>}"

[<chain_id>.bool]
is_testnet = true/false
verify = true/false

[<chain_id>.uint]
chain_id = <chain_id>
base_gas_price = <optional_value>          # in gwei
priority_gas_price = <optional_value>      # in gwei
gas_estimate_multiply = <optional_value>   # in percentage (e.g., 101 = 101%)

[<chain_id>.string]
name = "<Chain Name>"
```

#### Example: Base Sepolia

```toml
[84532]
endpoint_url = "${RPC_84532}"

[84532.bool]
is_testnet = true
verify = true

[84532.uint]
chain_id = 84532

[84532.string]
name = "Base Sepolia"
```

#### Supported Chains

The deployment scripts support 40+ chains including:

**Mainnets**: Ethereum, Base, Polygon, Arbitrum, Optimism, BNB, Sonic, Scroll, Gnosis, Avalanche, Apechain, HyperEvm, Sei, Unichain, Katana, Lisk, Worldchain, Monad, Plasma

**Testnets**: Sepolia, Base Sepolia, Polygon Amoy, Arbitrum Sepolia, Optimism Sepolia, BNB Testnet, Sonic Blaze, Scroll Sepolia, Gnosis Chiado, Avalanche Fuji, Apechain Curtis, Core Testnet, Neura Testnet, Sei Testnet, Unichain Sepolia, Worldchain Sepolia, Fluent Testnet, Monad Testnet, Plasma Testnet, Arc Testnet, Sophon ZK Testnet

See [config.toml](config.toml) for the complete list with chain IDs.

---

## Usage

### Navigate to Deployment Directory

```bash
cd script/deploy
```

### Option 1: Build Artifacts (Recommended for New Deployments)

If you've made changes to the contracts:

```bash
bash build-artifacts.sh
```

This will:
- Build contracts using Foundry with `via-ir` profile
- Copy artifacts to `artifacts/` directory
- Generate verification JSON files

Default artu=ifcats are commited to the repo, so if you haven't introduced any changes, no need to rebuild them.

### Option 2: Deploy to All Configured Chains

```bash
bash deploy-stx.sh
```

This will deploy to **all chains** defined in [config.toml](config.toml).

### Option 3: Deploy to Specific Chains

Deploy to one or more specific chains by providing chain IDs:

```bash
# Deploy to Base Sepolia only
bash deploy-stx.sh 84532

# Deploy to multiple chains
bash deploy-stx.sh 84532 11155420 421614

# Deploy to Ethereum Mainnet and Base Mainnet
bash deploy-stx.sh 1 8453
```

### Deployment Process

1. **Environment Validation**: Checks for required environment variables
2. **RPC Validation**: Attempts to create forks to validate all RPC URLs
3. **Address Calculation**: Computes expected contract addresses using CREATE2
4. **User Confirmation**: Displays expected addresses and asks for confirmation
5. **Deployment Execution**: Deploys contracts to each chain sequentially
6. **Verification** (optional): Verifies contracts on block explorers

### Example Output

```bash
[INFO] Loading environment variables from .env
[INFO] Validating required environment variables
[INFO] Checking RPC URLs for the requested chains...
[INFO] Trying to create forks for the requested chains...
[INFO] Forks successfully created, all RPC's from config are accessible
[INFO] Getting expected addresses for the contracts...

K1MeeValidator  0x0000000055C766a7060797FBc7Be40c08B296b72
Nexus          0x00000000561Dd60aEa485cDb26E4618B1E40Fd6E
NexusBootstrap 0x000000006f105FED549ee4304269Cc4a6111Fa6e
...

Do you want to proceed with the addresses above? (y/n): y

[INFO] Deploying Stx contracts to chain 84532 (Base-Sepolia)...
[INFO] Stx contracts deployed to chain 84532 (Base-Sepolia) successfully
```

---

## Contracts Deployed

The deployment scripts deploy the following contracts:

### Core Contracts

| Contract | Description | Address Type |
|----------|-------------|--------------|
| **K1MeeValidator** | ERC-7579 validator for SuperTransactions using secp256k1 | Deterministic (CREATE2) |
| **Nexus** | ERC-7579 modular smart account implementation | Deterministic (CREATE2) |
| **NexusBootstrap** | Bootstrap utility for initializing Nexus accounts | Deterministic (CREATE2) |
| **NexusAccountFactory** | Factory for deploying Nexus smart accounts | Deterministic (CREATE2) |
| **NexusProxy** | Proxy instance for testing (optional) | Factory-deployed |
| **ComposableExecutionModule** | ERC-7579 module for composable execution | Deterministic (CREATE2) |
| **ComposableStorage** | Storage contract for composable execution | Deterministic (CREATE2) |
| **EtherForwarder** | Utility for batch ETH transfers | Deterministic (CREATE2) |
| **NodePaymasterFactory** | Factory for deploying Node Paymasters | Deterministic (CREATE2) |
| **Disperse** | Utility for batch token/ETH transfers | CreateX (CREATE2) |

### Prerequisites (Auto-Deployed)

| Contract | Address | Description |
|----------|---------|-------------|
| **Create2Factory** | `0x4e59b44847b379578588920ca78fbf26c0b4956c` | CREATE2 factory for deterministic deployments |
| **EntryPoint v0.7** | `0x0000000071727De22E5E9d8BAf0edAc6f37da032` | ERC-4337 EntryPoint |
| **CreateX** | `0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed` | Enhanced CREATE2 deployer |

### Deployment Salts

The following salts are used for deterministic deployments (defined in [DeployStxContracts.s.sol](DeployStxContracts.s.sol)):

```solidity
MEE_K1_VALIDATOR_SALT              = 0x0000000000000000000000000000000000000000972d15c771cbed0134f06e96
NEXUS_SALT                         = 0x0000000000000000000000000000000000000000d778ccb0fcb1a100ad59b1f4
NEXUSBOOTSTRAP_SALT                = 0x00000000000000000000000000000000000000007ddd91bf179d32003c6b22f9
NEXUS_ACCOUNT_FACTORY_SALT         = 0x0000000000000000000000000000000000000000cfbb4facaad7260297eca2fc
COMPOSABLE_EXECUTION_MODULE_SALT   = 0x000000000000000000000000000000000000000093ca75554c2a3c03ef8aebc4
COMPOSABLE_STORAGE_SALT            = 0x0000000000000000000000000000000000000000465fbd534a6e5803cde982a7
ETH_FORWARDER_SALT                 = 0x00000000000000000000000000000000000000002f5763a1f79af7033892e88a
NODE_PMF_SALT                      = 0x000000000000000000000000000000000000000043d5c4fb34feeb02c1d49524
DISPERSE_SALT                      = 0xfd73487f4e6544007a3ce4000000000000000000000000000000000000000000
```

Change them to get random testing addresses.

---

## Directory Structure

```
script/deploy/
├── deploy-stx.sh                    # Main deployment orchestrator
├── deploy-chain.sh                  # Per-chain deployment logic
├── config.toml                      # Chain configuration
├── DeployStxContracts.s.sol        # Solidity deployment script
├── build-artifacts.sh              # Artifact builder
├── README.md                       # This file
├── artifacts/                      # Contract artifacts
│   ├── K1MeeValidator/
│   │   ├── K1MeeValidator.json
│   │   └── verify.json
│   ├── Nexus/
│   │   ├── Nexus.json
│   │   └── verify.json
│   └── ...
├── deploy-logs/                    # Deployment logs
│   ├── validate-forks.log
│   ├── 00dry-run.log
│   ├── Base-84532-deploy.log
│   ├── Base-84532-deploy-errors.log
│   └── ...
└── util/                           # Utility contracts
    ├── CreateX.sol
    ├── DeterministicDeployerLib.sol
    ├── ValidateForks.s.sol
    └── createx-hex/                # CreateX deployment data
```

---

## Advanced Configuration

### Gas Price Configuration

For chains requiring specific gas prices, add to [config.toml](config.toml):

```toml
[<chain_id>.uint]
base_gas_price = 1              # in gwei
priority_gas_price = 1          # in gwei (optional)
```

**Example**: BNB Testnet

```toml
[97.uint]
chain_id = 97
base_gas_price = 1
priority_gas_price = 1
```

### Gas Estimation Multiplier

For chains with volatile gas estimation, add a multiplier:

```toml
[<chain_id>.uint]
gas_estimate_multiply = 101     # 101% (1% buffer)
```

**Example**: Scroll Mainnet

```toml
[534352.uint]
chain_id = 534352
gas_estimate_multiply = 101
```

### Disable Verification

To skip contract verification on a specific chain:

```toml
[<chain_id>.bool]
verify = false
```

### Add New Chain

To add a new chain to the deployment system:

1. **Add RPC URL to `.env`**:
   ```bash
   RPC_<chain_id>=https://your-rpc-url
   ```

2. **Add chain configuration to `config.toml`**:
   ```toml
   [<chain_id>]
   endpoint_url = "${RPC_<chain_id>}"

   [<chain_id>.bool]
   is_testnet = true/false
   verify = true/false

   [<chain_id>.uint]
   chain_id = <chain_id>

   [<chain_id>.string]
   name = "<Chain Name>"
   ```

3. **Deploy**:
   ```bash
   bash deploy-stx.sh <chain_id>
   ```

---

## Troubleshooting

### Common Issues

#### 1. RPC URL Validation Failed

**Error**: `Failed to create forks for the requested chains`

**Solution**:
- Check the `deploy-logs/validate-forks.log` and `deploy-logs/validate-forks-errors.log`
- Verify RPC URLs in `.env` are correct and accessible
- Check if RPC provider has rate limits
- Ensure RPC URLs are properly formatted without trailing slashes

#### 2. Insufficient Funds

**Error**: `insufficient funds for gas * price + value`

**Solution**:
- Ensure deployer address has sufficient native tokens
- For testnets, use faucets to get test tokens
- For mainnets, fund the deployer address adequately

#### 3. Contract Already Deployed

**Behavior**: Script skips already-deployed contracts

**Solution**: This is expected behavior. The script is idempotent and will only deploy missing contracts.

#### 4. Verification Failed

**Warning**: `Stx contracts deployed successfully, but verification failed`

**Solution**:
- Verify API keys for block explorers are set (if required)
- Check if the block explorer supports verification
- Manual verification can be done using the generated `verify.json` files in `artifacts/`

#### 5. Gas Price Too Low

**Error**: `transaction underpriced` or `replacement transaction underpriced`

**Solution**: Add gas price configuration to [config.toml](config.toml):
```toml
[<chain_id>.uint]
base_gas_price = <higher_value>
priority_gas_price = <higher_value>
```

#### 6. CreateX Deployment Failed

**Warning**: `CreateX deployment failed. Disperse contract will not be deployed.`

**Solution**:
- This is non-critical; other contracts will still deploy
- CreateX requires significant gas; ensure sufficient balance
- The Disperse contract will be skipped if CreateX fails
Disperse contract is used to fund NodePaymaster instances generated by the NodePaymaster Factory.
If it is not present, instances can be funded manually.
So if CreateX/Disperse was not deployed, ignore it and contact Biconomy.

### Viewing Logs

All deployment logs are stored in `deploy-logs/`:

```bash
# View deployment log for a specific chain
cat deploy-logs/Base-84532-deploy.log

# View deployment errors
cat deploy-logs/Base-84532-deploy-errors.log

# View dry-run results
cat deploy-logs/00dry-run.log

# View fork validation
cat deploy-logs/validate-forks.log
```

`deploy-logs/build` directory contains `forge build` logs produced by the `build-artifacts.sh`
`deploy-logs/build` precalc directory contains logs for the part when the scripts identifies contracts that should be deployed on a given chain. If you're getting the `Failed to define contracts to deploy for chain X` error, check the logs in this folder.

### Manual Verification

If automatic verification fails, use the generated verification files (`verify.json`) and verify via explorers manually.

---

## Best Practices

### 1. Test on Testnets First
Always deploy to testnets before mainnet deployments:
```bash
bash deploy-stx.sh 84532 11155420 421614  # Test on Base, OP, Arbitrum testnets
```

### 2. Verify Expected Addresses
Carefully review the expected addresses shown during dry-run before confirming deployment.

### 3. Use Separate Deployer Keys
Use different private keys for testnets and mainnets for better security.

---

## Support & Contribution

### Getting Help
- Review logs in `deploy-logs/` directory
- Check [Foundry documentation](https://book.getfoundry.sh/)
- Open an issue in the repository

---

## Appendix

### CreateX Deployment Data

CreateX uses pre-signed transactions for deterministic deployment. The scripts automatically select the appropriate transaction based on gas estimates:

- **3M gas**: [signed_serialised_transaction_gaslimit_3000000_.json](util/createx-hex/signed_serialised_transaction_gaslimit_3000000_.json)
- **25M gas**: [signed_serialised_transaction_gaslimit_25000000_.json](util/createx-hex/signed_serialised_transaction_gaslimit_25000000_.json)
- **45M gas**: [signed_serialised_transaction_gaslimit_45000000_.json](util/createx-hex/signed_serialised_transaction_gaslimit_45000000_.json)

### EntryPoint Address

All contracts use the canonical ERC-4337 EntryPoint v0.7:
```
ENTRYPOINT_ADDRESS = 0x0000000071727De22E5E9d8BAf0edAc6f37da032
```

---

**Last Updated**: 2025-11-20
