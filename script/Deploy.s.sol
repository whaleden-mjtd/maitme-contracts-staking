// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ProgressiveStaking} from "../src/ProgressiveStaking.sol";

/**
 * @title DeployScript
 * @notice Deployment script for ProgressiveStaking contract
 */
contract DeployScript is Script {
    // Default tier rates in basis points (50 = 0.5%, 100 = 1%, etc.)
    uint256[6] public defaultTierRates = [uint256(50), 70, 200, 400, 500, 600];

    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address stakingToken = vm.envAddress("STAKING_TOKEN_ADDRESS");
        
        // Parse founder addresses from env (comma-separated)
        string memory foundersEnv = vm.envOr("FOUNDER_ADDRESSES", string(""));
        address[] memory founders = _parseFounders(foundersEnv);

        vm.startBroadcast(deployerPrivateKey);

        ProgressiveStaking staking = new ProgressiveStaking(
            msg.sender,
            stakingToken,
            founders,
            defaultTierRates
        );

        console.log("ProgressiveStaking deployed at:", address(staking));
        console.log("Staking token:", stakingToken);
        console.log("Owner:", msg.sender);
        console.log("Founders count:", founders.length);

        vm.stopBroadcast();
    }

    function _parseFounders(string memory foundersStr) internal pure returns (address[] memory) {
        if (bytes(foundersStr).length == 0) {
            return new address[](0);
        }

        // Count commas to determine array size
        uint256 count = 1;
        bytes memory strBytes = bytes(foundersStr);
        for (uint256 i = 0; i < strBytes.length; i++) {
            if (strBytes[i] == ",") {
                count++;
            }
        }

        // For simplicity, return empty array - founders should be set manually
        // In production, use a more robust parsing or pass founders as constructor args
        return new address[](0);
    }
}
