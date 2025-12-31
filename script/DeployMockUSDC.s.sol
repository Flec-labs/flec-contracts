// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {MockUSDC} from "../src/MockUSDC.sol";
import {MockUSDCFaucet} from "../src/MockUSDCFaucet.sol";

contract DeployMockUSDC is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        // Default config (bisa kamu ubah)
        uint256 dripAmount = 10_000e6;      // 10,000 mUSDC
        uint48 cooldown = 24 hours;
        uint256 maxBalance = 100_000e6;     // max 100,000 mUSDC di wallet

        vm.startBroadcast(pk);

        MockUSDC usdc = new MockUSDC(deployer);
        MockUSDCFaucet faucet = new MockUSDCFaucet(deployer, usdc, dripAmount, cooldown, maxBalance);

        // Faucet jadi minter
        usdc.grantRole(usdc.MINTER_ROLE(), address(faucet));

        console2.log("MockUSDC:", address(usdc));
        console2.log("Faucet  :", address(faucet));

        vm.stopBroadcast();
    }
}
