// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/MockUSDC.sol";

contract DeployMockUSDC is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address myAddress = 0x991863C43Aa5555BF15666C363B1Ff70e75Fcee8;

        vm.startBroadcast(deployerPrivateKey);

        // Deploy MockUSDC: recipient & initialOwner diisi alamat kamu
        MockUSDC usdc = new MockUSDC(myAddress, myAddress);
        
        console.log("MockUSDC deployed at:", address(usdc));

        vm.stopBroadcast();
    }
}