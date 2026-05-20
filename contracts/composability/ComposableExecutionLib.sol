// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { ComposableStorage } from "./ComposableStorage.sol";
import {
    InputParam,
    OutputParam,
    Constraint,
    ConstraintType,
    InputParamType,
    InputParamFetcherType,
    OutputParamFetcherType
} from "../types/ComposabilityDataTypes.sol";
import { Execution } from "erc7579/interfaces/IERC7579Account.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Library for composable execution handling
library ComposableExecutionLib {
    error ConstraintNotMet(ConstraintType constraintType);
    error Output_StaticCallFailed();
    error InvalidParameterEncoding(string message);
    error InvalidOutputParamFetcherType();
    error ComposableExecutionFailed();
    error InvalidConstraintType();
    error InvalidSetOfInputParams(string message);
    error EmptyOrSubConstraints();
    error InvalidConstraintRange();
    error InvalidReferenceDataLength();
    error InsufficientRawValue();

    // Process the input parameters and return the composed calldata
    function processInputs(
        InputParam[] calldata inputParams,
        bytes4 functionSig
    )
        internal
        view
        returns (Execution memory)
    {
        address composedTarget;
        uint256 composedValue;
        bytes memory composedCalldata = abi.encodePacked(functionSig);
        uint256 length = inputParams.length;

        // Bit 0: TARGET param type set, Bit 1: VALUE param type set
        uint256 paramTypeFlags = 0;
        for (uint256 i; i < length; i++) {
            bytes memory processedInput = processInput(inputParams[i]);
            if (inputParams[i].paramType == InputParamType.TARGET) {
                if (inputParams[i].fetcherType == InputParamFetcherType.BALANCE) {
                    revert InvalidParameterEncoding("BALANCE fetcher type is not supported for TARGET param type");
                }
                // Check if TARGET has already been set (bit 0)
                if (paramTypeFlags & 1 != 0) {
                    revert InvalidSetOfInputParams("TARGET param type can only be set once");
                }
                paramTypeFlags |= 1; // Set bit 0
                composedTarget = abi.decode(processedInput, (address));
            } else if (inputParams[i].paramType == InputParamType.VALUE) {
                // Check if VALUE has already been set (bit 1)
                if (paramTypeFlags & 2 != 0) {
                    revert InvalidSetOfInputParams("VALUE param type can only be set once");
                }
                paramTypeFlags |= 2; // Set bit 1
                composedValue = abi.decode(processedInput, (uint256));
            } else if (inputParams[i].paramType == InputParamType.CALL_DATA) {
                composedCalldata = bytes.concat(composedCalldata, processedInput);
            } else {
                revert InvalidParameterEncoding("Invalid param type");
            }
        }
        // if a param with TARGET type was not provided, it will be address(0)
        // we don't restrict it since some calls may want to call address(0)
        // if a param with VALUE type was not provided, it will be 0
        // this is even more often case, as many calls happen with 0 value
        return Execution({ target: composedTarget, value: composedValue, callData: composedCalldata });
    }

    // Process a single input parameter and return the composed calldata
    function processInput(InputParam calldata param) internal view returns (bytes memory) {
        if (param.fetcherType == InputParamFetcherType.RAW_BYTES) {
            _validateConstraints(param.paramData, param.constraints);
            return param.paramData;
        } else if (param.fetcherType == InputParamFetcherType.STATIC_CALL) {
            address contractAddr;
            bytes calldata callData;
            bytes calldata paramData = param.paramData;
            // expect paramData to be abi.encode(address contractAddr, bytes callData)
            assembly {
                contractAddr := calldataload(paramData.offset)
                let s := calldataload(add(paramData.offset, 0x20))
                let u := add(paramData.offset, s)
                callData.offset := add(u, 0x20)
                callData.length := calldataload(u)
            }
            (bool success, bytes memory returnData) = contractAddr.staticcall(callData);
            if (!success) {
                revert ComposableExecutionFailed();
            }
            _validateConstraints(returnData, param.constraints);
            return returnData;
        } else if (param.fetcherType == InputParamFetcherType.BALANCE) {
            // Balance is exactly one 32-byte word by construction; more than one constraint
            // would index past the encoded value and is rejected up front.
            if (param.constraints.length > 1) revert InvalidSetOfInputParams("BALANCE supports at most 1 constraint");
            address tokenAddr;
            address account;
            bytes calldata paramData = param.paramData;

            // expect paramData to be abi.encodePacked(address token, address account)
            // Validate exact length requirement
            require(paramData.length == 40, InvalidParameterEncoding("Invalid paramData length"));
            assembly {
                tokenAddr := shr(96, calldataload(paramData.offset))
                account := shr(96, calldataload(add(paramData.offset, 0x14)))
            }

            uint256 balance;
            if (tokenAddr == address(0)) {
                balance = account.balance;
            } else {
                balance = IERC20(tokenAddr).balanceOf(account);
            }
            _validateConstraints(abi.encode(balance), param.constraints);
            return abi.encode(balance);
        } else {
            revert InvalidParameterEncoding("Invalid param fetcher type");
        }
    }

    // Process the output parameters
    function processOutputs(OutputParam[] calldata outputParams, bytes memory returnData, address account) internal {
        uint256 length = outputParams.length;
        for (uint256 i; i < length; i++) {
            processOutput(outputParams[i], returnData, account);
        }
    }

    // Process a single output parameter and write to storage
    function processOutput(OutputParam calldata param, bytes memory returnData, address account) internal {
        // only static types are supported for now as return values
        // can also process all the static return values which are before the first dynamic return value in the
        // returnData
        if (param.fetcherType == OutputParamFetcherType.EXEC_RESULT) {
            uint256 returnValues;
            address targetStorageContract;
            bytes32 targetStorageSlot;
            bytes calldata paramData = param.paramData;
            assembly {
                returnValues := calldataload(paramData.offset)
                targetStorageContract := calldataload(add(paramData.offset, 0x20))
                targetStorageSlot := calldataload(add(paramData.offset, 0x40))
            }
            _parseReturnDataAndWriteToStorage(
                returnValues, returnData, targetStorageContract, targetStorageSlot, account
            );
            // same for static calls
        } else if (param.fetcherType == OutputParamFetcherType.STATIC_CALL) {
            uint256 returnValues;
            address sourceContract;
            bytes calldata sourceCallData;
            address targetStorageContract;
            bytes32 targetStorageSlot;
            bytes calldata paramData = param.paramData;
            assembly {
                returnValues := calldataload(paramData.offset)
                sourceContract := calldataload(add(paramData.offset, 0x20))
                let s := calldataload(add(paramData.offset, 0x40))
                let u := add(paramData.offset, s)
                sourceCallData.offset := add(u, 0x20)
                sourceCallData.length := calldataload(u)
                targetStorageContract := calldataload(add(paramData.offset, 0x60))
                targetStorageSlot := calldataload(add(paramData.offset, 0x80))
            }
            (bool outputSuccess, bytes memory outputReturnData) = sourceContract.staticcall(sourceCallData);
            if (!outputSuccess) {
                revert Output_StaticCallFailed();
            }
            _parseReturnDataAndWriteToStorage(
                returnValues, outputReturnData, targetStorageContract, targetStorageSlot, account
            );
        } else {
            revert InvalidOutputParamFetcherType();
        }
    }

    /// @dev Validate the constraints => compare each 32-byte word of rawValue against constraints[i].
    /// Each constraints[i] is checked against the i-th 32-byte word of rawValue (AND semantics across
    /// the array). Use ConstraintType.OR to express OR semantics within a single word position.
    ///
    /// AND vs OR encoding:
    /// - AND is implicit across the top-level `Constraint[]`. Every non-OR entry has a static
    ///   32-byte reference (EQ/GTE/LTE/GTE_SIGNED/LTE_SIGNED) or a fixed 64-byte (lower, upper)
    ///   payload (IN) — predictable layout, predictable gas.
    /// - OR is a single entry whose `referenceData` is a dynamic `abi.encode(Constraint[])`. It is
    ///   decoded once here and evaluated against the *same* 32-byte word as the outer entry. The
    ///   sub-constraints inside the OR must be leaf constraints only — nesting OR inside OR is
    ///   intentionally rejected (see `_checkConstraint`) to keep what the user signs flat and
    ///   easy to display.
    function _validateConstraints(bytes memory rawValue, Constraint[] calldata constraints) private pure {
        uint256 len = constraints.length;
        // Without this, the assembly mload below reads past rawValue's payload into adjacent
        // memory (the freshly-allocated Constraint struct's constraintType word), so empty
        // staticcall returndata or BALANCE encoded as a single word could silently satisfy
        // zero-threshold predicates like GTE(0) or GTE_SIGNED(0).
        if (rawValue.length < len * 32) revert InsufficientRawValue();
        for (uint256 i; i < len;) {
            Constraint memory c = constraints[i];
            bytes32 value;
            assembly {
                value := mload(add(rawValue, add(0x20, mul(i, 0x20))))
            }
            if (c.constraintType == ConstraintType.OR) {
                Constraint[] memory subs = abi.decode(c.referenceData, (Constraint[]));
                uint256 subsLen = subs.length;
                if (subsLen == 0) revert EmptyOrSubConstraints();
                // Structural pre-pass: reject nested OR before evaluating any sub. Without this,
                // rejection would depend on whether an earlier leaf happens to match, which makes
                // "what you sign" off-chain rendering inconsistent with on-chain behavior.
                for (uint256 j; j < subsLen;) {
                    if (subs[j].constraintType == ConstraintType.OR) revert InvalidConstraintType();
                    unchecked {
                        ++j;
                    }
                }
                bool anyMet;
                for (uint256 j; j < subsLen;) {
                    if (_checkConstraint(value, subs[j])) {
                        anyMet = true;
                        break;
                    }
                    unchecked {
                        ++j;
                    }
                }
                if (!anyMet) revert ConstraintNotMet(c.constraintType);
            } else {
                if (!_checkConstraint(value, c)) revert ConstraintNotMet(c.constraintType);
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @dev Returns true if value satisfies constraint c. OR is rejected here: nested OR is not
    /// supported, so only leaf constraints may appear inside an OR's sub-array. SKIP unconditionally
    /// returns true and exists so signers can ignore a specific 32-byte field while still validating
    /// later fields at their fixed positions, without padding with dummy always-true predicates.
    ///
    /// Leaf branches (EQ, GTE, LTE, GTE_SIGNED, LTE_SIGNED) require referenceData to be exactly
    /// 32 bytes — `bytes32(bytes)` left-aligns and zero-pads on shorter input, so an enforcement
    /// is needed to avoid silently miscomparing non-canonical encodings (e.g. abi.encodePacked).
    // solhint-disable-next-line code-complexity
    function _checkConstraint(bytes32 value, Constraint memory c) private pure returns (bool) {
        ConstraintType ct = c.constraintType;
        if (ct == ConstraintType.EQ) {
            if (c.referenceData.length != 32) revert InvalidReferenceDataLength();
            return value == bytes32(c.referenceData);
        } else if (ct == ConstraintType.GTE) {
            if (c.referenceData.length != 32) revert InvalidReferenceDataLength();
            return value >= bytes32(c.referenceData);
        } else if (ct == ConstraintType.LTE) {
            if (c.referenceData.length != 32) revert InvalidReferenceDataLength();
            return value <= bytes32(c.referenceData);
        } else if (ct == ConstraintType.IN) {
            (bytes32 lower, bytes32 upper) = abi.decode(c.referenceData, (bytes32, bytes32));
            // Bounds are compared unsigned. Reject lower > upper so:
            //   - same-sign signed ranges written in descending order revert instead of accepting nothing,
            //   - mixed-sign ranges like IN(-10, 10) revert (negative encodes to a huge unsigned) instead
            //     of being unsatisfiable,
            //   - reversed bounds like IN(10, -10) revert instead of silently widening to "magnitude >= 10".
            if (lower > upper) revert InvalidConstraintRange();
            return value >= lower && value <= upper;
        } else if (ct == ConstraintType.GTE_SIGNED) {
            // Reinterprets value as int256: any 32-byte word with the high bit set becomes
            // negative under two's complement. Callers must only use GTE_SIGNED / LTE_SIGNED
            // when the resolved value (RAW_BYTES input or STATIC_CALL return) lives in the
            // signed int256 domain — for values that may exceed 2**255 - 1, use unsigned GTE.
            if (c.referenceData.length != 32) revert InvalidReferenceDataLength();
            return int256(uint256(value)) >= int256(uint256(bytes32(c.referenceData)));
        } else if (ct == ConstraintType.LTE_SIGNED) {
            // See GTE_SIGNED above: signed-domain only.
            if (c.referenceData.length != 32) revert InvalidReferenceDataLength();
            return int256(uint256(value)) <= int256(uint256(bytes32(c.referenceData)));
        } else if (ct == ConstraintType.SKIP) {
            return true;
        } else {
            revert InvalidConstraintType();
        }
    }

    /// @dev Parse the return data and write to the appropriate storage contract
    function _parseReturnDataAndWriteToStorage(
        uint256 returnValues,
        bytes memory returnData,
        address targetStorageContract,
        bytes32 targetStorageSlot,
        address account
    )
        internal
    {
        for (uint256 i; i < returnValues; i++) {
            bytes32 value;
            assembly {
                value := mload(add(returnData, add(0x20, mul(i, 0x20))))
            }
            ComposableStorage(targetStorageContract)
                .writeStorage({
                    slot: keccak256(abi.encodePacked(targetStorageSlot, i)), value: value, account: account
                });
        }
    }
}
