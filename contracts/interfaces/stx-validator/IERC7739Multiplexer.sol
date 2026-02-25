// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.27;

/**
 * @title IERC7739Multiplexer
 * @notice Interface for the ERC7739Multiplexer module
 * @dev This module is responsible for multiplexing the ERC7739 validation
 */
interface IERC7739Multiplexer {
    function getErc7739HashAndSignature(
        address account,
        address sender,
        bytes32 hash,
        bytes calldata signature
    )
        external
        view
        returns (bytes32, bytes calldata);
}
