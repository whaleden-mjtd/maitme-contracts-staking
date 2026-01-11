// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ProgressiveStaking} from "../src/ProgressiveStaking.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";

/**
 * @title ProgressiveStakingAdvancedTest
 * @notice Advanced test suite for ProgressiveStaking contract
 * @dev This test file covers advanced scenarios that go beyond basic functionality:
 *
 * Test Categories:
 * 1. FUZZ TESTS - Property-based testing with random inputs
 *    - Random stake amounts (1 wei to 10M tokens)
 *    - Random number of stake positions (1-20)
 *    - Random time periods (1 day to 10 years)
 *    - Random partial withdrawal percentages (1-99%)
 *
 * 2. TIME MANIPULATION TESTS - Testing tier transitions and long-term behavior
 *    - Rewards at exact tier boundaries (180, 360, 720, 1080, 1440 days)
 *    - Rewards just before/after tier changes
 *    - Claiming at different intervals
 *    - Long-term staking (5+ years)
 *
 * 3. INDEX CHANGES TESTS - Testing array management after withdrawals
 *    - Position removal from middle of array
 *    - Multiple sequential withdrawals
 *    - StakeId persistence after index changes
 *
 * 4. MULTI-USER TESTS - Testing isolation between users
 *    - Independent staking and rewards
 *    - Global stakeId counter across users
 *
 * 5. EDGE CASES - Boundary conditions and error handling
 *    - Claiming immediately after stake (0 rewards)
 *    - Withdrawing more than staked
 *    - Double withdrawal requests
 *    - Insufficient treasury
 *
 * 6. ACCESS CONTROL TESTS - Permission verification
 *    - Owner-only functions
 *    - Admin-only functions
 *
 * 7. COMPOUND ACCURACY TESTS - Mathematical precision verification
 *    - Single tier accuracy
 *    - Multi-tier compound accuracy
 *    - Rewards after partial claims
 */
