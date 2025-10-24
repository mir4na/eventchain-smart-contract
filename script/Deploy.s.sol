// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {EventChain} from "../src/EventChain.sol";

contract DeployEventChain is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address platformWallet = vm.envAddress("PLATFORM_WALLET");
        address backendSigner = vm.envAddress("BACKEND_SIGNER");

        vm.startBroadcast(deployerPrivateKey);

        EventChain eventChain = new EventChain(platformWallet, backendSigner);

        vm.stopBroadcast();

        console.log("EventChain deployed to:", address(eventChain));
        console.log("Platform wallet:", platformWallet);
        console.log("Backend signer:", backendSigner);
        console.log("Owner:", vm.addr(deployerPrivateKey));
    }
}