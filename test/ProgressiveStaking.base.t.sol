// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ProgressiveStaking} from "../src/ProgressiveStaking.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";

/**
 * @title ProgressiveStakingBaseTest
 * @notice Base test contract with shared setup for all test files
 * @dev Inherit from this contract to get common setup and utilities
 */
abstract contract ProgressiveStakingBaseTest is Test {
    ProgressiveStaking public staking;
    ERC20Mock public token;

    address public owner = makeAddr("owner");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public user3 = makeAddr("user3");
    address public founder = makeAddr("founder");

    uint256 public constant INITIAL_BALANCE = 10_000_000 ether;
    uint256 public constant TREASURY_AMOUNT = 1_000_000 ether;

    uint256[6] public tierRates = [uint256(50), 70, 200, 400, 500, 600];

    function setUp() public virtual {
        token = new ERC20Mock("Staking Token", "STK");

        address[] memory founders = new address[](1);
        founders[0] = founder;

        vm.prank(owner);
        staking = new ProgressiveStaking(owner, address(token), founders, tierRates);

        token.mint(owner, INITIAL_BALANCE);
        token.mint(user1, INITIAL_BALANCE);
        token.mint(user2, INITIAL_BALANCE);
        token.mint(user3, INITIAL_BALANCE);
        token.mint(founder, INITIAL_BALANCE);

        vm.startPrank(owner);
        token.approve(address(staking), TREASURY_AMOUNT);
        staking.depositTreasury(TREASURY_AMOUNT);
        vm.stopPrank();

        vm.prank(user1);
        token.approve(address(staking), type(uint256).max);
        vm.prank(user2);
        token.approve(address(staking), type(uint256).max);
        vm.prank(user3);
        token.approve(address(staking), type(uint256).max);
        vm.prank(founder);
        token.approve(address(staking), type(uint256).max);
    }
}
