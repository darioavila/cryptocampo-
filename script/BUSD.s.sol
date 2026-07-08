// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {BUSD} from "../src/BUSD.sol";

contract DeployBUSD is Script {
    function run() external returns (BUSD) {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);
        BUSD busd = new BUSD();
        vm.stopBroadcast();
        console.log("BUSD desplegado en:", address(busd));
        return busd;
    }
}
