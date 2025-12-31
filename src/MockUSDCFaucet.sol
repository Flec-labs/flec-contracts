// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MockUSDC} from "./MockUSDC.sol";

contract MockUSDCFaucet is Ownable {
    MockUSDC public immutable token;

    uint256 public dripAmount;     // contoh: 1_000e6 = 1,000 USDC
    uint48  public cooldown;       // contoh: 24 hours
    uint256 public maxBalance;     // contoh: 10_000e6 (anti-hoarding)

    bool public allowlistEnabled;
    mapping(address => bool) public allowlist;
    mapping(address => uint256) public lastDripAt;

    event Dripped(address indexed user, uint256 amount);
    event FaucetConfig(uint256 dripAmount, uint48 cooldown, uint256 maxBalance, bool allowlistEnabled);

    constructor(
        address initialOwner,
        MockUSDC _token,
        uint256 _dripAmount,
        uint48 _cooldown,
        uint256 _maxBalance
    ) Ownable(initialOwner) {
        require(address(_token) != address(0), "token=0");
        token = _token;
        dripAmount = _dripAmount;
        cooldown = _cooldown;
        maxBalance = _maxBalance;
        emit FaucetConfig(_dripAmount, _cooldown, _maxBalance, false);
    }

    function drip() external {
        if (allowlistEnabled) require(allowlist[msg.sender], "not allowlisted");

        uint256 last = lastDripAt[msg.sender];
        require(block.timestamp >= last + cooldown, "cooldown");

        if (maxBalance > 0) {
            require(token.balanceOf(msg.sender) < maxBalance, "balance too high");
        }

        lastDripAt[msg.sender] = block.timestamp;
        token.mint(msg.sender, dripAmount);
        emit Dripped(msg.sender, dripAmount);
    }

    // --- Admin controls ---
    function setConfig(uint256 _dripAmount, uint48 _cooldown, uint256 _maxBalance, bool _allowlistEnabled)
        external
        onlyOwner
    {
        dripAmount = _dripAmount;
        cooldown = _cooldown;
        maxBalance = _maxBalance;
        allowlistEnabled = _allowlistEnabled;
        emit FaucetConfig(_dripAmount, _cooldown, _maxBalance, _allowlistEnabled);
    }

    function setAllowlist(address user, bool allowed) external onlyOwner {
        allowlist[user] = allowed;
    }

    function batchAllowlist(address[] calldata users, bool allowed) external onlyOwner {
        for (uint256 i = 0; i < users.length; i++) {
            allowlist[users[i]] = allowed;
        }
    }
}
