// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script, console} from "forge-std/Script.sol";
import {CCNFT} from "../src/CCNFT.sol";

contract DeployCCNFT is Script {
    function run() external returns (CCNFT) {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);
        CCNFT ccnft = new CCNFT();
        vm.stopBroadcast();
        console.log("CCNFT desplegado en:", address(ccnft));
        return ccnft;
    }
}
