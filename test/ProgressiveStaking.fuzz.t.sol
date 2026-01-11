// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ProgressiveStakingBaseTest} from "./ProgressiveStaking.base.t.sol";
import {ProgressiveStaking} from "../src/ProgressiveStaking.sol";

/**
 * @title ProgressiveStakingFuzzTest
 * @notice Fuzz tests for ProgressiveStaking contract
 * @dev Property-based testing with random inputs to find edge cases.
 *      Foundry runs each fuzz test 256 times by default with different random values.
 *
 * Test Categories:
 * - Random stake amounts (1 wei to 10M tokens)
 * - Random number of stake positions (1-20)
 * - Random time periods (1 day to 10 years)
 * - Random partial withdrawal percentages (1-99%)
 */
contract ProgressiveStakingFuzzTest is ProgressiveStakingBaseTest {

    /**
     * @notice Fuzz test: Stake with random amounts
     * @dev Tests that staking works correctly for any valid amount from MIN_STAKE_AMOUNT to max balance.
     *      Verifies position creation and total staked tracking.
     * @param amount Random stake amount (bounded to MIN_STAKE_AMOUNT - INITIAL_BALANCE)
     */
    function testFuzz_Stake(uint256 amount) public {
        amount = bound(amount, staking.MIN_STAKE_AMOUNT(), INITIAL_BALANCE);

        vm.prank(user1);
        staking.stake(amount);

        assertEq(staking.getUserStakeCount(user1), 1);
        assertEq(staking.totalStaked(), amount);

        ProgressiveStaking.StakePosition[] memory positions = staking.getStakeInfo(user1);
        assertEq(positions[0].amount, amount);
    }

    /**
     * @notice Fuzz test: Create random number of stake positions
     * @dev Tests that contract handles multiple positions correctly.
     *      Each position has incrementing amount (1000 + i*100 tokens).
     * @param numStakes Random number of stakes (bounded to 1-20)
     */
    function testFuzz_StakeMultipleTimes(uint8 numStakes) public {
        numStakes = uint8(bound(numStakes, 1, 20));

        uint256 totalAmount = 0;
        vm.startPrank(user1);
        for (uint8 i = 0; i < numStakes; i++) {
            uint256 amount = 1000 ether + (i * 100 ether);
            staking.stake(amount);
            totalAmount += amount;
        }
        vm.stopPrank();

        assertEq(staking.getUserStakeCount(user1), numStakes);
        assertEq(staking.totalStaked(), totalAmount);
    }

    /**
     * @notice Fuzz test: Calculate rewards after random time periods
     * @dev Tests that reward calculation works for any duration from 1 day to 10 years.
     *      Ensures no overflow or underflow in tier calculations.
     * @param timeElapsed Random time in seconds (bounded to 1 day - 3650 days)
     */
    function testFuzz_TimeWarp(uint256 timeElapsed) public {
        timeElapsed = bound(timeElapsed, 1 days, 3650 days);

        vm.prank(user1);
        staking.stake(10_000 ether);

        vm.warp(block.timestamp + timeElapsed);

        uint256 rewards = staking.calculateTotalRewards(user1);
        assertGt(rewards, 0);
    }

    /**
     * @notice Fuzz test: Partial withdrawals with random percentages
     * @dev Tests that partial withdrawals work correctly for any percentage.
     *      Verifies remaining balance and position state.
     * @param percentage Random withdrawal percentage (bounded to 1-99%)
     */
    function testFuzz_PartialWithdraw(uint8 percentage) public {
        percentage = uint8(bound(percentage, 1, 99));

        uint256 stakeAmount = 10_000 ether;
        vm.prank(user1);
        staking.stake(stakeAmount);

        uint256 withdrawAmount = (stakeAmount * percentage) / 100;

        vm.prank(user1);
        staking.requestWithdraw(1, withdrawAmount);

        vm.warp(block.timestamp + 90 days);

        vm.prank(user1);
        staking.executeWithdraw(1);

        ProgressiveStaking.StakePosition[] memory positions = staking.getStakeInfo(user1);
        assertEq(positions[0].amount, stakeAmount - withdrawAmount);
    }

    /**
     * @notice Fuzz test: Multiple users with random stake amounts
     * @dev Tests isolation between users with random amounts.
     * @param amount1 Random amount for user1
     * @param amount2 Random amount for user2
     */
    function testFuzz_MultipleUsers(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1 ether, INITIAL_BALANCE / 2);
        amount2 = bound(amount2, 1 ether, INITIAL_BALANCE / 2);

        vm.prank(user1);
        staking.stake(amount1);

        vm.prank(user2);
        staking.stake(amount2);

        assertEq(staking.getUserStakeCount(user1), 1);
        assertEq(staking.getUserStakeCount(user2), 1);
        assertEq(staking.totalStaked(), amount1 + amount2);

        ProgressiveStaking.StakePosition[] memory pos1 = staking.getStakeInfo(user1);
        ProgressiveStaking.StakePosition[] memory pos2 = staking.getStakeInfo(user2);

        assertEq(pos1[0].amount, amount1);
        assertEq(pos2[0].amount, amount2);
    }

    /**
     * @notice Fuzz test: Rewards calculation consistency
     * @dev Tests that rewards are always positive and increase with time.
     * @param time1 First time period
     * @param time2 Additional time period
     */
    function testFuzz_RewardsIncreaseWithTime(uint256 time1, uint256 time2) public {
        time1 = bound(time1, 1 days, 180 days);
        time2 = bound(time2, 1 days, 180 days);

        vm.prank(user1);
        staking.stake(10_000 ether);

        vm.warp(block.timestamp + time1);
        uint256 rewards1 = staking.calculateTotalRewards(user1);

        vm.warp(block.timestamp + time2);
        uint256 rewards2 = staking.calculateTotalRewards(user1);

        assertGe(rewards2, rewards1, "Rewards should not decrease with time");
    }

    /**
     * @notice Fuzz test: Stake amount affects rewards proportionally
     * @dev Tests that doubling stake roughly doubles rewards (within same tier).
     * @param baseAmount Base stake amount
     */
    function testFuzz_RewardsProportionalToStake(uint256 baseAmount) public {
        baseAmount = bound(baseAmount, 100 ether, 1_000_000 ether);

        vm.prank(user1);
        staking.stake(baseAmount);

        vm.prank(user2);
        staking.stake(baseAmount * 2);

        vm.warp(block.timestamp + 90 days);

        uint256 rewards1 = staking.calculateTotalRewards(user1);
        uint256 rewards2 = staking.calculateTotalRewards(user2);

        // Rewards should be roughly proportional (within 1% tolerance due to rounding)
        assertApproxEqRel(rewards2, rewards1 * 2, 0.01e18);
    }
}
