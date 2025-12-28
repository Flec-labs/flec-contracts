// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/FLECHub.sol"; 

contract DeployHub is Script {
    function run() external {
        // Mengambil private key dari environment variable [.env]
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Alamat yang akan menjadi Owner kontrak 
        address initialOwner = vm.addr(deployerPrivateKey);

        // Memulai proses transaksi ke blockchain
        vm.startBroadcast(deployerPrivateKey);

        // Deploy FLECHub Monolithic 
        // Parameter constructor adalah alamat Initial Owner 
        FLECHub hub = new FLECHub(initialOwner);

        // Berhenti mengirim transaksi
        vm.stopBroadcast();

        // Log alamat kontrak hasil deploy untuk dicatat
        console.log("FLECHub deployed at:", address(hub));
    }
}