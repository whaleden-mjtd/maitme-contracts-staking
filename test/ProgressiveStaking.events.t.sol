// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ProgressiveStakingBaseTest} from "./ProgressiveStaking.base.t.sol";
import {ProgressiveStaking} from "../src/ProgressiveStaking.sol";

/**
 * @title ProgressiveStakingEventsTest
 * @notice Event emission tests for ProgressiveStaking contract
 * @dev Tests that all events are emitted correctly with proper parameters
 */
contract ProgressiveStakingEventsTest is ProgressiveStakingBaseTest {

    /// @notice Test Staked event is emitted correctly
    function test_StakedEventEmission() public {
        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit ProgressiveStaking.Staked(user1, 1, 1000 ether, block.timestamp);
        staking.stake(1000 ether);
    }

    /// @notice Test RewardsClaimed event is emitted correctly
    function test_RewardsClaimedEventEmission() public {
        vm.prank(user1);
        staking.stake(10_000 ether);

        vm.warp(block.timestamp + 180 days);

        uint256 expectedRewards = staking.calculateTotalRewards(user1);

        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit ProgressiveStaking.RewardsClaimed(user1, 1, expectedRewards, block.timestamp);
        staking.claimRewards(1);
    }

    /// @notice Test AllRewardsClaimed event is emitted correctly
    function test_AllRewardsClaimedEventEmission() public {
        vm.startPrank(user1);
        staking.stake(5000 ether);
        staking.stake(5000 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + 180 days);

        uint256 expectedRewards = staking.calculateTotalRewards(user1);

        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit ProgressiveStaking.AllRewardsClaimed(user1, expectedRewards, block.timestamp);
        staking.claimAllRewards();
    }

    /// @notice Test WithdrawRequested event is emitted correctly
    function test_WithdrawRequestedEventEmission() public {
        vm.prank(user1);
        staking.stake(1000 ether);

        uint256 expectedAvailableAt = block.timestamp + 90 days;

        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit ProgressiveStaking.WithdrawRequested(user1, 1, 500 ether, block.timestamp, expectedAvailableAt);
        staking.requestWithdraw(1, 500 ether);
    }

    /// @notice Test WithdrawExecuted event is emitted correctly
    function test_WithdrawExecutedEventEmission() public {
        vm.prank(user1);
        staking.stake(1000 ether);

        vm.prank(user1);
        staking.requestWithdraw(1, 1000 ether);

        vm.warp(block.timestamp + 90 days);

        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit ProgressiveStaking.WithdrawExecuted(user1, 1, 1000 ether, block.timestamp);
        staking.executeWithdraw(1);
    }

    /// @notice Test WithdrawCancelled event is emitted correctly
    function test_WithdrawCancelledEventEmission() public {
        vm.prank(user1);
        staking.stake(1000 ether);

        vm.prank(user1);
        staking.requestWithdraw(1, 500 ether);

        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit ProgressiveStaking.WithdrawCancelled(user1, 1, 500 ether, block.timestamp);
        staking.cancelWithdrawRequest(1);
    }

    /// @notice Test EmergencyWithdrawn event is emitted correctly
    function test_EmergencyWithdrawnEventEmission() public {
        vm.prank(user1);
        staking.stake(10_000 ether);

        vm.warp(block.timestamp + 180 days);

        vm.prank(owner);
        staking.emergencyShutdown();

        uint256 expectedRewards = staking.calculateTotalRewards(user1);

        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit ProgressiveStaking.EmergencyWithdrawn(user1, 10_000 ether, expectedRewards, block.timestamp);
        staking.emergencyWithdraw();
    }

    /// @notice Test EmergencyShutdown event is emitted correctly
    function test_EmergencyShutdownEventEmission() public {
        vm.prank(user1);
        staking.stake(1000 ether);

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit ProgressiveStaking.EmergencyShutdown(owner, block.timestamp, 1000 ether, 0);
        staking.emergencyShutdown();
    }

    /// @notice Test TreasuryDeposited event is emitted correctly
    function test_TreasuryDepositedEventEmission() public {
        vm.startPrank(owner);
        token.approve(address(staking), 1000 ether);

        vm.expectEmit(true, false, false, true);
        emit ProgressiveStaking.TreasuryDeposited(owner, 1000 ether, block.timestamp);
        staking.depositTreasury(1000 ether);
        vm.stopPrank();
    }

    /// @notice Test TreasuryWithdrawn event is emitted correctly
    function test_TreasuryWithdrawnEventEmission() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit ProgressiveStaking.TreasuryWithdrawn(owner, 1000 ether, block.timestamp);
        staking.withdrawTreasury(1000 ether);
    }

    /// @notice Test TierRatesUpdated event is emitted correctly
    function test_TierRatesUpdatedEventEmission() public {
        uint256[6] memory newRates = [uint256(100), 150, 250, 450, 550, 650];

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit ProgressiveStaking.TierRatesUpdated(owner, newRates, block.timestamp);
        staking.updateTierRates(newRates);
    }

    /// @notice Test ContractPaused event is emitted correctly
    function test_ContractPausedEventEmission() public {
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit ProgressiveStaking.ContractPaused(owner, block.timestamp);
        staking.pause();
    }

    /// @notice Test ContractUnpaused event is emitted correctly
    function test_ContractUnpausedEventEmission() public {
        vm.prank(owner);
        staking.pause();

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit ProgressiveStaking.ContractUnpaused(owner, block.timestamp);
        staking.unpause();
    }
}
