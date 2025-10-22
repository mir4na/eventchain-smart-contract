// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {EventChain} from "../src/EventChain.sol";

contract EventChainScript is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        EventChain eventChain = new EventChain();

        address platformWallet = vm.envOr("PLATFORM_WALLET", address(0));
        if (platformWallet != address(0)) {
            eventChain.setPlatformWallet(platformWallet);
        }

        address initialAdmin = vm.envOr("INITIAL_ADMIN", address(0));
        if (initialAdmin != address(0) && initialAdmin != deployer) {
            eventChain.addAdmin(initialAdmin);
        }

        vm.stopBroadcast();
    }
}