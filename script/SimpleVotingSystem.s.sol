// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {SimpleVotingSystem} from "../src/SimpleVotingSystem.sol";

contract DeployVotingSystem is Script {
    SimpleVotingSystem public votingSystem;

    function run() public {
        vm.startBroadcast(); // utilise la 1ère clé d'Anvil

        votingSystem = new SimpleVotingSystem();

        vm.stopBroadcast();
    }
}
