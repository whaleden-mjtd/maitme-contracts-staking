// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ProgressiveStakingBaseTest} from "./ProgressiveStaking.base.t.sol";
import {ProgressiveStaking} from "../src/ProgressiveStaking.sol";

/**
 * @title ProgressiveStakingValidationTest
 * @notice Input validation and edge case tests for ProgressiveStaking contract
 * @dev Tests constructor validation, error handling, and view function edge cases
 */
contract ProgressiveStakingValidationTest is ProgressiveStakingBaseTest {

    // ============ Constructor Validation Tests ============

    /// @notice Test that constructor reverts with zero address for initialOwner
    function test_RevertZeroAddressOwner() public {
        address[] memory founders = new address[](0);
        uint256[6] memory rates = [uint256(50), 70, 200, 400, 500, 600];

        vm.expectRevert(ProgressiveStaking.ZeroAddress.selector);
        new ProgressiveStaking(address(0), address(token), founders, rates);
    }

    /// @notice Test that constructor reverts with zero address for staking token
    function test_RevertZeroAddressToken() public {
        address[] memory founders = new address[](0);
        uint256[6] memory rates = [uint256(50), 70, 200, 400, 500, 600];

        vm.expectRevert(ProgressiveStaking.ZeroAddress.selector);
        new ProgressiveStaking(owner, address(0), founders, rates);
    }

    /// @notice Test that constructor reverts with zero address founder
    function test_RevertZeroAddressFounder() public {
        address[] memory founders = new address[](2);
        founders[0] = makeAddr("validFounder");
        founders[1] = address(0);
        uint256[6] memory rates = [uint256(50), 70, 200, 400, 500, 600];

        vm.expectRevert(ProgressiveStaking.ZeroAddress.selector);
        new ProgressiveStaking(owner, address(token), founders, rates);
    }

    /// @notice Test that constructor validates tier rates
    function test_RevertInvalidTierRatesInConstructor() public {
        address[] memory founders = new address[](0);
        uint256[6] memory rates = [uint256(50), 70, 200, 400, 500, 20000];

        vm.expectRevert(ProgressiveStaking.InvalidTierRates.selector);
        new ProgressiveStaking(owner, address(token), founders, rates);
    }

    // ============ Edge Cases Tests ============

    /// @notice Test that getTierConfig reverts for invalid tier index
    function test_GetTierConfigInvalidTier() public {
        staking.getTierConfig(0);
        staking.getTierConfig(5);

        vm.expectRevert(ProgressiveStaking.InvalidTier.selector);
        staking.getTierConfig(6);

        vm.expectRevert(ProgressiveStaking.InvalidTier.selector);
        staking.getTierConfig(255);
    }

    /// @notice Test that requestWithdraw uses correct error for amount > balance
    function test_RequestWithdrawInsufficientBalance() public {
        vm.prank(user1);
        staking.stake(1000 ether);

        vm.prank(user1);
        vm.expectRevert(ProgressiveStaking.InsufficientStakeBalance.selector);
        staking.requestWithdraw(1, 1001 ether);

        vm.prank(user1);
        staking.requestWithdraw(1, 1000 ether);
    }

    /// @notice Test partial withdraw followed by another partial withdraw request
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

    /// @notice Test claiming immediately after stake (0 rewards)
    function test_ClaimImmediatelyAfterStake() public {
        vm.prank(user1);
        staking.stake(10_000 ether);

        vm.prank(user1);
        vm.expectRevert(ProgressiveStaking.NoRewardsToClaim.selector);
        staking.claimRewards(1);
    }

    /// @notice Test double withdrawal request for same position
    function test_DoubleWithdrawRequest() public {
        vm.prank(user1);
        staking.stake(1000 ether);

        vm.prank(user1);
        staking.requestWithdraw(1, 500 ether);

        vm.prank(user1);
        vm.expectRevert(ProgressiveStaking.PositionHasPendingWithdraw.selector);
        staking.requestWithdraw(1, 300 ether);
    }

    /// @notice Test insufficient treasury for rewards
    function test_InsufficientTreasuryForRewards() public {
        vm.prank(owner);
        staking.withdrawTreasury(TREASURY_AMOUNT - 1 ether);

        vm.prank(user1);
        staking.stake(1_000_000 ether);

        vm.warp(block.timestamp + 360 days);

        uint256 rewards = staking.calculateTotalRewards(user1);
        assertGt(rewards, 1 ether);

        vm.prank(user1);
        vm.expectRevert(ProgressiveStaking.InsufficientTreasury.selector);
        staking.claimRewards(1);
    }

    /// @notice Test founders don't earn rewards
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

    // ============ Treasury Edge Cases ============

    /// @notice Test withdrawTreasury reverts when amount exceeds balance
    function test_WithdrawTreasuryRevertsInsufficientBalance() public {
        uint256 treasuryBalance = staking.getTreasuryBalance();

        vm.prank(owner);
        vm.expectRevert(ProgressiveStaking.InsufficientTreasury.selector);
        staking.withdrawTreasury(treasuryBalance + 1);
    }

    /// @notice Test depositTreasury reverts with zero amount
    function test_DepositTreasuryRevertsZeroAmount() public {
        vm.prank(owner);
        vm.expectRevert(ProgressiveStaking.ZeroAmount.selector);
        staking.depositTreasury(0);
    }

    /// @notice Test withdrawTreasury reverts with zero amount
    function test_WithdrawTreasuryRevertsZeroAmount() public {
        vm.prank(owner);
        vm.expectRevert(ProgressiveStaking.ZeroAmount.selector);
        staking.withdrawTreasury(0);
    }

    // ============ View Functions Edge Cases ============

    /// @notice Test getStakeInfo returns empty array for user with no stakes
    function test_GetStakeInfoEmptyUser() public {
        ProgressiveStaking.StakePosition[] memory positions = staking.getStakeInfo(user1);
        assertEq(positions.length, 0);
    }

    /// @notice Test calculateTotalRewards returns 0 for user with no stakes
    function test_CalculateTotalRewardsEmptyUser() public {
        uint256 rewards = staking.calculateTotalRewards(user1);
        assertEq(rewards, 0);
    }

    /// @notice Test getUserStakeCount returns 0 for user with no stakes
    function test_GetUserStakeCountEmptyUser() public {
        uint256 count = staking.getUserStakeCount(user1);
        assertEq(count, 0);
    }

    /// @notice Test getActivePendingWithdrawals returns empty array when no pending
    function test_GetActivePendingWithdrawalsEmpty() public {
        ProgressiveStaking.WithdrawRequest[] memory active = staking.getActivePendingWithdrawals(user1);
        assertEq(active.length, 0);

        vm.prank(user1);
        staking.stake(1000 ether);

        active = staking.getActivePendingWithdrawals(user1);
        assertEq(active.length, 0);
    }

    /// @notice Test getPendingWithdrawals vs getActivePendingWithdrawals
    function test_GetPendingWithdrawalsVsActive() public {
        vm.startPrank(user1);
        staking.stake(1000 ether);
        staking.requestWithdraw(1, 500 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + 90 days);
        vm.prank(user1);
        staking.executeWithdraw(1);

        vm.prank(user1);
        staking.requestWithdraw(1, 200 ether);

        ProgressiveStaking.WithdrawRequest[] memory all = staking.getPendingWithdrawals(user1);
        assertEq(all.length, 2);

        ProgressiveStaking.WithdrawRequest[] memory active = staking.getActivePendingWithdrawals(user1);
        assertEq(active.length, 1);
        assertEq(active[0].amount, 200 ether);
    }

    /// @notice Test getActivePendingWithdrawals returns only non-executed requests
    function test_GetActivePendingWithdrawals() public {
        vm.startPrank(user1);
        staking.stake(1000 ether);
        staking.stake(2000 ether);
        staking.stake(3000 ether);

        staking.requestWithdraw(1, 500 ether);
        staking.requestWithdraw(2, 1000 ether);
        staking.requestWithdraw(3, 1500 ether);
        vm.stopPrank();

        ProgressiveStaking.WithdrawRequest[] memory active = staking.getActivePendingWithdrawals(user1);
        assertEq(active.length, 3);

        vm.warp(block.timestamp + 90 days);
        vm.prank(user1);
        staking.executeWithdraw(2);

        active = staking.getActivePendingWithdrawals(user1);
        assertEq(active.length, 2);

        vm.prank(user1);
        staking.cancelWithdrawRequest(1);

        active = staking.getActivePendingWithdrawals(user1);
        assertEq(active.length, 1);
        assertEq(active[0].stakeId, 3);
    }

    // ============ Token Balance Consistency Tests ============

    /// @notice Test contract token balance equals totalStaked + treasuryBalance
    function test_TokenBalanceConsistency() public {
        uint256 contractBalance = token.balanceOf(address(staking));
        assertEq(contractBalance, staking.totalStaked() + staking.getTreasuryBalance());

        vm.prank(user1);
        staking.stake(5000 ether);

        contractBalance = token.balanceOf(address(staking));
        assertEq(contractBalance, staking.totalStaked() + staking.getTreasuryBalance());

        vm.warp(block.timestamp + 180 days);
        vm.prank(user1);
        staking.claimRewards(1);

        contractBalance = token.balanceOf(address(staking));
        assertEq(contractBalance, staking.totalStaked() + staking.getTreasuryBalance());

        vm.prank(user1);
        staking.requestWithdraw(1, 2000 ether);
        vm.warp(block.timestamp + 90 days);
        vm.prank(user1);
        staking.executeWithdraw(1);

        contractBalance = token.balanceOf(address(staking));
        assertEq(contractBalance, staking.totalStaked() + staking.getTreasuryBalance());
    }
}
