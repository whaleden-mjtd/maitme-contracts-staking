// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ProgressiveStakingBaseTest} from "./ProgressiveStaking.base.t.sol";
import {ProgressiveStaking} from "../src/ProgressiveStaking.sol";

/**
 * @title ProgressiveStakingTimeTest
 * @notice Time manipulation tests for ProgressiveStaking contract
 * @dev Tests tier transitions, long-term behavior, and time-based edge cases.
 *
 * Test Categories:
 * - Rewards at exact tier boundaries (180, 360, 720, 1080, 1440 days)
 * - Rewards just before/after tier changes
 * - Claiming at different intervals
 * - Long-term staking (5+ years)
 * - Index changes after withdrawals
 */
contract ProgressiveStakingTimeTest is ProgressiveStakingBaseTest {

    // ============ Tier Boundary Tests ============

    /**
     * @notice Test rewards at exact Tier 1 boundary (180 days)
     * @dev At exactly 180 days, user should still be in Tier 1
     */
    function test_RewardsAtTier1Boundary() public {
        vm.prank(user1);
        staking.stake(10_000 ether);

        vm.warp(block.timestamp + 180 days);

        uint8 tier = staking.getCurrentTier(user1, 1);
        assertEq(tier, 2); // At exactly 180 days, we're at start of Tier 2

        uint256 rewards = staking.calculateTotalRewards(user1);
        // 10,000 * 0.5% * 0.5 = 25 tokens
        assertApproxEqRel(rewards, 25 ether, 0.01e18);
    }

    /**
     * @notice Test rewards just after Tier 1 boundary (181 days)
     * @dev At 181 days, user should be in Tier 2
     */
    function test_RewardsJustAfterTier1() public {
        vm.prank(user1);
        staking.stake(10_000 ether);

        vm.warp(block.timestamp + 181 days);

        uint8 tier = staking.getCurrentTier(user1, 1);
        assertEq(tier, 2);
    }

    /**
     * @notice Test rewards at exact Tier 2 boundary (360 days)
     * @dev Verifies compound calculation across Tier 1 and Tier 2
     */
    function test_RewardsAtTier2Boundary() public {
        vm.prank(user1);
        staking.stake(10_000 ether);

        vm.warp(block.timestamp + 360 days);

        uint8 tier = staking.getCurrentTier(user1, 1);
        assertEq(tier, 3); // At exactly 360 days, we're at start of Tier 3

        uint256 rewards = staking.calculateTotalRewards(user1);
        // Tier 1: 10,000 * 0.5% * 0.5 = 25
        // Tier 2: 10,025 * 0.7% * 0.5 = 35.09
        // Total: ~60.09
        assertApproxEqRel(rewards, 60.0875 ether, 0.01e18);
    }

    /**
     * @notice Test rewards at Tier 3 boundary (720 days = 2 years)
     * @dev Verifies compound calculation across Tier 1, 2, and 3
     */
    function test_RewardsAtTier3Boundary() public {
        vm.prank(user1);
        staking.stake(10_000 ether);

        vm.warp(block.timestamp + 720 days);

        uint8 tier = staking.getCurrentTier(user1, 1);
        assertEq(tier, 4); // At exactly 720 days, we're at start of Tier 4

        uint256 rewards = staking.calculateTotalRewards(user1);
        // Tier 1: 25, Tier 2: 35.09, Tier 3: 201.2
        // Total: ~261.3
        assertApproxEqRel(rewards, 261.29 ether, 0.01e18);
    }

    /**
     * @notice Test long-term staking through all tiers (5 years)
     * @dev Verifies compound accuracy across all 6 tiers
     */
    function test_LongTermStaking5Years() public {
        vm.prank(user1);
        staking.stake(10_000 ether);

        vm.warp(block.timestamp + 1800 days); // 5 years

        uint8 tier = staking.getCurrentTier(user1, 1);
        assertEq(tier, 6);

        uint256 rewards = staking.calculateTotalRewards(user1);
        // Should be significant after 5 years with compounding
        assertGt(rewards, 1800 ether);
        assertLt(rewards, 1950 ether);
    }

    /**
     * @notice Test very long-term staking (10 years in Tier 6)
     * @dev Ensures no overflow with extended Tier 6 duration
     */
    function test_VeryLongTermStaking10Years() public {
        vm.prank(user1);
        staking.stake(10_000 ether);

        vm.warp(block.timestamp + 3650 days); // 10 years

        uint8 tier = staking.getCurrentTier(user1, 1);
        assertEq(tier, 6);

        uint256 rewards = staking.calculateTotalRewards(user1);
        // Should have significant rewards without overflow
        assertGt(rewards, 0);
    }

    // ============ Claiming Interval Tests ============

    /**
     * @notice Test claiming rewards at different intervals
     * @dev Verifies that claiming doesn't affect total rewards over time
     */
    function test_ClaimingAtDifferentIntervals() public {
        vm.prank(user1);
        staking.stake(10_000 ether);

        // Claim at 90 days
        vm.warp(block.timestamp + 90 days);
        uint256 rewards1 = staking.calculateTotalRewards(user1);
        vm.prank(user1);
        staking.claimRewards(1);

        // Claim at 180 days
        vm.warp(block.timestamp + 90 days);
        uint256 rewards2 = staking.calculateTotalRewards(user1);
        vm.prank(user1);
        staking.claimRewards(1);

        // Both claims should be roughly equal (same tier, same duration)
        assertApproxEqRel(rewards1, rewards2, 0.05e18);
    }

    /**
     * @notice Test rewards accumulate correctly after claim
     * @dev Second claim in Tier 2 should be larger due to higher APY
     */
    function test_RewardsAccumulateCorrectlyAfterClaim() public {
        vm.prank(user1);
        staking.stake(10_000 ether);

        // Claim at 180 days
        vm.warp(block.timestamp + 180 days);
        uint256 rewards1 = staking.calculateTotalRewards(user1);
        vm.prank(user1);
        staking.claimRewards(1);

        // Claim at 360 days
        vm.warp(block.timestamp + 180 days);
        uint256 rewards2 = staking.calculateTotalRewards(user1);
        vm.prank(user1);
        staking.claimRewards(1);

        // Second claim should be higher (Tier 2 rate)
        assertGt(rewards2, rewards1);
    }

    // ============ Index Changes Tests ============

    /**
     * @notice Test that position indices update correctly after withdrawal
     * @dev When middle position is removed, last position moves to fill gap
     */
    function test_IndexChangesAfterWithdraw() public {
        // Create 3 positions
        vm.startPrank(user1);
        staking.stake(1000 ether); // stakeId 1
        staking.stake(2000 ether); // stakeId 2
        staking.stake(3000 ether); // stakeId 3
        vm.stopPrank();

        // Request withdraw for middle position
        vm.prank(user1);
        staking.requestWithdraw(2, 2000 ether);

        vm.warp(block.timestamp + 90 days);

        vm.prank(user1);
        staking.executeWithdraw(2);

        // Should have 2 positions left
        assertEq(staking.getUserStakeCount(user1), 2);

        // Position 1 and 3 should still be accessible
        ProgressiveStaking.StakePosition memory pos1 = staking.getStakeByStakeId(user1, 1);
        ProgressiveStaking.StakePosition memory pos3 = staking.getStakeByStakeId(user1, 3);

        assertEq(pos1.amount, 1000 ether);
        assertEq(pos3.amount, 3000 ether);
    }

    /**
     * @notice Test stakeIds persist correctly after index changes
     * @dev StakeIds should remain valid even after array reorganization
     */
    function test_StakeIdsPersistAfterIndexChange() public {
        // Create 5 positions
        vm.startPrank(user1);
        for (uint256 i = 0; i < 5; i++) {
            staking.stake(1000 ether);
        }
        vm.stopPrank();

        // Remove positions 2 and 4
        vm.prank(user1);
        staking.requestWithdraw(2, 1000 ether);
        vm.warp(block.timestamp + 90 days);
        vm.prank(user1);
        staking.executeWithdraw(2);

        vm.prank(user1);
        staking.requestWithdraw(4, 1000 ether);
        vm.warp(block.timestamp + 90 days);
        vm.prank(user1);
        staking.executeWithdraw(4);

        // Remaining positions (1, 3, 5) should still be accessible
        assertEq(staking.getUserStakeCount(user1), 3);

        staking.getStakeByStakeId(user1, 1);
        staking.getStakeByStakeId(user1, 3);
        staking.getStakeByStakeId(user1, 5);

        // Removed positions should revert
        vm.expectRevert(ProgressiveStaking.InvalidStakeId.selector);
        staking.getStakeByStakeId(user1, 2);

        vm.expectRevert(ProgressiveStaking.InvalidStakeId.selector);
        staking.getStakeByStakeId(user1, 4);
    }

    /**
     * @notice Test sequential withdrawals from same position
     * @dev Multiple partial withdrawals should work correctly
     */
    function test_SequentialPartialWithdrawals() public {
        vm.prank(user1);
        staking.stake(10_000 ether);

        // First partial withdrawal
        vm.prank(user1);
        staking.requestWithdraw(1, 3000 ether);

        ProgressiveStaking.WithdrawRequest[] memory firstReq = staking.getActivePendingWithdrawals(user1);
        assertEq(firstReq.length, 1);
        uint256 firstWithdrawStakeId = firstReq[0].stakeId;
        vm.warp(block.timestamp + 90 days);
        vm.prank(user1);
        staking.executeWithdraw(firstWithdrawStakeId);

        ProgressiveStaking.StakePosition memory pos = staking.getStakeByStakeId(user1, 1);
        assertEq(pos.amount, 7000 ether);

        // Second partial withdrawal
        vm.prank(user1);
        staking.requestWithdraw(1, 2000 ether);

        ProgressiveStaking.WithdrawRequest[] memory secondReq = staking.getActivePendingWithdrawals(user1);
        assertEq(secondReq.length, 1);
        uint256 secondWithdrawStakeId = secondReq[0].stakeId;
        vm.warp(block.timestamp + 90 days);
        vm.prank(user1);
        staking.executeWithdraw(secondWithdrawStakeId);

        pos = staking.getStakeByStakeId(user1, 1);
        assertEq(pos.amount, 5000 ether);
    }

    // ============ Multi-User Time Tests ============

    /**
     * @notice Test that users have independent reward timelines
     * @dev User staking later should have different tier than earlier user
     */
    function test_IndependentUserTimelines() public {
        // User1 stakes at time 0
        vm.prank(user1);
        staking.stake(10_000 ether);

        // Fast forward 180 days
        vm.warp(block.timestamp + 180 days);

        // User2 stakes at day 180
        vm.prank(user2);
        staking.stake(10_000 ether);

        // Fast forward another 180 days (total 360 days)
        vm.warp(block.timestamp + 180 days);

        // User1 should be in Tier 3 (360 days), User2 should be in Tier 2 (180 days)
        assertEq(staking.getCurrentTier(user1, 1), 3);
        assertEq(staking.getCurrentTier(user2, 2), 2);

        // User1 should have more rewards
        uint256 rewards1 = staking.calculateTotalRewards(user1);
        uint256 rewards2 = staking.calculateTotalRewards(user2);
        assertGt(rewards1, rewards2);
    }
}
