// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {EventChain} from "../src/EventChain.sol";

contract EventChainScript is Script {
    EventChain public eventChain;

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        eventChain = new EventChain();
        
        console.log("EventChain deployed at:", address(eventChain));

        vm.stopBroadcast();
    }
}