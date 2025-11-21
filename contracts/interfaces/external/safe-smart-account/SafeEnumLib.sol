// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.27;

/**
 * @title Enum
 * @notice Collection of enums used in Safe Smart Account contracts.
 * @author @safe-global/safe-protocol
 */
library SafeEnumLib {
    /**
     * @notice A Safe transaction operation.
     * @custom:variant Call The Safe transaction is executed with the `CALL` opcode.
     * @custom:variant Delegatecall The Safe transaction is executed with the `DELEGATECALL` opcode.
     */
    enum Operation {
        Call,
        DelegateCall
    }
}
