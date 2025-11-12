# Stx Contracts

**Smart Contracts in Solidity which serve as a core layer for Biconomy Modular Execution Environment (MEE) stack and unlock seamless cross-chain orchestration via SuperTransactions (Stx)**

## Documentation

- [Orchestration](https://docs.biconomy.io/new/learn-about-biconomy/understanding-composable-orchestration) in Biconomy Docs
- [Fusion research article](https://ethresear.ch/t/fusion-module-7702-alternative-with-no-protocol-changes/20949)

## Repo Contents
This repo contains all the contracts that have previously been divided into three different repositories.
- https://github.com/bcnmy/nexus 
- https://github.com/bcnmy/mee-contracts
- https://github.com/bcnmy/composability

Since all of the above contracts follow the same purpose of unlocking Supertransactions (stx), they are now united within the same repository.

Thus, the repo contains the contracts that implement the following important entities:

### MEE K1 Validator
ERC-7579 Validator module that validates SuperTransactions.
A SuperTransaction is an array or Merkle tree of entries, such as UserOps or ERC-712 data structures (cross-chain intents, off-chain orders, etc.).
#### Modes
The K1 MEE Validator supports four distinct validation modes to accommodate different user flows: 
- **Simple Mode:** User signs the EIP-712 Hash of a SuperTx data struct.
- **On-Chain Transaction Mode:** Fusion mode, where the user signs a standard Ethereum transaction that funds the orchestrator Smart Account and contains the Stx hash, thus the Stx entries are also signed with just one signature.
- **ERC-2612 Permit Mode:** Fusion mode that combines token approvals with SuperTx authorization in a single signature. In this and the above (on-chain) mode, the Stx is a Merkle tree of entries.
- **Non-MEE Fallback Mode:** For backwards compatibility with standard ERC-4337 UserOperations.

This flexibility allows users to interact with smart accounts using familiar EOA wallets while unlocking advanced batching and cross-chain orchestration capabilities. 

#### SuperTransaction Architecture 
At the core of the validator's design is support for SuperTransactions (Stx, SuperTx) - structured batches of operations that can include UserOps, ERC-712 messages, cross-chain intents, and off-chain orders. 
Each operation within a SuperTx includes temporal constraints (lowerBoundTimestamp, upperBoundTimestamp) for scheduled execution windows. 

This architecture enables users to sign once and authorize complex multi-step, potentially cross-chain workflows while maintaining cryptographic proof that each executed operation was part of the original batch. 

#### Modular Account Integration & Security 
Built as a singleton contract shared across all smart accounts, the K1 MEE Validator implements multiple standards including ERC-7579 (modular accounts), ERC-7780 (stateless validation), ERC-7739 (nested typed data signing), and ERC-1271 (contract signature verification). Each smart account installs the validator module and configures its own EOA owner, with ownership restricted to externally owned accounts (including EIP-7702 delegated EOAs).

### Composability contracts

**Smart contracts to unlock composable execution.**
The composability stack allows developers to create dynamic, multi-step transactions entirely from frontend code by injecting values into the calldata at runtime.
[More details on Runtime Parameters injection](https://docs.biconomy.io/new/getting-started/understanding-runtime-injection).

The smart contracts in this repo handle the composable execution logic, allowing developers to avoid any on-chain development and just use the SDK to build composable operations.

#### Features: 
-   **Single-chain composability**: Use outputs of one action as inputs for another.
For example, `swap()` method returns the amount of tokens received as a result of a swap. 
This exact amount can be used as input for `approve()` method to allow a `stake()` method to execute.
-   **Static types handling**: Inject any static types into the abi.encoded function call.
-   **Several return values handling**: If function returns multiple values, you can use any amount of them as input for another function.
-   **Constraints handling**: Validate any constraints on the input parameters.

#### Contracts included:
-   **Composable Execution Module**: ERC-7579 module that allows Smart Accounts to execute composable transactions without changing the account implementation.
-   **Composable Execution Base**: Base contract that Smart Accounts can inherit from to enable composable execution natively.
-   **Composable Execution Lib**: Library that provides methods to process input and output parameters of a composable execution.

#### On storage slots for ComposableExecutionModule
As can be seen in the Storage.sol file, the actual storage slot used depends on both the `account` address and the `caller` 
address.

Thus, if the ComposableExecutionModule is used via 'call' flows (as a Fallback and/or Executor module), the storage slot is different compared to the case when the module is used via 'delegatecall' flow.

It is however recommended that the smart account is consistent in terms of which flow - `call` or `delegatecall` - it uses.

### Nexus Smart Account

#### Standards Compliance & Ecosystem Integration

Nexus is a fully compliant ERC-7579 modular smart account supporting a comprehensive suite of standards:

- **[ERC-4337](https://eips.ethereum.org/EIPS/eip-4337)** - Account Abstraction v0.7
- **[ERC-7579](https://eips.ethereum.org/EIPS/eip-7579)** - Modular Smart Accounts
- **[ERC-1271](https://eips.ethereum.org/EIPS/eip-1271)** - Contract Signature Validation
- **[ERC-2771](https://eips.ethereum.org/EIPS/eip-2771)** - Meta-Transactions
- **[ERC-7739](https://eips.ethereum.org/EIPS/eip-7739)** - Nested Typed Data Signing
- **[ERC-7201](https://eips.ethereum.org/EIPS/eip-7201)** - Namespaced Storage
- **[ERC-1967](https://eips.ethereum.org/EIPS/eip-1967)** - UUPS Upgradeable Proxy
- **[ERC-7702](https://eips.ethereum.org/EIPS/eip-7702)** - Native Delegated EOA Support
- **[ERC-721](https://eips.ethereum.org/EIPS/eip-721)** - NFT Receiver
- **[ERC-1155](https://eips.ethereum.org/EIPS/eip-1155)** - Multi-Token Receiver

This extensive standards support ensures Nexus works seamlessly across the entire Ethereum ecosystem, from DeFi protocols and NFT marketplaces to account abstraction infrastructure and the latest EIP-7702 innovations for EOA enhancement.

#### Innovative Features: PREP, Module Enable Mode & Composability

Nexus introduces groundbreaking features that set it apart from traditional smart accounts. **PREP Mode** (Provably Rootless EIP-7702 Proxy) enables rootless proxy initialization using cryptographic validation, allowing ERC-7702 accounts to bootstrap without traditional proxy overhead. **Module Enable Mode** permits installing validator modules during UserOp validation itself, dramatically reducing onboarding friction by allowing a module to validate its own installation. The **Composable Execution System** provides runtime parameter injection, enabling outputs from one call to feed as inputs to another with constraint validation (equality, range checks), perfect for complex DeFi workflows. Additional innovations include a **tri-modal nonce system** that encodes validation mode and validator address directly in the nonce for gas efficiency, **pre-validation hooks** that can modify hashes/signatures before validation (enabling session keys and spending limits), and an **emergency hook uninstall mechanism** with a 1-day timelock safeguard against malicious modules.

#### Gas Optimization & Architectural Excellence

Nexus is engineered for exceptional gas efficiency through multiple optimization techniques. It uses **transient storage** (EIP-1153 tstore/tload) for initialization flags, eliminating persistent storage costs. Critical execution paths leverage **assembly-optimized operations** with memory-safe annotations for compiler optimization, including specialized versions that skip return data when unnecessary. The storage layout employs **ERC-7201 namespaced storage** with packed data structures—validators and executors use gas-efficient **SentinelList** linked lists for O(1) contains checks, while the single-hook design avoids mapping overhead. The architecture implements a **default validator pattern** where an immutable validator is always available without storage lookups, and **minimal SLOAD operations** with early returns in validation flows. Batch execution includes optimized paths for operations that don't require return values, and the **module fallback system** handles ERC token receivers natively without requiring module installations, saving gas on common operations.

### Node Paymaster and Node Paymaster Factory
Utility smart contracts for MEE Nodes.
Node Paymaster allows MEE Nodes to pay for UserOps that are part of the Stx executed by the nodes.
#### Economic Model & Gas Sponsorship
The Node Paymaster implements a sophisticated economic model that ensures MEE Nodes can profitably sponsor gas fees while maintaining fairness for all participants. It supports flexible refund mechanisms where gas sponsors (users or dApps) pre-pay an estimated maximum gas cost plus a premium, and then receive refunds for unused gas after execution. The system offers two premium models: percentage-based and fixed-amount premiums. This design allows nodes to earn sustainable revenue for their infrastructure services while keeping gas costs predictable and competitive for end users. 
#### Architecture & Access Control
Built on the ERC-4337 account abstraction standard, the Node Paymaster uses a factory deployment pattern with CREATE2 for deterministic, counterfactual addresses. Each MEE Node deploys its own NodePaymaster instance through the NodePaymasterFactory, which can automatically fund the paymaster's deposit at the EntryPoint during creation. The paymaster implements strict access control via tx.origin checks, restricting UserOp sponsorship to the node owner's master EOA and whitelisted worker EOAs. This intentional design makes it incompatible with public ERC-4337 mempools but optimized for MEE's private node infrastructure, where proven nodes operate within a trusted network with slashing mechanisms for malicious behavior.

## Security Audits
The Stx contracts suite is carefully audited by lead researchers in blockchain security.
Please explore the `/audit/` folder to find the reports.

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ pnpm test
```