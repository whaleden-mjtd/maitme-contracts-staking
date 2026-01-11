// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ProgressiveStaking} from "../src/ProgressiveStaking.sol";
import {ERC20Mock} from "../test/mocks/ERC20Mock.sol";

/**
 * @title DeployTestnetScript
 * @notice Deployment script for testnet (Sepolia) - deploys mock token + staking contract
 * @dev Usage: forge script script/DeployTestnet.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast --verify
 */
contract DeployTestnetScript is Script {
    // Tier rates in basis points: 0.5%, 0.7%, 2%, 4%, 5%, 6%
    uint256[6] public tierRates = [uint256(50), 70, 200, 400, 500, 600];

    // Initial token supply for testing (100M tokens)
    uint256 public constant INITIAL_SUPPLY = 100_000_000 ether;

    // Treasury amount to deposit (10M tokens)
    uint256 public constant TREASURY_AMOUNT = 10_000_000 ether;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Parse founder addresses
        address[] memory founders = _parseFounders();

        console.log("=== Testnet Deployment (Sepolia) ===");
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy mock ERC20 token
        ERC20Mock token = new ERC20Mock("MAIT Token", "MAIT");
        console.log("Mock Token deployed at:", address(token));

        // 2. Mint initial supply to deployer
        token.mint(deployer, INITIAL_SUPPLY);
        console.log("Minted", INITIAL_SUPPLY / 1 ether, "tokens to deployer");

        // 3. Deploy staking contract
        ProgressiveStaking staking = new ProgressiveStaking(
            deployer,
            address(token),
            founders,
            tierRates
        );
        console.log("ProgressiveStaking deployed at:", address(staking));

        // 4. Approve and deposit treasury
        token.approve(address(staking), TREASURY_AMOUNT);
        staking.depositTreasury(TREASURY_AMOUNT);
        console.log("Treasury deposited:", TREASURY_AMOUNT / 1 ether, "tokens");

        vm.stopBroadcast();

        // Summary
        console.log("");
        console.log("=== Deployment Summary ===");
        console.log("Token:", address(token));
        console.log("Staking:", address(staking));
        console.log("Owner:", deployer);
        console.log("Founders:", founders.length);
        console.log("Treasury:", TREASURY_AMOUNT / 1 ether, "tokens");
        console.log("");
        console.log("Tier rates (basis points):");
        console.log("  Tier 1 (0-180 days):", tierRates[0], "= 0.5%");
        console.log("  Tier 2 (180-360 days):", tierRates[1], "= 0.7%");
        console.log("  Tier 3 (360-720 days):", tierRates[2], "= 2%");
        console.log("  Tier 4 (720-1080 days):", tierRates[3], "= 4%");
        console.log("  Tier 5 (1080-1440 days):", tierRates[4], "= 5%");
        console.log("  Tier 6 (1440+ days):", tierRates[5], "= 6%");
    }

    function _parseFounders() internal view returns (address[] memory) {
        string memory foundersEnv = vm.envOr("FOUNDER_ADDRESSES", string(""));
        if (bytes(foundersEnv).length == 0) {
            return new address[](0);
        }

        // Simple parsing for up to 10 founders
        // Format: "0x123...,0x456...,0x789..."
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