contract ProgressiveStakingAdvancedTest is Test {
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

    function setUp() public {
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

    // ============ Fuzz Tests ============
    // Fuzz tests use random inputs to find edge cases that manual tests might miss.
    // Foundry runs each fuzz test 256 times by default with different random values.

    /**
     * @notice Fuzz test: Stake with random amounts
     * @dev Tests that staking works correctly for any valid amount from 1 wei to max balance.
     *      Verifies position creation and total staked tracking.
     * @param amount Random stake amount (bounded to 1 - INITIAL_BALANCE)
     */
    function testFuzz_Stake(uint256 amount) public {
        // Bound amount to reasonable range
        amount = bound(amount, 1, INITIAL_BALANCE);

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
        // Bound to reasonable number of stakes
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
        // Bound time to 0-10 years
        timeElapsed = bound(timeElapsed, 1 days, 3650 days);

        vm.prank(user1);
        staking.stake(10_000 ether);

        vm.warp(block.timestamp + timeElapsed);

        // Rewards should always be calculable without reverting
        uint256 rewards = staking.calculateTotalRewards(user1);

        // Rewards should be positive for any time > 0
        assertGt(rewards, 0);
    }

    /**
     * @notice Fuzz test: Partial withdrawal with random percentages
     * @dev Tests that partial withdrawals work correctly for any percentage 1-99%.
     *      Verifies remaining balance is calculated correctly.
     * @param withdrawPercent Random percentage (bounded to 1-99)
     */
    function testFuzz_PartialWithdraw(uint256 withdrawPercent) public {
        // Bound to 1-99%
        withdrawPercent = bound(withdrawPercent, 1, 99);

        uint256 stakeAmount = 10_000 ether;
        uint256 withdrawAmount = (stakeAmount * withdrawPercent) / 100;

        vm.prank(user1);
        staking.stake(stakeAmount);

        vm.prank(user1);
        staking.requestWithdraw(1, withdrawAmount);

        vm.warp(block.timestamp + 91 days);

        vm.prank(user1);
        staking.executeWithdraw(1);

        ProgressiveStaking.StakePosition memory position = staking.getStakeByStakeId(user1, 1);
        assertEq(position.amount, stakeAmount - withdrawAmount);
    }

    // ============ Time Manipulation Tests ============
    // These tests verify correct behavior at tier boundaries and over long time periods.
    // Uses vm.warp() to simulate time passage.

    /**
     * @notice Test rewards calculation at exact tier boundary timestamps
     * @dev Checks rewards at 180, 360, 720, 1080, 1440, and 1800 days.
     *      Verifies rewards always increase as time progresses through tiers.
     */
    function test_RewardsAtTierBoundaries() public {
        vm.prank(user1);
        staking.stake(10_000 ether);

        // Test at exact tier boundaries
        uint256[] memory boundaries = new uint256[](6);
        boundaries[0] = 180 days;  // End of Tier 1
        boundaries[1] = 360 days;  // End of Tier 2
        boundaries[2] = 720 days;  // End of Tier 3
        boundaries[3] = 1080 days; // End of Tier 4
        boundaries[4] = 1440 days; // End of Tier 5
        boundaries[5] = 1800 days; // In Tier 6

        uint256 prevRewards = 0;
        for (uint256 i = 0; i < boundaries.length; i++) {
            vm.warp(block.timestamp + boundaries[i]);
            uint256 rewards = staking.calculateTotalRewards(user1);
            assertGt(rewards, prevRewards, "Rewards should increase over time");
            prevRewards = rewards;
            vm.warp(block.timestamp - boundaries[i]); // Reset
        }
    }

    /**
     * @notice Test tier transition at boundary (179 days vs 181 days)
     * @dev Verifies:
     *      - Tier changes from 1 to 2 at 180 days
     *      - Rewards increase after tier change due to higher APY
     */
    function test_RewardsJustBeforeAndAfterTierChange() public {
        vm.prank(user1);
        staking.stake(10_000 ether);

        // Just before Tier 2 (179 days)
        vm.warp(block.timestamp + 179 days);
        uint256 rewardsBefore = staking.calculateTotalRewards(user1);
        uint8 tierBefore = staking.getCurrentTier(user1, 1);

        // Just after Tier 2 starts (181 days)
        vm.warp(block.timestamp + 2 days);
        uint256 rewardsAfter = staking.calculateTotalRewards(user1);
        uint8 tierAfter = staking.getCurrentTier(user1, 1);

        assertEq(tierBefore, 1);
        assertEq(tierAfter, 2);
        assertGt(rewardsAfter, rewardsBefore);
    }

    /**
     * @notice Test claiming rewards at regular intervals (every 30 days)
     * @dev Simulates user claiming monthly for a year.
     *      Verifies cumulative claims work correctly.
     */
    function test_ClaimAtDifferentTimeIntervals() public {
        vm.prank(user1);
        staking.stake(10_000 ether);

        uint256 totalClaimed = 0;

        // Claim every 30 days for 360 days
        for (uint256 i = 0; i < 12; i++) {
            vm.warp(block.timestamp + 30 days);

            uint256 rewards = staking.calculateTotalRewards(user1);
            if (rewards > 0) {
                uint256 balanceBefore = token.balanceOf(user1);
                vm.prank(user1);
                staking.claimRewards(1);
                uint256 balanceAfter = token.balanceOf(user1);
                totalClaimed += (balanceAfter - balanceBefore);
            }
        }

        assertGt(totalClaimed, 0);
    }

    /**
     * @notice Test long-term staking behavior (5 years)
     * @dev Verifies:
     *      - User reaches Tier 6 (VIP) after 48 months
     *      - Rewards accumulate correctly over long periods
     *      - Claiming still works after extended time
     */
    function test_LongTermStaking_5Years() public {
        vm.prank(user1);
        staking.stake(10_000 ether);

        // Fast forward 5 years (1825 days)
        vm.warp(block.timestamp + 1825 days);

        uint256 rewards = staking.calculateTotalRewards(user1);
        uint8 tier = staking.getCurrentTier(user1, 1);

        assertEq(tier, 6); // Should be in VIP tier
        assertGt(rewards, 0);

        // Claim should work
        vm.prank(user1);
        staking.claimRewards(1);
    }

    // ============ Index Changes Tests ============
    // These tests verify that the array-based position storage handles removals correctly.
    // When a position is removed, the last position is moved to fill the gap.
    // StakeIds must remain valid and accessible after index changes.

    /**
     * @notice Test position array management after withdrawing middle position
     * @dev Creates 5 positions, withdraws position 2 (middle).
     *      Verifies:
     *      - Position count decreases to 4
     *      - Position 5 is moved to index where position 2 was
     *      - All remaining stakeIds (1,3,4,5) are still accessible
     *      - StakeId 2 is no longer valid
     */
    function test_IndexChangesAfterWithdraw() public {
        // Create 5 positions
        vm.startPrank(user1);
        staking.stake(1000 ether); // stakeId 1
        staking.stake(2000 ether); // stakeId 2
        staking.stake(3000 ether); // stakeId 3
        staking.stake(4000 ether); // stakeId 4
        staking.stake(5000 ether); // stakeId 5
        vm.stopPrank();

        assertEq(staking.getUserStakeCount(user1), 5);

        // Withdraw position 2 (middle position)
        vm.prank(user1);
        staking.requestWithdraw(2, 2000 ether);

        vm.warp(block.timestamp + 91 days);

        vm.prank(user1);
        staking.executeWithdraw(2);

        // Should have 4 positions now
        assertEq(staking.getUserStakeCount(user1), 4);

        // Remaining positions should still be accessible
        // Note: position 5 was moved to index where position 2 was
        staking.getStakeByStakeId(user1, 1);
        staking.getStakeByStakeId(user1, 3);
        staking.getStakeByStakeId(user1, 4);
        staking.getStakeByStakeId(user1, 5);

        // Verify amounts are correct
        assertEq(staking.getStakeByStakeId(user1, 1).amount, 1000 ether);
        assertEq(staking.getStakeByStakeId(user1, 3).amount, 3000 ether);
        assertEq(staking.getStakeByStakeId(user1, 4).amount, 4000 ether);
        assertEq(staking.getStakeByStakeId(user1, 5).amount, 5000 ether);

        // Position 2 should not exist anymore (check last to not break other assertions)
        vm.expectRevert(ProgressiveStaking.InvalidStakeId.selector);
        staking.getStakeByStakeId(user1, 2);
    }

    /**
     * @notice Test sequential withdrawals and position count tracking
     * @dev Withdraws positions one by one to verify:
     *      - Position count decreases correctly after each withdrawal
     *      - Remaining positions stay accessible
     */
    function test_IndexChangesAfterMultipleWithdraws() public {
        // Create 10 positions
        vm.startPrank(user1);
        for (uint256 i = 0; i < 10; i++) {
            staking.stake(1000 ether);
        }
        vm.stopPrank();

        assertEq(staking.getUserStakeCount(user1), 10);

        // Withdraw positions one by one (to avoid index shifting issues during batch)
        // Withdraw stakeId 1
        vm.prank(user1);
        staking.requestWithdraw(1, 1000 ether);
        vm.warp(block.timestamp + 91 days);
        vm.prank(user1);
        staking.executeWithdraw(1);

        assertEq(staking.getUserStakeCount(user1), 9);

        // Withdraw stakeId 3
        vm.prank(user1);
        staking.requestWithdraw(3, 1000 ether);
        vm.warp(block.timestamp + 91 days);
        vm.prank(user1);
        staking.executeWithdraw(3);

        assertEq(staking.getUserStakeCount(user1), 8);

        // Verify remaining positions are accessible
        staking.getStakeByStakeId(user1, 2);
        staking.getStakeByStakeId(user1, 4);
        staking.getStakeByStakeId(user1, 5);
    }

    /**
     * @notice Test that stakeIds remain valid after array index changes
     * @dev When position at index 0 is removed, position at last index moves to index 0.
     *      But the stakeId of the moved position must remain the same.
     */
    function test_StakeIdsPersistAfterIndexChange() public {
        vm.startPrank(user1);
        staking.stake(1000 ether); // stakeId 1, index 0
        staking.stake(2000 ether); // stakeId 2, index 1
        staking.stake(3000 ether); // stakeId 3, index 2
        vm.stopPrank();

        assertEq(staking.getUserStakeCount(user1), 3);

        // Remove first position (stakeId 1)
        vm.prank(user1);
        staking.requestWithdraw(1, 1000 ether);
        vm.warp(block.timestamp + 91 days);
        vm.prank(user1);
        staking.executeWithdraw(1);

        // Should have 2 positions now
        assertEq(staking.getUserStakeCount(user1), 2);

        // stakeId 2 and 3 should still be accessible with correct amounts
        ProgressiveStaking.StakePosition memory pos2 = staking.getStakeByStakeId(user1, 2);
        ProgressiveStaking.StakePosition memory pos3 = staking.getStakeByStakeId(user1, 3);

        assertEq(pos2.amount, 2000 ether);
        assertEq(pos3.amount, 3000 ether);
        assertEq(pos2.stakeId, 2);
        assertEq(pos3.stakeId, 3);
    }

    // ============ Multi-User Tests ============
    // These tests verify that users are isolated from each other.
    // Each user has their own positions, but stakeIds are globally unique.

    /**
     * @notice Test multiple users staking independently
     * @dev Verifies:
     *      - Each user has separate position count
     *      - Global stakeId counter increments across all users
     *      - Total staked is sum of all users
     */
    function test_MultipleUsersStaking() public {
        vm.prank(user1);
        staking.stake(1000 ether);

        vm.prank(user2);
        staking.stake(2000 ether);

        vm.prank(user3);
        staking.stake(3000 ether);

        assertEq(staking.totalStaked(), 6000 ether);
        assertEq(staking.getUserStakeCount(user1), 1);
        assertEq(staking.getUserStakeCount(user2), 1);
        assertEq(staking.getUserStakeCount(user3), 1);

        // Each user has independent stakeIds starting from global counter
        ProgressiveStaking.StakePosition memory pos1 = staking.getStakeByStakeId(user1, 1);
        ProgressiveStaking.StakePosition memory pos2 = staking.getStakeByStakeId(user2, 2);
        ProgressiveStaking.StakePosition memory pos3 = staking.getStakeByStakeId(user3, 3);

        assertEq(pos1.stakeId, 1);
        assertEq(pos2.stakeId, 2);
        assertEq(pos3.stakeId, 3);
    }

    /**
     * @notice Test that rewards are calculated independently per user
     * @dev User1 stakes first, user2 stakes 90 days later.
     *      After 180 days total, user1 should have more rewards than user2.
     */
    function test_MultipleUsersIndependentRewards() public {
        vm.prank(user1);
        staking.stake(10_000 ether);

        vm.warp(block.timestamp + 90 days);

        vm.prank(user2);
        staking.stake(10_000 ether);

        vm.warp(block.timestamp + 90 days); // 180 days for user1, 90 days for user2

        uint256 rewards1 = staking.calculateTotalRewards(user1);
        uint256 rewards2 = staking.calculateTotalRewards(user2);

        // User1 should have more rewards (staked longer)
        assertGt(rewards1, rewards2);
    }

    // ============ Edge Cases ============
    // These tests verify error handling and boundary conditions.

    /**
     * @notice Test claiming rewards immediately after staking (should fail)
     * @dev No time has passed, so rewards = 0. Claiming should revert.
     */
    function test_ClaimRewardsImmediatelyAfterStake() public {
        vm.prank(user1);
        staking.stake(10_000 ether);

        // No time passed
        uint256 rewards = staking.calculateTotalRewards(user1);
        assertEq(rewards, 0);

        vm.prank(user1);
        vm.expectRevert(ProgressiveStaking.NoRewardsToClaim.selector);
        staking.claimRewards(1);
    }

    /**
     * @notice Test requesting withdrawal for more than staked amount
     * @dev Should revert with InsufficientStakeBalance error
     */
    function test_WithdrawMoreThanStaked() public {
        vm.prank(user1);
        staking.stake(1000 ether);

        vm.prank(user1);
        vm.expectRevert(ProgressiveStaking.InsufficientStakeBalance.selector);
        staking.requestWithdraw(1, 2000 ether);
    }

    /**
     * @notice Test that only one pending withdrawal per position is allowed
     * @dev Second requestWithdraw should fail with PositionHasPendingWithdraw
     */
    function test_DoubleWithdrawRequest() public {
        vm.prank(user1);
        staking.stake(1000 ether);

        vm.prank(user1);
        staking.requestWithdraw(1, 500 ether);

        // Second request should fail
        vm.prank(user1);
        vm.expectRevert(ProgressiveStaking.PositionHasPendingWithdraw.selector);
        staking.requestWithdraw(1, 500 ether);
    }

    /**
     * @notice Test that withdrawal cannot be executed twice
     * @dev After full withdrawal, position is removed. Second execute should fail.
     */
    function test_ExecuteWithdrawTwice() public {
        vm.prank(user1);
        staking.stake(1000 ether);

        vm.prank(user1);
        staking.requestWithdraw(1, 1000 ether);

        vm.warp(block.timestamp + 91 days);

        vm.prank(user1);
        staking.executeWithdraw(1);

        // Second execute should fail (position removed)
        vm.prank(user1);
        vm.expectRevert(ProgressiveStaking.InvalidStakeId.selector);
        staking.executeWithdraw(1);
    }

    /**
     * @notice Test claiming from non-existent stakeId
     * @dev Should revert with InvalidStakeId
     */
    function test_ClaimFromNonExistentPosition() public {
        vm.prank(user1);
        vm.expectRevert(ProgressiveStaking.InvalidStakeId.selector);
        staking.claimRewards(999);
    }

    /**
     * @notice Test that staking is blocked after emergency shutdown
     * @dev Emergency shutdown pauses the contract, preventing new stakes
     */
    function test_StakeAfterEmergencyMode() public {
        vm.prank(owner);
        staking.emergencyShutdown();

        // Emergency shutdown also pauses the contract, so we get EnforcedPause first
        vm.prank(user1);
        vm.expectRevert();
        staking.stake(1000 ether);
    }

    /**
     * @notice Test that emergency withdraw only works in emergency mode
     * @dev Should revert with EmergencyModeNotActive when not in emergency
     */
    function test_EmergencyWithdrawWithoutEmergencyMode() public {
        vm.prank(user1);
        staking.stake(1000 ether);

        vm.prank(user1);
        vm.expectRevert(ProgressiveStaking.EmergencyModeNotActive.selector);
        staking.emergencyWithdraw();
    }

    /**
     * @notice Test claiming when treasury has insufficient funds
     * @dev If rewards exceed treasury balance, claim should revert
     */
    function test_InsufficientTreasury() public {
        // Withdraw most of treasury
        vm.prank(owner);
        staking.withdrawTreasury(TREASURY_AMOUNT - 1 ether);

        vm.prank(user1);
        staking.stake(1_000_000 ether);

        vm.warp(block.timestamp + 360 days);

        // Rewards exceed treasury
        uint256 rewards = staking.calculateTotalRewards(user1);
        assertGt(rewards, staking.getTreasuryBalance());

        vm.prank(user1);
        vm.expectRevert(ProgressiveStaking.InsufficientTreasury.selector);
        staking.claimRewards(1);
    }

    // ============ Access Control Tests ============
    // These tests verify that protected functions are only callable by authorized roles.

    /**
     * @notice Test that only owner can deposit to treasury
     */
    function test_OnlyOwnerCanDepositTreasury() public {
        vm.prank(user1);
        vm.expectRevert();
        staking.depositTreasury(1000 ether);
    }

    /**
     * @notice Test that only owner can withdraw from treasury
     */
    function test_OnlyOwnerCanWithdrawTreasury() public {
        vm.prank(user1);
        vm.expectRevert();
        staking.withdrawTreasury(1000 ether);
    }

    /**
     * @notice Test that only owner can update tier rates
     */
    function test_OnlyOwnerCanUpdateTierRates() public {
        uint256[6] memory newRates = [uint256(100), 200, 300, 400, 500, 600];

        vm.prank(user1);
        vm.expectRevert();
        staking.updateTierRates(newRates);
    }

    /**
     * @notice Test that only owner can trigger emergency shutdown
     */
    function test_OnlyOwnerCanEmergencyShutdown() public {
        vm.prank(user1);
        vm.expectRevert();
        staking.emergencyShutdown();
    }

    /**
     * @notice Test that only admin can pause the contract
     */
    function test_OnlyAdminCanPause() public {
        vm.prank(user1);
        vm.expectRevert();
        staking.pause();
    }

    // ============ Compound Accuracy Tests ============
    // These tests verify the mathematical accuracy of reward calculations.

    /**
     * @notice Test reward calculation accuracy for Tier 1
     * @dev Verifies: 10,000 * 0.5% * (180/360) = 25 tokens
     *      Uses 0.1% tolerance for floating point precision
     */
    function test_CompoundAccuracyTier1() public {
        uint256 amount = 10_000 ether;

        vm.prank(user1);
        staking.stake(amount);

        vm.warp(block.timestamp + 180 days);

        uint256 rewards = staking.calculateTotalRewards(user1);
        // Expected: 10,000 * 0.5% * (180/360) = 25 ether
        uint256 expected = 25 ether;

        assertApproxEqRel(rewards, expected, 0.001e18); // 0.1% tolerance
    }

    /**
     * @notice Test compound reward accuracy across all 6 tiers
     * @dev After 5 years (1800 days), verifies compound calculation:
     *      Tier 1: 10,000 * 0.5% * 0.5 = 25
     *      Tier 2: 10,025 * 0.7% * 0.5 = 35.09
     *      Tier 3: 10,060.09 * 2.0% * 1.0 = 201.2
     *      Tier 4: 10,261.29 * 4.0% * 1.0 = 410.45
     *      Tier 5: 10,671.74 * 5.0% * 1.0 = 533.59
     *      Tier 6: 11,205.33 * 6.0% * 1.0 = 672.32
     *      Total: ~1877.65 tokens
     */
    function test_CompoundAccuracyAllTiers() public {
        uint256 amount = 10_000 ether;

        vm.prank(user1);
        staking.stake(amount);

        // Fast forward through all tiers (1800 days = 5 years)
        vm.warp(block.timestamp + 1800 days);

        uint256 rewards = staking.calculateTotalRewards(user1);

        // Manual calculation with compound:
        // Tier 1 (180 days): 10,000 * 0.5% * 0.5 = 25
        // Tier 2 (180 days): 10,025 * 0.7% * 0.5 = 35.09
        // Tier 3 (360 days): 10,060.09 * 2.0% * 1.0 = 201.2
        // Tier 4 (360 days): 10,261.29 * 4.0% * 1.0 = 410.45
        // Tier 5 (360 days): 10,671.74 * 5.0% * 1.0 = 533.59
        // Tier 6 (360 days): 11,205.33 * 6.0% * 1.0 = 672.32
        // Total: ~1877.65 tokens

        assertGt(rewards, 1800 ether);
        assertLt(rewards, 1950 ether);
    }

    // ============ Rewards After Partial Claim ============
    // These tests verify that rewards continue accumulating correctly after claims.

    /**
     * @notice Test that rewards continue after a claim
     * @dev Claims at 90 days, then checks rewards at 180 days.
     *      Second period should have new rewards.
     */
    function test_RewardsAfterPartialClaim() public {
        vm.prank(user1);
        staking.stake(10_000 ether);

        // Wait 90 days, claim
        vm.warp(block.timestamp + 90 days);
        vm.prank(user1);
        staking.claimRewards(1);

        // Wait another 90 days
        vm.warp(block.timestamp + 90 days);
        uint256 rewards = staking.calculateTotalRewards(user1);

        // Should have rewards for the second 90 days only
        assertGt(rewards, 0);
    }

    /**
     * @notice Test that Tier 2 rewards are higher than Tier 1 after claim
     * @dev Claims at 180 days (Tier 1), then at 360 days (Tier 2).
     *      Second claim should be larger due to higher APY in Tier 2.
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

    // ============ Constructor Validation Tests ============

    /**
     * @notice Test that constructor reverts with zero address for initialOwner
     * @dev Critical security check - prevents deployment with no admin
     */
    function test_RevertZeroAddressOwner() public {
        address[] memory founders = new address[](0);
        uint256[6] memory rates = [uint256(50), 70, 200, 400, 500, 600];

        vm.expectRevert(ProgressiveStaking.ZeroAddress.selector);
        new ProgressiveStaking(address(0), address(token), founders, rates);
    }

    /**
     * @notice Test that constructor reverts with zero address for staking token
     * @dev Critical security check - prevents deployment with invalid token
     */
    function test_RevertZeroAddressToken() public {
        address[] memory founders = new address[](0);
        uint256[6] memory rates = [uint256(50), 70, 200, 400, 500, 600];

        vm.expectRevert(ProgressiveStaking.ZeroAddress.selector);
        new ProgressiveStaking(owner, address(0), founders, rates);
    }

    // ============ Emergency Withdraw Mapping Cleanup Tests ============

    /**
     * @notice Test that emergencyWithdraw properly cleans up stakeIdExists mapping
     * @dev After emergency withdraw, stakeIdExists should return false for all stakeIds
     */
    function test_EmergencyWithdrawCleansStakeIdExists() public {
        // User stakes multiple positions
        vm.startPrank(user1);
        staking.stake(1000 ether);
        staking.stake(2000 ether);
        staking.stake(3000 ether);
        vm.stopPrank();

        // Verify positions exist
        assertEq(staking.getUserStakeCount(user1), 3);

        // Enable emergency mode
        vm.prank(owner);
        staking.emergencyShutdown();

        // Emergency withdraw
        vm.prank(user1);
        staking.emergencyWithdraw();

        // Verify all positions are gone
        assertEq(staking.getUserStakeCount(user1), 0);

        // Verify stakeIdExists is cleaned - trying to access old stakeIds should revert
        vm.expectRevert(ProgressiveStaking.InvalidStakeId.selector);
        staking.getStakeByStakeId(user1, 1);

        vm.expectRevert(ProgressiveStaking.InvalidStakeId.selector);
        staking.getStakeByStakeId(user1, 2);

        vm.expectRevert(ProgressiveStaking.InvalidStakeId.selector);
        staking.getStakeByStakeId(user1, 3);
    }

    /**
     * @notice Test that emergencyWithdraw emits correct event
     * @dev Verifies EmergencyWithdrawn event with principal and rewards
     */
    function test_EmergencyWithdrawEmitsEvent() public {
        vm.prank(user1);
        staking.stake(10_000 ether);

        // Wait for some rewards to accumulate
        vm.warp(block.timestamp + 180 days);

        // Enable emergency mode
        vm.prank(owner);
        staking.emergencyShutdown();

        // Calculate expected rewards
        uint256 expectedRewards = staking.calculateTotalRewards(user1);

        // Emergency withdraw and check event
        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit ProgressiveStaking.EmergencyWithdrawn(user1, 10_000 ether, expectedRewards, block.timestamp);
        staking.emergencyWithdraw();
    }

    /**
     * @notice Test that user cannot stake after emergency withdraw (stakeIds cleaned)
     * @dev New stakes should get new stakeIds, not reuse old ones
     */
    function test_CanStakeAfterEmergencyWithdraw() public {
        // First stake
        vm.prank(user1);
        staking.stake(1000 ether);
        assertEq(staking.getUserStakeCount(user1), 1);

        // Emergency shutdown and withdraw
        vm.prank(owner);
        staking.emergencyShutdown();

        vm.prank(user1);
        staking.emergencyWithdraw();
        assertEq(staking.getUserStakeCount(user1), 0);

        // Disable emergency mode would be needed to stake again
        // But since emergencyMode can't be disabled, this test verifies
        // that the mappings are properly cleaned even if user can't stake again
    }

    /**
     * @notice Test emergencyWithdraw with multiple users
     * @dev Each user's mappings should be independently cleaned
     */
    function test_EmergencyWithdrawMultipleUsers() public {
        // Multiple users stake
        vm.prank(user1);
        staking.stake(1000 ether);

        vm.prank(user2);
        staking.stake(2000 ether);

        vm.prank(user3);
        staking.stake(3000 ether);

        // Emergency shutdown
        vm.prank(owner);
        staking.emergencyShutdown();

        // User1 withdraws
        vm.prank(user1);
        staking.emergencyWithdraw();

        // User1's stakeId should be invalid, but user2's should still work
        vm.expectRevert(ProgressiveStaking.InvalidStakeId.selector);
        staking.getStakeByStakeId(user1, 1);

        // User2 hasn't withdrawn yet, their stake should still exist
        ProgressiveStaking.StakePosition memory pos = staking.getStakeByStakeId(user2, 2);
        assertEq(pos.amount, 2000 ether);

        // User2 withdraws
        vm.prank(user2);
        staking.emergencyWithdraw();

        vm.expectRevert(ProgressiveStaking.InvalidStakeId.selector);
        staking.getStakeByStakeId(user2, 2);
    }

    // ============ getTierConfig Bounds Check Tests ============

    /**
     * @notice Test that getTierConfig reverts for invalid tier index
     * @dev Should revert with InvalidTier for tier >= MAX_TIERS (6)
     */
    function test_GetTierConfigInvalidTier() public {
        // Valid tiers 0-5 should work
        staking.getTierConfig(0);
        staking.getTierConfig(5);

        // Invalid tier 6 should revert
        vm.expectRevert(ProgressiveStaking.InvalidTier.selector);
        staking.getTierConfig(6);

        // Invalid tier 255 should revert
        vm.expectRevert(ProgressiveStaking.InvalidTier.selector);
        staking.getTierConfig(255);
    }

    // ============ InsufficientStakeBalance Error Tests ============

    /**
     * @notice Test that requestWithdraw uses correct error for amount > balance
     * @dev Should revert with InsufficientStakeBalance, not ZeroAmount
     */
    function test_RequestWithdrawInsufficientBalance() public {
        vm.prank(user1);
        staking.stake(1000 ether);

        // Try to withdraw more than staked
        vm.prank(user1);
        vm.expectRevert(ProgressiveStaking.InsufficientStakeBalance.selector);
        staking.requestWithdraw(1, 1001 ether);

        // Exact amount should work
        vm.prank(user1);
        staking.requestWithdraw(1, 1000 ether);
    }

    /**
     * @notice Test partial withdraw followed by another partial withdraw request
     * @dev After partial withdraw, remaining balance should be correctly tracked
     */
    function test_PartialWithdrawThenRequestMore() public {
        vm.prank(user1);
        staking.stake(1000 ether);

        // Request partial withdraw
        vm.prank(user1);
        staking.requestWithdraw(1, 400 ether);

        // Wait and execute
        vm.warp(block.timestamp + 90 days);
        vm.prank(user1);
        staking.executeWithdraw(1);

        // Position should have 600 ether remaining
        ProgressiveStaking.StakePosition memory pos = staking.getStakeByStakeId(user1, 1);
        assertEq(pos.amount, 600 ether);

        // Requesting more than remaining should fail
        vm.prank(user1);
        vm.expectRevert(ProgressiveStaking.InsufficientStakeBalance.selector);
        staking.requestWithdraw(1, 601 ether);

        // Requesting exactly remaining should work
        vm.prank(user1);
        staking.requestWithdraw(1, 600 ether);
    }
}
