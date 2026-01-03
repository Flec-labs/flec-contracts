// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Script.sol";
import "../src/FLECHub.sol";

contract DeployFLECHub is Script {
    function run() external {
        // Ambil private key dari .env
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);

        // Alamat yang akan menjadi Owner awal kontrak (biasanya alamatmu sendiri)
        address initialOwner = vm.addr(deployerPrivateKey);
        address allowedToken = vm.envAddress("ALLOWED_TOKEN");

        // Deploy FLECHub
        FLECHub hub = new FLECHub(initialOwner, allowedToken);

        console.log("FLECHub deployed at:", address(hub));

        vm.stopBroadcast();
    }
}
