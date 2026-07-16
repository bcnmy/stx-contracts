// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";

interface IEntryPointDeposit {
    function depositTo(address account) external payable;
    function balanceOf(address account) external view returns (uint256);
}

/// Emergency top-up of the Chiliz node paymaster EntryPoint deposits (first used for
/// the 2026-07-12 AA31 incident; no auto-refill exists in mee-node, refills are manual).
/// Splits the deployer's CHZ balance evenly between both node paymasters, keeping
/// GAS_BUFFER for future deploy gas. Refuses to run if the split would be dust.
contract RefillChilizPaymasters is Script {
    IEntryPointDeposit constant EP = IEntryPointDeposit(0x0000000071727De22E5E9d8BAf0edAc6f37da032);
    address constant PM_NODE0 = 0x130Ed027b1CDF13977D125f7B6bAB45ea2Aa17CE;
    address constant PM_NODE1 = 0x3F801481fd20E5fb00df349AFD49B9e2085FD948;
    uint256 constant GAS_BUFFER = 10 ether;
    uint256 constant MIN_DEPOSIT_EACH = 50 ether;

    function run() external {
        uint256 pk;
        try vm.envUint("MAINNET_PRIVATE_KEY") returns (uint256 v) {
            pk = v;
        } catch {
            pk = uint256(vm.envBytes32("MAINNET_PRIVATE_KEY"));
        }

        address deployer = vm.addr(pk);
        require(deployer.balance > GAS_BUFFER, "balance below gas buffer");
        uint256 each = (deployer.balance - GAS_BUFFER) / 2;
        require(each >= MIN_DEPOSIT_EACH, "split would be dust; bridge more first");
        console2.log("depositing to each paymaster:", each);

        vm.startBroadcast(pk);
        EP.depositTo{ value: each }(PM_NODE0);
        EP.depositTo{ value: each }(PM_NODE1);
        vm.stopBroadcast();

        console2.log("node-0 paymaster deposit:", EP.balanceOf(PM_NODE0));
        console2.log("node-1 paymaster deposit:", EP.balanceOf(PM_NODE1));
    }
}
