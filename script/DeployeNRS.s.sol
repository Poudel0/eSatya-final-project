// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {eNRS} from "../src/eNRS/eNRS.sol";
import {eNRS_Engine} from "../src/eNRS/eNRS_Engine.sol";
import { HelperConfig} from "./HelperConfig.s.sol";
import {perp} from "../src/Perpetual/perpetual.sol";

contract DeployeNRS is Script{

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (eNRS, eNRS_Engine,perp,HelperConfig){
        HelperConfig helperConfig = new HelperConfig();
        (address wethPriceFeed,,,, uint256 deployerKey) = helperConfig.activeNetworkConfig();

        // tokenAddresses = weth;
        // priceFeedAddresses = wethPriceFeed;
        vm.startBroadcast(deployerKey);
        eNRS enrs = new eNRS();
        eNRS_Engine engine = new eNRS_Engine(address(enrs),wethPriceFeed);
        
        enrs.transferOwnership(address(engine));

        // Deploy Perpetual Contract
        perp perpetual = new perp(address(enrs),wethPriceFeed);
        vm.stopBroadcast();
        return(enrs,engine,perpetual,helperConfig);
    }
    
}