// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ProgressiveStaking} from "../src/ProgressiveStaking.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";

/**
 * @title ProgressiveStakingTest
 * @notice Core test suite for ProgressiveStaking contract
 * @dev Tests cover basic functionality: staking, rewards, withdrawals, and admin operations.
 *
 * Test Categories:
 * - Stake Tests: Creating and managing stake positions
 * - Rewards Tests: Calculating and claiming rewards across tiers
 * - Withdraw Tests: 90-day notice period withdrawal flow
 * - Admin Tests: Treasury management, tier rates, emergency functions
 * - Tier Tests: Tier progression based on staking duration
 * - Edge Cases: Compound rewards across multiple tiers
 *
 * Test Environment Setup:
 * - Mock ERC20 token deployed for staking
 * - Owner, 2 regular users, and 1 founder address
 * - Treasury pre-funded with 100,000 tokens
 * - Tier rates: 0.5%, 0.7%, 2%, 4%, 5%, 6% (in basis points: 50, 70, 200, 400, 500, 600)
 */
contract ProgressiveStakingTest is Test {
    ProgressiveStaking public staking;
    ERC20Mock public token;

    address public owner = makeAddr("owner");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public founder = makeAddr("founder");

    uint256 public constant INITIAL_BALANCE = 1_000_000 ether;
    uint256 public constant TREASURY_AMOUNT = 100_000 ether;

    // Tier rates in basis points (50 = 0.5%, 100 = 1%, etc.)
    uint256[6] public tierRates = [uint256(50), 70, 200, 400, 500, 600];

    /**
     * @notice Sets up the test environment before each test
     * @dev Deploys contracts, mints tokens, funds treasury, and approves spending
     */
    function setUp() public {
        // Deploy mock token
        token = new ERC20Mock("Staking Token", "STK");

        // Setup founders array
        address[] memory founders = new address[](1);
        founders[0] = founder;

        // Deploy staking contract
        vm.prank(owner);
        staking = new ProgressiveStaking(owner, address(token), founders, tierRates);

        // Mint tokens to users
        token.mint(owner, INITIAL_BALANCE);
        token.mint(user1, INITIAL_BALANCE);
        token.mint(user2, INITIAL_BALANCE);
        token.mint(founder, INITIAL_BALANCE);

        // Owner deposits treasury
        vm.startPrank(owner);
        token.approve(address(staking), TREASURY_AMOUNT);
        staking.depositTreasury(TREASURY_AMOUNT);
        vm.stopPrank();

        // Users approve staking contract
        vm.prank(user1);
        token.approve(address(staking), type(uint256).max);

        vm.prank(user2);
        token.approve(address(staking), type(uint256).max);

        vm.prank(founder);
        token.approve(address(staking), type(uint256).max);
    }

    // ============ Stake Tests ============

    /**
     * @notice Test basic staking functionality
     * @dev Verifies that:
     *      - User can stake tokens successfully
     *      - Stake count increases correctly
     *      - Total staked amount is tracked
     *      - Position has correct stakeId and amount
     */
    function test_Stake() public {
        uint256 amount = 1000 ether;

        vm.prank(user1);
        staking.stake(amount);

        assertEq(staking.getUserStakeCount(user1), 1);
        assertEq(staking.totalStaked(), amount);

        ProgressiveStaking.StakePosition[] memory positions = staking.getStakeInfo(user1);
        assertEq(positions[0].amount, amount);
        assertEq(positions[0].stakeId, 1);
    }

    /**
     * @notice Test creating multiple stake positions
     * @dev Verifies that each stake creates a separate position with unique stakeId.
     *      User should have 3 positions totaling 6000 tokens.
     */
    function test_Stake_MultiplePositions() public {
        vm.startPrank(user1);
        staking.stake(1000 ether);
        staking.stake(2000 ether);
        staking.stake(3000 ether);
        vm.stopPrank();

        assertEq(staking.getUserStakeCount(user1), 3);
        assertEq(staking.totalStaked(), 6000 ether);
    }

    /**
     * @notice Test that staking zero amount reverts
     * @dev Contract should reject zero-amount stakes with ZeroAmount error
     */
    function test_Stake_RevertZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert(ProgressiveStaking.ZeroAmount.selector);
        staking.stake(0);
    }

    // ============ Rewards Tests ============

    /**
     * @notice Test reward calculation for Tier 1 (0-6 months, 0.5% APY)
     * @dev After 180 days with 10,000 tokens staked:
     *      Expected: 10,000 * 0.5% * (180/360) = 25 tokens
     */
    function test_CalculateRewards_Tier1() public {
        uint256 amount = 10_000 ether;

        vm.prank(user1);
        staking.stake(amount);

        // Fast forward 180 days (full Tier 1)
        vm.warp(block.timestamp + 180 days);

        uint256 rewards = staking.calculateTotalRewards(user1);
        // Expected: 10,000 * 0.5% * (180/360) = 25 tokens
        assertApproxEqRel(rewards, 25 ether, 0.01e18); // 1% tolerance
    }

    /**
     * @notice Test reward calculation spanning Tier 1 and Tier 2
     * @dev After 360 days with 10,000 tokens staked:
     *      Tier 1: 10,000 * 0.5% * 0.5 = 25 tokens
     *      Tier 2: 10,025 * 0.7% * 0.5 = 35.09 tokens (compounded)
     *      Total: ~60.09 tokens
     */
    function test_CalculateRewards_Tier2() public {
        uint256 amount = 10_000 ether;

        vm.prank(user1);
        staking.stake(amount);

        // Fast forward 360 days (Tier 1 + Tier 2)
        vm.warp(block.timestamp + 360 days);

        uint256 rewards = staking.calculateTotalRewards(user1);
        // Tier 1: 10,000 * 0.5% * 0.5 = 25
        // Tier 2: 10,025 * 0.7% * 0.5 = 35.0875
        // Total: ~60.09 tokens
        assertApproxEqRel(rewards, 60.0875 ether, 0.01e18);
    }

    /**
     * @notice Test claiming rewards from a specific position
     * @dev Verifies that:
     *      - User receives tokens after claiming
     *      - Rewards reset to 0 after claim
     *      - lastClaimTime is updated
     */
    function test_ClaimRewards() public {
        uint256 amount = 10_000 ether;

        vm.prank(user1);
        staking.stake(amount);

        vm.warp(block.timestamp + 180 days);

        uint256 balanceBefore = token.balanceOf(user1);

        vm.prank(user1);
        staking.claimRewards(1);

        uint256 balanceAfter = token.balanceOf(user1);
        assertGt(balanceAfter, balanceBefore);

        // After claim, rewards should be 0
        uint256 rewardsAfterClaim = staking.calculateTotalRewards(user1);
        assertEq(rewardsAfterClaim, 0);
    }

    /**
     * @notice Test claiming rewards from all positions at once
     * @dev User with multiple positions can claim all rewards in single transaction.
     *      More gas-efficient than claiming individually.
     */
    function test_ClaimAllRewards() public {
        vm.startPrank(user1);
        staking.stake(5000 ether);
        staking.stake(5000 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + 180 days);

        uint256 totalRewardsBefore = staking.calculateTotalRewards(user1);
        uint256 balanceBefore = token.balanceOf(user1);

        vm.prank(user1);
        staking.claimAllRewards();

        uint256 balanceAfter = token.balanceOf(user1);
        assertApproxEqRel(balanceAfter - balanceBefore, totalRewardsBefore, 0.01e18);
    }

    /**
     * @notice Test that founders receive no rewards
     * @dev Founder addresses are set at deployment and earn 0% APY.
     *      This is a special mode for project founders who stake without interest.
     */
    function test_FounderNoRewards() public {
        vm.prank(founder);
        staking.stake(10_000 ether);

        vm.warp(block.timestamp + 360 days);

        uint256 rewards = staking.calculateTotalRewards(founder);
        assertEq(rewards, 0);
    }

    // ============ Withdraw Tests ============

    /**
     * @notice Test requesting a withdrawal (starting 90-day notice period)
     * @dev Verifies that:
     *      - Withdraw request is created
     *      - availableAt is set to current time + 90 days
     *      - Request is stored in user's pending withdrawals
     */
    function test_RequestWithdraw() public {
        uint256 amount = 1000 ether;

        vm.prank(user1);
        staking.stake(amount);

        vm.prank(user1);
        staking.requestWithdraw(1, amount);

        ProgressiveStaking.WithdrawRequest[] memory requests = staking.getPendingWithdrawals(user1);
        assertEq(requests.length, 1);
        assertEq(requests[0].amount, amount);
        assertEq(requests[0].availableAt, block.timestamp + 90 days);
        assertEq(requests[0].executed, false);
        assertEq(requests[0].cancelled, false);
    }

    /**
     * @notice Test executing withdrawal after notice period
     * @dev Verifies that:
     *      - User receives staked tokens back
     *      - Any pending rewards are also claimed
     *      - Position is removed if fully withdrawn
     */
    function test_ExecuteWithdraw() public {
        uint256 amount = 1000 ether;

        vm.prank(user1);
        staking.stake(amount);

        vm.warp(block.timestamp + 10 days);

        vm.prank(user1);
        staking.requestWithdraw(1, amount);

        // Fast forward past notice period
        vm.warp(block.timestamp + 91 days);

        uint256 balanceBefore = token.balanceOf(user1);

        vm.prank(user1);
        staking.executeWithdraw(1);

        uint256 balanceAfter = token.balanceOf(user1);
        assertGt(balanceAfter, balanceBefore);
        assertEq(staking.getUserStakeCount(user1), 0);
    }

    /**
     * @notice Test that withdrawal fails before notice period ends
     * @dev 90-day notice period must pass before executeWithdraw succeeds.
     *      Attempting to withdraw at 89 days should revert with WithdrawNotReady.
     */
    function test_ExecuteWithdraw_RevertBeforeNoticePeriod() public {
        vm.prank(user1);
        staking.stake(1000 ether);

        vm.prank(user1);
        staking.requestWithdraw(1, 1000 ether);

        // Try to execute before notice period
        vm.warp(block.timestamp + 89 days);

        vm.prank(user1);
        vm.expectRevert(ProgressiveStaking.WithdrawNotReady.selector);
        staking.executeWithdraw(1);
    }

    /**
     * @notice Test cancelling a pending withdrawal request
     * @dev User can cancel withdrawal request before executing.
     *      Position remains intact and continues earning rewards.
     */
    function test_CancelWithdrawRequest() public {
        vm.prank(user1);
        staking.stake(1000 ether);

        vm.warp(block.timestamp + 10 days);

        vm.prank(user1);
        staking.requestWithdraw(1, 1000 ether);

        vm.prank(user1);
        staking.cancelWithdrawRequest(1);

        // Position should still exist
        assertEq(staking.getUserStakeCount(user1), 1);

        ProgressiveStaking.WithdrawRequest[] memory requests = staking.getPendingWithdrawals(user1);
        assertEq(requests.length, 1);
        assertEq(requests[0].executed, true);
        assertEq(requests[0].cancelled, true);

        uint256 rewardsAfterCancel = staking.calculateRewards(user1, 1);
        vm.warp(block.timestamp + 10 days);
        uint256 rewardsLater = staking.calculateRewards(user1, 1);
        assertGt(rewardsLater, rewardsAfterCancel);
    }

    function test_CancelWithdrawRequestResumesAccrualWhenTreasuryInsufficient() public {
        vm.prank(user1);
        staking.stake(1000 ether);

        vm.warp(block.timestamp + 30 days);

        vm.prank(user1);
        staking.requestWithdraw(1, 1000 ether);

        uint256 rewardsFrozen = staking.calculateRewards(user1, 1);
        assertGt(rewardsFrozen, 0);

        vm.startPrank(owner);
        staking.withdrawTreasury(TREASURY_AMOUNT);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);

        vm.prank(user1);
        staking.cancelWithdrawRequest(1);

        uint256 rewardsAfterCancel = staking.calculateRewards(user1, 1);
        assertEq(rewardsAfterCancel, rewardsFrozen);

        vm.warp(block.timestamp + 10 days);

        uint256 rewardsLater = staking.calculateRewards(user1, 1);
        assertGt(rewardsLater, rewardsAfterCancel);

        vm.startPrank(owner);
        token.approve(address(staking), rewardsLater);
        staking.depositTreasury(rewardsLater);
        vm.stopPrank();

        uint256 userBalanceBefore = token.balanceOf(user1);
        vm.prank(user1);
        staking.claimRewards(1);
        uint256 userBalanceAfter = token.balanceOf(user1);
        assertEq(userBalanceAfter - userBalanceBefore, rewardsLater);
    }

    function test_ClaimThenRequestThenCancelSameTimestampDoesNotStallAccrual() public {
        vm.prank(user1);
        staking.stake(1000 ether);

        vm.warp(block.timestamp + 10 days);

        vm.prank(user1);
        staking.claimRewards(1);

        vm.prank(user1);
        staking.requestWithdraw(1, 1000 ether);

        vm.prank(user1);
        staking.cancelWithdrawRequest(1);

        uint256 rewardsNow = staking.calculateRewards(user1, 1);
        assertEq(rewardsNow, 0);

        vm.warp(block.timestamp + 10 days);
        uint256 rewardsLater = staking.calculateRewards(user1, 1);
        assertGt(rewardsLater, 0);
    }

    function test_RewardsDoNotAccrueAfterWithdrawRequest() public {
        vm.prank(user1);
        staking.stake(1000 ether);

        vm.warp(block.timestamp + 30 days);

        vm.prank(user1);
        staking.requestWithdraw(1, 1000 ether);

        uint256 rewardsAtRequest = staking.calculateRewards(user1, 1);

        vm.warp(block.timestamp + 30 days);

        uint256 rewardsLater = staking.calculateRewards(user1, 1);
        assertEq(rewardsLater, rewardsAtRequest);
    }

    /**
     * @notice Test partial withdrawal from a position
     * @dev User can withdraw part of their stake.
     *      Remaining amount stays in the position and continues earning.
     */
    function test_PartialWithdraw() public {
        uint256 amount = 1000 ether;

        vm.prank(user1);
        staking.stake(amount);

        vm.prank(user1);
        staking.requestWithdraw(1, 500 ether);

        vm.warp(block.timestamp + 91 days);

        vm.prank(user1);
        staking.executeWithdraw(1);

        // Position should still exist with remaining amount
        assertEq(staking.getUserStakeCount(user1), 1);

        ProgressiveStaking.StakePosition memory position = staking.getStakeByStakeId(user1, 1);
        assertEq(position.amount, 500 ether);
    }

    function test_PartialWithdrawDoesNotLoseRewardsIfTreasuryInsufficient() public {
        uint256 amount = 1000 ether;

        vm.prank(user1);
        staking.stake(amount);

        vm.warp(block.timestamp + 100 days);

        vm.prank(user1);
        staking.requestWithdraw(1, 500 ether);

        uint256 rewardsAtRequest = staking.calculateRewards(user1, 1);
        assertGt(rewardsAtRequest, 0);

        vm.warp(block.timestamp + 91 days);

        vm.startPrank(owner);
        staking.withdrawTreasury(TREASURY_AMOUNT);
        token.approve(address(staking), 100 ether);
        vm.stopPrank();

        vm.prank(user1);
        staking.executeWithdraw(1);

        ProgressiveStaking.StakePosition memory afterPosition = staking.getStakeByStakeId(user1, 1);
        assertEq(afterPosition.amount, 500 ether);

        // Rewards that were accrued before requestWithdraw should remain claimable even if treasury was insufficient
        // during executeWithdraw.
        uint256 rewardsAfterExecute = staking.calculateRewards(user1, 1);
        assertGe(rewardsAfterExecute, rewardsAtRequest);

        uint256 userBalanceBefore = token.balanceOf(user1);

        vm.startPrank(owner);
        token.approve(address(staking), rewardsAfterExecute);
        staking.depositTreasury(rewardsAfterExecute);
        vm.stopPrank();

        vm.prank(user1);
        staking.claimRewards(1);

        uint256 userBalanceAfter = token.balanceOf(user1);
        assertGt(userBalanceAfter, userBalanceBefore);
    }

    // ============ Admin Tests ============

    /**
     * @notice Test depositing tokens to treasury
     * @dev Only owner can deposit. Treasury funds are used to pay rewards.
     */
    function test_DepositTreasury() public {
        uint256 additionalAmount = 50_000 ether;

        vm.startPrank(owner);
        token.approve(address(staking), additionalAmount);
        staking.depositTreasury(additionalAmount);
        vm.stopPrank();

        assertEq(staking.getTreasuryBalance(), TREASURY_AMOUNT + additionalAmount);
    }

    /**
     * @notice Test withdrawing tokens from treasury
     * @dev Only owner can withdraw unused treasury funds.
     */
    function test_WithdrawTreasury() public {
        uint256 withdrawAmount = 10_000 ether;

        vm.prank(owner);
        staking.withdrawTreasury(withdrawAmount);

        assertEq(staking.getTreasuryBalance(), TREASURY_AMOUNT - withdrawAmount);
    }

    /**
     * @notice Test updating tier interest rates
     * @dev Owner can adjust APY rates for all tiers.
     *      Rates are in basis points (100 = 1%).
     */
    function test_UpdateTierRates() public {
        uint256[6] memory newRates = [uint256(100), 200, 300, 400, 500, 600];

        vm.prank(owner);
        staking.updateTierRates(newRates);

        ProgressiveStaking.TierConfig memory tier0 = staking.getTierConfig(0);
        assertEq(tier0.rate, 100);
    }

    /**
     * @notice Test emergency shutdown functionality
     * @dev Owner can trigger emergency mode which:
     *      - Pauses normal operations
     *      - Allows users to withdraw immediately without notice period
     */
    function test_EmergencyShutdown() public {
        vm.prank(user1);
        staking.stake(1000 ether);

        vm.prank(owner);
        staking.emergencyShutdown();

        assertTrue(staking.emergencyMode());

        // User can emergency withdraw
        vm.prank(user1);
        staking.emergencyWithdraw();

        assertEq(staking.getUserStakeCount(user1), 0);
    }

    /**
     * @notice Test pausing the contract
     * @dev Admin can pause contract to prevent new stakes and claims.
     *      Useful for maintenance or security incidents.
     */
    function test_Pause() public {
        // Owner has DEFAULT_ADMIN_ROLE, can grant ADMIN_ROLE
        vm.startPrank(owner);
        staking.grantRole(staking.ADMIN_ROLE(), owner);
        staking.pause();
        vm.stopPrank();

        vm.prank(user1);
        vm.expectRevert();
        staking.stake(1000 ether);
    }

    // ============ Tier Tests ============

    /**
     * @notice Test tier progression over time
     * @dev Verifies correct tier assignment:
     *      - Day 0: Tier 1
     *      - Day 181: Tier 2
     *      - Day 361: Tier 3
     */
    function test_GetCurrentTier() public {
        vm.prank(user1);
        staking.stake(1000 ether);

        assertEq(staking.getCurrentTier(user1, 1), 1);

        vm.warp(block.timestamp + 181 days);
        assertEq(staking.getCurrentTier(user1, 1), 2);

        vm.warp(block.timestamp + 180 days); // 361 days total
        assertEq(staking.getCurrentTier(user1, 1), 3);
    }

    // ============ Edge Cases ============

    /**
     * @notice Test compound rewards accumulating across multiple tiers
     * @dev After 720 days (2 years), rewards compound through Tier 1, 2, and 3:
     *      Tier 1: 10,000 * 0.5% * 0.5 = 25 tokens
     *      Tier 2: 10,025 * 0.7% * 0.5 = 35.09 tokens
     *      Tier 3: 10,060.09 * 2.0% * 1.0 = 201.2 tokens
     *      Total: ~261.3 tokens
     */
    function test_RewardsAccumulateAcrossTiers() public {
        uint256 amount = 10_000 ether;

        vm.prank(user1);
        staking.stake(amount);

        // Fast forward 720 days (through Tier 1, 2, 3)
        vm.warp(block.timestamp + 720 days);

        uint256 rewards = staking.calculateTotalRewards(user1);

        // Rewards should be compounded across tiers
        // Tier 1: 10,000 * 0.5% * 0.5 = 25
        // Tier 2: 10,025 * 0.7% * 0.5 = 35.0875
        // Tier 3: 10,060.0875 * 2.0% * 1.0 = 201.20175
        // Total: ~261.3 tokens
        assertApproxEqRel(rewards, 261.29 ether, 0.01e18);
    }
}
