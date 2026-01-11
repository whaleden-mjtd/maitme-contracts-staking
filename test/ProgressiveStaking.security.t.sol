// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ProgressiveStakingBaseTest} from "./ProgressiveStaking.base.t.sol";
import {ProgressiveStaking} from "../src/ProgressiveStaking.sol";

/**
 * @title ProgressiveStakingSecurityTest
 * @notice Security and audit-related tests for ProgressiveStaking contract
 * @dev Tests access control, input validation, DoS prevention, and edge cases.
 *
 * Test Categories:
 * - Constructor validation (address(0), tier rates)
 * - Access control (roles, permissions)
 * - DoS attack prevention
 * - Emergency withdraw scenarios
 * - Edge cases and error handling
 */
contract ProgressiveStakingSecurityTest is ProgressiveStakingBaseTest {

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

    /**
     * @notice Test that constructor reverts with zero address founder
     * @dev Founders array should not contain address(0)
     */
    function test_RevertZeroAddressFounder() public {
        address[] memory founders = new address[](2);
        founders[0] = makeAddr("validFounder");
        founders[1] = address(0);
        uint256[6] memory rates = [uint256(50), 70, 200, 400, 500, 600];

        vm.expectRevert(ProgressiveStaking.ZeroAddress.selector);
        new ProgressiveStaking(owner, address(token), founders, rates);
    }

    /**
     * @notice Test that constructor validates tier rates
     * @dev Tier rates > RATE_PRECISION (10000) should revert
     */
    function test_RevertInvalidTierRatesInConstructor() public {
        address[] memory founders = new address[](0);
        uint256[6] memory rates = [uint256(50), 70, 200, 400, 500, 20000];

        vm.expectRevert(ProgressiveStaking.InvalidTierRates.selector);
        new ProgressiveStaking(owner, address(token), founders, rates);
    }

    // ============ Access Control Tests ============

    /**
     * @notice Test that only DEFAULT_ADMIN_ROLE can deposit treasury
     * @dev Non-admin should be rejected
     */
    function test_OnlyAdminCanDepositTreasury() public {
        token.mint(user1, 1000 ether);
        vm.prank(user1);
        token.approve(address(staking), 1000 ether);

        vm.prank(user1);
        vm.expectRevert();
        staking.depositTreasury(1000 ether);
    }

    /**
     * @notice Test that only DEFAULT_ADMIN_ROLE can withdraw treasury
     * @dev Non-admin should be rejected
     */
    function test_OnlyAdminCanWithdrawTreasury() public {
        vm.prank(user1);
        vm.expectRevert();
        staking.withdrawTreasury(100 ether);
    }

    /**
     * @notice Test that only DEFAULT_ADMIN_ROLE can update tier rates
     * @dev Non-admin should be rejected
     */
    function test_OnlyAdminCanUpdateTierRates() public {
        uint256[6] memory newRates = [uint256(100), 150, 250, 450, 550, 650];

        vm.prank(user1);
        vm.expectRevert();
        staking.updateTierRates(newRates);
    }

    /**
     * @notice Test that only DEFAULT_ADMIN_ROLE can trigger emergency shutdown
     * @dev Non-admin should be rejected
     */
    function test_OnlyAdminCanEmergencyShutdown() public {
        vm.prank(user1);
        vm.expectRevert();
        staking.emergencyShutdown();
    }

    /**
     * @notice Test that only ADMIN_ROLE can pause
     * @dev Non-admin should be rejected
     */
    function test_OnlyAdminCanPause() public {
        vm.prank(user1);
        vm.expectRevert();
        staking.pause();
    }

    /**
     * @notice Test that only ADMIN_ROLE can unpause
     * @dev Non-admin should be rejected
     */
    function test_OnlyAdminCanUnpause() public {
        vm.prank(owner);
        staking.pause();

        vm.prank(user1);
        vm.expectRevert();
        staking.unpause();
    }

    // ============ Emergency Withdraw Tests ============

    /**
     * @notice Test that emergencyWithdraw properly cleans up stakeIdExists mapping
     * @dev After emergency withdraw, stakeIdExists should return false for all stakeIds
     */
    function test_EmergencyWithdrawCleansStakeIdExists() public {
        vm.startPrank(user1);
        staking.stake(1000 ether);
        staking.stake(2000 ether);
        staking.stake(3000 ether);
        vm.stopPrank();

        assertEq(staking.getUserStakeCount(user1), 3);

        vm.prank(owner);
        staking.emergencyShutdown();

        vm.prank(user1);
        staking.emergencyWithdraw();

        assertEq(staking.getUserStakeCount(user1), 0);

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

        vm.warp(block.timestamp + 180 days);

        vm.prank(owner);
        staking.emergencyShutdown();

        uint256 expectedRewards = staking.calculateTotalRewards(user1);

        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit ProgressiveStaking.EmergencyWithdrawn(user1, 10_000 ether, expectedRewards, block.timestamp);
        staking.emergencyWithdraw();
    }

    /**
     * @notice Test that emergencyWithdraw reverts when user has no stakes
     * @dev Should revert with NoStakesToWithdraw
     */
    function test_EmergencyWithdrawNoStakes() public {
        vm.prank(owner);
        staking.emergencyShutdown();

        vm.prank(user1);
        vm.expectRevert(ProgressiveStaking.NoStakesToWithdraw.selector);
        staking.emergencyWithdraw();
    }

    /**
     * @notice Test emergencyWithdraw with multiple users
     * @dev Each user's mappings should be independently cleaned
     */
    function test_EmergencyWithdrawMultipleUsers() public {
        vm.prank(user1);
        staking.stake(1000 ether);

        vm.prank(user2);
        staking.stake(2000 ether);

        vm.prank(user3);
        staking.stake(3000 ether);

        vm.prank(owner);
        staking.emergencyShutdown();

        vm.prank(user1);
        staking.emergencyWithdraw();

        vm.expectRevert(ProgressiveStaking.InvalidStakeId.selector);
        staking.getStakeByStakeId(user1, 1);

        ProgressiveStaking.StakePosition memory pos = staking.getStakeByStakeId(user2, 2);
        assertEq(pos.amount, 2000 ether);

        vm.prank(user2);
        staking.emergencyWithdraw();

        vm.expectRevert(ProgressiveStaking.InvalidStakeId.selector);
        staking.getStakeByStakeId(user2, 2);
    }

    // ============ DoS Attack Prevention Tests ============

    /**
     * @notice Test that attacker cannot DoS other users via withdraw request spam
     * @dev With MAX_PENDING_WITHDRAWALS limit, attacker is limited to 10 pending requests
     */
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

    /**
     * @notice Test max pending withdrawals limit
     * @dev User should not be able to have more than MAX_PENDING_WITHDRAWALS
     */
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

    /**
     * @notice Test that executing withdrawal frees up pending slot
     * @dev After execute, user should be able to request another withdrawal
     */
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

    /**
     * @notice Test that cancelling withdrawal frees up pending slot
     * @dev After cancel, user should be able to request another withdrawal
     */
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

    /**
     * @notice Test O(1) pending withdraw check with mapping
     * @dev hasPendingWithdraw mapping should correctly track state
     */
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

    /**
     * @notice Test gas cost remains bounded with many withdraw requests
     * @dev Even with max pending withdrawals, gas should be reasonable
     */
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

    /**
     * @notice Test that multiple users don't affect each other's gas costs
     * @dev Each user's withdraw requests are independent
     */
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

    /**
     * @notice Test that large number of users doesn't cause global DoS
     * @dev Contract should handle many users without issues
     */
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

    // ============ Edge Cases Tests ============

    /**
     * @notice Test that getTierConfig reverts for invalid tier index
     * @dev Should revert with InvalidTier for tier >= MAX_TIERS (6)
     */
    function test_GetTierConfigInvalidTier() public {
        staking.getTierConfig(0);
        staking.getTierConfig(5);

        vm.expectRevert(ProgressiveStaking.InvalidTier.selector);
        staking.getTierConfig(6);

        vm.expectRevert(ProgressiveStaking.InvalidTier.selector);
        staking.getTierConfig(255);
    }

    /**
     * @notice Test that requestWithdraw uses correct error for amount > balance
     * @dev Should revert with InsufficientStakeBalance, not ZeroAmount
     */
    function test_RequestWithdrawInsufficientBalance() public {
        vm.prank(user1);
        staking.stake(1000 ether);

        vm.prank(user1);
        vm.expectRevert(ProgressiveStaking.InsufficientStakeBalance.selector);
        staking.requestWithdraw(1, 1001 ether);

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

        vm.prank(user1);
        staking.requestWithdraw(1, 400 ether);

        vm.warp(block.timestamp + 90 days);
        vm.prank(user1);
        staking.executeWithdraw(1);

        ProgressiveStaking.StakePosition memory pos = staking.getStakeByStakeId(user1, 1);
        assertEq(pos.amount, 600 ether);

        vm.prank(user1);
        vm.expectRevert(ProgressiveStaking.InsufficientStakeBalance.selector);
        staking.requestWithdraw(1, 601 ether);

        vm.prank(user1);
        staking.requestWithdraw(1, 600 ether);
    }

    /**
     * @notice Test claiming immediately after stake (0 rewards)
     * @dev Should revert with NoRewardsToClaim
     */
    function test_ClaimImmediatelyAfterStake() public {
        vm.prank(user1);
        staking.stake(10_000 ether);

        vm.prank(user1);
        vm.expectRevert(ProgressiveStaking.NoRewardsToClaim.selector);
        staking.claimRewards(1);
    }

    /**
     * @notice Test double withdrawal request for same position
     * @dev Should revert with PositionHasPendingWithdraw
     */
    function test_DoubleWithdrawRequest() public {
        vm.prank(user1);
        staking.stake(1000 ether);

        vm.prank(user1);
        staking.requestWithdraw(1, 500 ether);

        vm.prank(user1);
        vm.expectRevert(ProgressiveStaking.PositionHasPendingWithdraw.selector);
        staking.requestWithdraw(1, 300 ether);
    }

    /**
     * @notice Test insufficient treasury for rewards
     * @dev Should revert with InsufficientTreasury
     */
    function test_InsufficientTreasuryForRewards() public {
        // Withdraw most of treasury
        vm.prank(owner);
        staking.withdrawTreasury(TREASURY_AMOUNT - 1 ether);

        vm.prank(user1);
        staking.stake(1_000_000 ether);

        vm.warp(block.timestamp + 360 days);

        // Rewards should exceed remaining treasury
        uint256 rewards = staking.calculateTotalRewards(user1);
        assertGt(rewards, 1 ether);

        vm.prank(user1);
        vm.expectRevert(ProgressiveStaking.InsufficientTreasury.selector);
        staking.claimRewards(1);
    }

    /**
     * @notice Test founders don't earn rewards
     * @dev Founder's rewards should always be 0
     */
    function test_FounderNoRewards() public {
        vm.prank(founder);
        staking.stake(10_000 ether);

        vm.warp(block.timestamp + 360 days);

        uint256 rewards = staking.calculateTotalRewards(founder);
        assertEq(rewards, 0);

        vm.prank(founder);
        vm.expectRevert(ProgressiveStaking.NoRewardsToClaim.selector);
        staking.claimRewards(1);
    }
}
