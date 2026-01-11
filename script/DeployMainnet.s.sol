// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ProgressiveStaking} from "../src/ProgressiveStaking.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title DeployMainnetScript
 * @notice Deployment script for mainnet (Ethereum) - uses existing token
 * @dev Usage: forge script script/DeployMainnet.s.sol --rpc-url $MAINNET_RPC_URL --broadcast --verify
 */
contract DeployMainnetScript is Script {
    // Tier rates in basis points: 0.5%, 0.7%, 2%, 4%, 5%, 6%
    uint256[6] public tierRates = [uint256(50), 70, 200, 400, 500, 600];

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address stakingToken = vm.envAddress("STAKING_TOKEN_ADDRESS");
        uint256 treasuryAmount = vm.envOr("TREASURY_AMOUNT", uint256(0));

        // Parse founder addresses
        address[] memory founders = _parseFounders();

        // Validation
        require(stakingToken != address(0), "STAKING_TOKEN_ADDRESS not set");

        console.log("=== Mainnet Deployment (Ethereum) ===");
        console.log("Deployer:", deployer);
        console.log("Staking Token:", stakingToken);

        // Check deployer token balance if treasury deposit is planned
        if (treasuryAmount > 0) {
            uint256 balance = IERC20(stakingToken).balanceOf(deployer);
            require(balance >= treasuryAmount, "Insufficient token balance for treasury");
            console.log("Deployer token balance:", balance / 1 ether);
            console.log("Treasury to deposit:", treasuryAmount / 1 ether);
        }

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy staking contract
        ProgressiveStaking staking = new ProgressiveStaking(
            deployer,
            stakingToken,
            founders,
            tierRates
        );
        console.log("ProgressiveStaking deployed at:", address(staking));

        // 2. Optionally deposit treasury
        if (treasuryAmount > 0) {
            IERC20(stakingToken).approve(address(staking), treasuryAmount);
            staking.depositTreasury(treasuryAmount);
            console.log("Treasury deposited:", treasuryAmount / 1 ether, "tokens");
        } else {
            console.log("Treasury deposit skipped (TREASURY_AMOUNT not set)");
            console.log("Remember to deposit treasury manually before users can claim rewards!");
        }

        vm.stopBroadcast();

        // Summary
        console.log("");
        console.log("=== Deployment Summary ===");
        console.log("Token:", stakingToken);
        console.log("Staking:", address(staking));
        console.log("Owner:", deployer);
        console.log("Founders:", founders.length);
        console.log("");
        console.log("Tier rates (basis points):");
        console.log("  Tier 1 (0-180 days):", tierRates[0], "= 0.5%");
        console.log("  Tier 2 (180-360 days):", tierRates[1], "= 0.7%");
        console.log("  Tier 3 (360-720 days):", tierRates[2], "= 2%");
        console.log("  Tier 4 (720-1080 days):", tierRates[3], "= 4%");
        console.log("  Tier 5 (1080-1440 days):", tierRates[4], "= 5%");
        console.log("  Tier 6 (1440+ days):", tierRates[5], "= 6%");
        console.log("");
        console.log("IMPORTANT: Verify contract on Etherscan!");
    }

    function _parseFounders() internal view returns (address[] memory) {
        string memory foundersEnv = vm.envOr("FOUNDER_ADDRESSES", string(""));
        if (bytes(foundersEnv).length == 0) {
            return new address[](0);
        }

        // Simple parsing for up to 10 founders
        address[] memory tempFounders = new address[](10);
        uint256 count = 0;

        bytes memory strBytes = bytes(foundersEnv);
        uint256 start = 0;

        for (uint256 i = 0; i <= strBytes.length; i++) {
            if (i == strBytes.length || strBytes[i] == ",") {
                if (i > start) {
                    bytes memory addrBytes = new bytes(i - start);
                    for (uint256 j = start; j < i; j++) {
                        addrBytes[j - start] = strBytes[j];
                    }
                    address founder = vm.parseAddress(string(addrBytes));
                    if (founder != address(0) && count < 10) {
                        tempFounders[count] = founder;
                        count++;
                    }
                }
                start = i + 1;
            }
        }

        address[] memory founders = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            founders[i] = tempFounders[i];
        }
        return founders;
    }
}
