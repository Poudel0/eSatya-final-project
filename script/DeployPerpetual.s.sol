// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.20;

// import {Script} from "forge-std/Script.sol";
// import {perp} from "../src/Perpetual/perpetual.sol";
// import {HelperConfig} from "./HelperConfig.s.sol";

// contract DeployPerpetual is Script{

//     address eNRSAddress;


//     function run() external returns (perp,HelperConfig){
//         HelperConfig helperConfig = new HelperConfig();
//         (, address wbtcPriceFeed, , address wbtc, uint256 deployerKey) = helperConfig.activeNetworkConfig();

       
//         vm.startBroadcast(deployerKey);
//         perp perpetual = new perp(eNRSAddress,wbtcPriceFeed);
        
//         vm.stopBroadcast();
//         return(perpetual,helperConfig);
//     }
    
// }
