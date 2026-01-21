pragma solidity ^0.8.0;
   
   import "forge-std/Script.sol";

   // Use this script while foundry bug is not yet fixed
   // https://github.com/foundry-rs/foundry/issues/11584
   
   contract DeployEpScript is Script {
       function run() external {
           // import calldata from .env file
           bytes memory data = vm.envBytes("EP_V07_DEPLOY_TX_DATA");
           address to = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
           
           vm.startBroadcast();
           (bool success,) = to.call(data);
           require(success, "call failed");
           vm.stopBroadcast();
       }
   }