// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ProgressiveStakingBaseTest} from "./ProgressiveStaking.base.t.sol";
import {ProgressiveStaking} from "../src/ProgressiveStaking.sol";

/**
 * @title ProgressiveStakingDoSTest
 * @notice DoS attack prevention tests for ProgressiveStaking contract
 * @dev Tests gas limits, pending withdrawal limits, and user isolation
 */
contract ProgressiveStakingDoSTest is ProgressiveStakingBaseTest {

    /// @notice Test that attacker cannot DoS other users via withdraw request spam
    function test_DoS_WithdrawRequestSpamPrevention() public {
        address attacker = makeAddr("attacker");
        token.mint(attacker, 1_000_000 ether);
        vm.prank(attacker);
        token.approve(address(staking), type(uint256).max);

        for (uint256 i = 0; i < 100; i++) {
            vm.prank(attacker);
            staking.stake(100 ether);
        }

        for (uint256 i = 1; i <= 10; i++) {
            vm.prank(attacker);
            staking.requestWithdraw(i, 50 ether);
        }

        vm.prank(attacker);
        vm.expectRevert(ProgressiveStaking.TooManyPendingWithdrawals.selector);
        staking.requestWithdraw(11, 50 ether);

        vm.prank(user1);
        staking.stake(1000 ether);

        vm.prank(user1);
        staking.requestWithdraw(101, 500 ether);

        assertEq(staking.pendingWithdrawCount(user1), 1);
    }

    /// @notice Test max pending withdrawals limit
    function test_MaxPendingWithdrawalsLimit() public {
        for (uint256 i = 0; i < 11; i++) {
            vm.prank(user1);
            staking.stake(100 ether);
        }

        for (uint256 i = 1; i <= 10; i++) {
            vm.prank(user1);
            staking.requestWithdraw(i, 50 ether);
        }

        vm.prank(user1);
        vm.expectRevert(ProgressiveStaking.TooManyPendingWithdrawals.selector);
        staking.requestWithdraw(11, 50 ether);
    }

    /// @notice Test that executing withdrawal frees up pending slot
    function test_ExecuteWithdrawFreesPendingSlot() public {
        for (uint256 i = 0; i < 11; i++) {
            vm.prank(user1);
            staking.stake(100 ether);
        }

        for (uint256 i = 1; i <= 10; i++) {
            vm.prank(user1);
            staking.requestWithdraw(i, 50 ether);
        }

        vm.warp(block.timestamp + 90 days);

        vm.prank(user1);
        staking.executeWithdraw(1);

        vm.prank(user1);
        staking.requestWithdraw(11, 50 ether);
    }

    /// @notice Test that cancelling withdrawal frees up pending slot
    function test_CancelWithdrawFreesPendingSlot() public {
        for (uint256 i = 0; i < 11; i++) {
            vm.prank(user1);
            staking.stake(100 ether);
        }

        for (uint256 i = 1; i <= 10; i++) {
            vm.prank(user1);
            staking.requestWithdraw(i, 50 ether);
        }

        vm.prank(user1);
        staking.cancelWithdrawRequest(5);

        vm.prank(user1);
        staking.requestWithdraw(11, 50 ether);
    }

    /// @notice Test O(1) pending withdraw check with mapping
    function test_PendingWithdrawMappingTracking() public {
        vm.prank(user1);
        staking.stake(1000 ether);

        assertEq(staking.pendingWithdrawCount(user1), 0);

        vm.prank(user1);
        staking.requestWithdraw(1, 500 ether);

        assertEq(staking.pendingWithdrawCount(user1), 1);

        vm.prank(user1);
        vm.expectRevert(ProgressiveStaking.PositionHasPendingWithdraw.selector);
        staking.requestWithdraw(1, 200 ether);

        vm.warp(block.timestamp + 90 days);
        vm.prank(user1);
        staking.executeWithdraw(1);

        assertEq(staking.pendingWithdrawCount(user1), 0);

        vm.prank(user1);
        staking.requestWithdraw(1, 200 ether);
        assertEq(staking.pendingWithdrawCount(user1), 1);
    }

    /// @notice Test gas cost remains bounded with many withdraw requests
    function test_DoS_GasCostBounded() public {
        for (uint256 i = 0; i < 10; i++) {
            vm.prank(user1);
            staking.stake(100 ether);
        }

        for (uint256 i = 1; i <= 10; i++) {
            vm.prank(user1);
            staking.requestWithdraw(i, 50 ether);
        }

        uint256 gasBefore = gasleft();
        vm.prank(user1);
        vm.expectRevert(ProgressiveStaking.PositionHasPendingWithdraw.selector);
        staking.requestWithdraw(1, 10 ether);
        uint256 gasUsed = gasBefore - gasleft();

        assertLt(gasUsed, 50_000, "Gas cost too high for pending check");
    }

    /// @notice Test that multiple users don't affect each other's gas costs
    function test_DoS_UserIsolation() public {
        for (uint256 i = 0; i < 10; i++) {
            vm.prank(user1);
            staking.stake(100 ether);
        }
        for (uint256 i = 1; i <= 10; i++) {
            vm.prank(user1);
            staking.requestWithdraw(i, 50 ether);
        }

        vm.prank(user2);
        staking.stake(1000 ether);

        uint256 gasBefore = gasleft();
        vm.prank(user2);
        staking.requestWithdraw(11, 500 ether);
        uint256 gasUsed = gasBefore - gasleft();

        assertLt(gasUsed, 200_000, "User2 affected by user1's state");
    }

    /// @notice Test that large number of users doesn't cause global DoS
    function test_DoS_ManyUsers() public {
        address[] memory users = new address[](50);
        for (uint256 i = 0; i < 50; i++) {
            users[i] = makeAddr(string(abi.encodePacked("user", i)));
            token.mint(users[i], 10_000 ether);
            vm.prank(users[i]);
            token.approve(address(staking), type(uint256).max);

            vm.prank(users[i]);
            staking.stake(1000 ether);
        }

        for (uint256 i = 0; i < 50; i++) {
            vm.prank(users[i]);
            staking.requestWithdraw(i + 1, 500 ether);
        }

        for (uint256 i = 0; i < 50; i++) {
            assertEq(staking.pendingWithdrawCount(users[i]), 1);
        }

        assertEq(staking.totalStaked(), 50 * 1000 ether);
    }

    /// @notice Test that stake array manipulation doesn't cause DoS
    function test_DoS_StakeArrayManipulation() public {
        for (uint256 i = 0; i < 20; i++) {
            vm.prank(user1);
            staking.stake(100 ether);
        }

        uint256[] memory toRemove = new uint256[](5);
        toRemove[0] = 5;
        toRemove[1] = 10;
        toRemove[2] = 15;
        toRemove[3] = 3;
        toRemove[4] = 18;

        for (uint256 i = 0; i < toRemove.length; i++) {
            vm.prank(user1);
            staking.requestWithdraw(toRemove[i], 100 ether);

            vm.warp(block.timestamp + 90 days);

            vm.prank(user1);
            staking.executeWithdraw(toRemove[i]);
        }

        assertEq(staking.getUserStakeCount(user1), 15);

        vm.prank(user1);
        staking.stake(100 ether);

        assertEq(staking.getUserStakeCount(user1), 16);
    }

    /// @notice Test claimAllRewards gas with many positions
    function test_DoS_ClaimAllRewardsGas() public {
        for (uint256 i = 0; i < 20; i++) {
            vm.prank(user1);
            staking.stake(100 ether);
        }

        vm.warp(block.timestamp + 180 days);

        uint256 gasBefore = gasleft();
        vm.prank(user1);
        staking.claimAllRewards();
        uint256 gasUsed = gasBefore - gasleft();

        assertLt(gasUsed, 1_000_000, "claimAllRewards gas too high");
    }
}
