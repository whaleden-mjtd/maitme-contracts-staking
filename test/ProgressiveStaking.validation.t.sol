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

        ProgressiveStaking.WithdrawRequest[] memory requests = staking.getActivePendingWithdrawals(user1);
        assertEq(requests.length, 1);
        uint256 withdrawStakeId = requests[0].stakeId;

        vm.warp(block.timestamp + 90 days);
        vm.prank(user1);
        staking.executeWithdraw(withdrawStakeId);

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

        ProgressiveStaking.WithdrawRequest[] memory requests = staking.getActivePendingWithdrawals(user1);
        assertEq(requests.length, 1);
        uint256 withdrawStakeId = requests[0].stakeId;

        vm.prank(user1);
        vm.expectRevert(ProgressiveStaking.PositionHasPendingWithdraw.selector);
        staking.requestWithdraw(withdrawStakeId, 300 ether);
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
    function test_GetStakeInfoEmptyUser() public view {
        ProgressiveStaking.StakePosition[] memory positions = staking.getStakeInfo(user1);
        assertEq(positions.length, 0);
    }

    /// @notice Test calculateTotalRewards returns 0 for user with no stakes
    function test_CalculateTotalRewardsEmptyUser() public view {
        uint256 rewards = staking.calculateTotalRewards(user1);
        assertEq(rewards, 0);
    }

    /// @notice Test getUserStakeCount returns 0 for user with no stakes
    function test_GetUserStakeCountEmptyUser() public view {
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

        ProgressiveStaking.WithdrawRequest[] memory firstRequests = staking.getActivePendingWithdrawals(user1);
        assertEq(firstRequests.length, 1);
        uint256 firstWithdrawStakeId = firstRequests[0].stakeId;

        vm.warp(block.timestamp + 90 days);
        vm.prank(user1);
        staking.executeWithdraw(firstWithdrawStakeId);

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

        uint256 withdrawStakeId1 = active[0].stakeId;
        uint256 withdrawStakeId2 = active[1].stakeId;
        uint256 withdrawStakeId3 = active[2].stakeId;

        vm.warp(block.timestamp + 90 days);
        vm.prank(user1);
        staking.executeWithdraw(withdrawStakeId2);

        ProgressiveStaking.WithdrawRequest[] memory allAfterExec = staking.getPendingWithdrawals(user1);
        for (uint256 i = 0; i < allAfterExec.length; i++) {
            if (allAfterExec[i].stakeId == withdrawStakeId2) {
                assertEq(allAfterExec[i].executed, true);
                assertEq(allAfterExec[i].cancelled, false);
            }
        }

        active = staking.getActivePendingWithdrawals(user1);
        assertEq(active.length, 2);

        vm.prank(user1);
        staking.cancelWithdrawRequest(withdrawStakeId1);

        ProgressiveStaking.WithdrawRequest[] memory allAfterCancel = staking.getPendingWithdrawals(user1);
        for (uint256 i = 0; i < allAfterCancel.length; i++) {
            if (allAfterCancel[i].stakeId == withdrawStakeId1) {
                assertEq(allAfterCancel[i].executed, true);
                assertEq(allAfterCancel[i].cancelled, true);
            }
        }

        active = staking.getActivePendingWithdrawals(user1);
        assertEq(active.length, 1);
        assertEq(active[0].stakeId, withdrawStakeId3);
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

        ProgressiveStaking.WithdrawRequest[] memory requests = staking.getActivePendingWithdrawals(user1);
        assertEq(requests.length, 1);
        uint256 withdrawStakeId = requests[0].stakeId;
        vm.warp(block.timestamp + 90 days);
        vm.prank(user1);
        staking.executeWithdraw(withdrawStakeId);

        contractBalance = token.balanceOf(address(staking));
        assertEq(contractBalance, staking.totalStaked() + staking.getTreasuryBalance());
    }

    // ============ MIN_STAKE_AMOUNT Tests ============

    /// @notice Test that stake reverts when amount is below MIN_STAKE_AMOUNT
    function test_StakeRevertsWhenBelowMinimum() public {
        uint256 minAmount = staking.MIN_STAKE_AMOUNT();

        vm.prank(user1);
        vm.expectRevert(ProgressiveStaking.StakeAmountTooLow.selector);
        staking.stake(minAmount - 1);
    }

    /// @notice Test that stake works at exactly MIN_STAKE_AMOUNT
    function test_StakeAtExactMinimum() public {
        uint256 minAmount = staking.MIN_STAKE_AMOUNT();

        vm.prank(user1);
        staking.stake(minAmount);

        assertEq(staking.getUserStakeCount(user1), 1);
    }

    /// @notice Test dust amount (1 wei) is rejected
    function test_DustAmountStakeRejected() public {
        vm.prank(user1);
        vm.expectRevert(ProgressiveStaking.StakeAmountTooLow.selector);
        staking.stake(1);
    }

    /// @notice Test requestWithdraw reverts if it would leave a non-zero remainder below MIN_STAKE_AMOUNT
    function test_RequestWithdrawRevertsIfRemainingBelowMinimum() public {
        uint256 minAmount = staking.MIN_STAKE_AMOUNT();

        // Stake exactly MIN_STAKE_AMOUNT
        vm.prank(user1);
        staking.stake(minAmount);

        // Withdraw minAmount - 1 leaves 1 wei remaining (below minimum) -> should revert
        vm.prank(user1);
        vm.expectRevert(ProgressiveStaking.StakeAmountTooLow.selector);
        staking.requestWithdraw(1, minAmount - 1);
    }

    function test_StakeRevertsIfTooManyStakes() public {
        uint256 maxStakes = staking.MAX_STAKES_PER_ADDRESS();
        uint256 maxPending = staking.MAX_PENDING_WITHDRAWALS();
        uint256 minAmount = staking.MIN_STAKE_AMOUNT();
        uint256 effectiveMaxStakes = maxStakes - maxPending - 1;

        vm.startPrank(user1);
        for (uint256 i = 0; i < effectiveMaxStakes; i++) {
            staking.stake(minAmount);
        }

        vm.expectRevert(ProgressiveStaking.TooManyStakes.selector);
        staking.stake(minAmount);
        vm.stopPrank();
    }

    // ============ Long-term Array Growth Tests ============

    /// @notice Test withdraw request array growth over time
    function test_WithdrawRequestArrayGrowth() public {
        // Create 20 stakes
        vm.startPrank(user1);
        for (uint256 i = 0; i < 20; i++) {
            staking.stake(100 ether);
        }
        vm.stopPrank();

        // Create and execute 10 withdraw requests (fills up pending limit)
        for (uint256 cycle = 0; cycle < 5; cycle++) {
            // Request withdrawals for 2 positions per cycle
            vm.startPrank(user1);
            staking.requestWithdraw(cycle * 2 + 1, 100 ether);
            staking.requestWithdraw(cycle * 2 + 2, 100 ether);
            vm.stopPrank();

            vm.warp(block.timestamp + 90 days);

            // Execute them
            vm.startPrank(user1);
            staking.executeWithdraw(cycle * 2 + 1);
            staking.executeWithdraw(cycle * 2 + 2);
            vm.stopPrank();
        }

        // Array should have 10 requests (all executed)
        ProgressiveStaking.WithdrawRequest[] memory allRequests = staking.getPendingWithdrawals(user1);
        assertEq(allRequests.length, 10);

        // But active count should be 0
        assertEq(staking.pendingWithdrawCount(user1), 0);

        // getActivePendingWithdrawals should return empty
        ProgressiveStaking.WithdrawRequest[] memory activeRequests = staking.getActivePendingWithdrawals(user1);
        assertEq(activeRequests.length, 0);

        // User can still create new requests
        vm.prank(user1);
        staking.requestWithdraw(11, 100 ether);
        assertEq(staking.pendingWithdrawCount(user1), 1);
    }

    // ============ Branch Coverage Tests ============

    /// @notice Test stake reverts in emergency mode (paused first, then emergency check)
    function test_StakeRevertsInEmergencyMode() public {
        // Set emergency mode without pausing to test EmergencyModeActive error
        // Since emergencyShutdown also pauses, we need to test the order of checks
        // The contract checks: whenNotPaused first, then emergencyMode
        // So when emergencyShutdown is called, it pauses first - EnforcedPause is thrown
        vm.prank(owner);
        staking.emergencyShutdown();

        vm.prank(user1);
        vm.expectRevert(); // Will revert with EnforcedPause (pause check comes first)
        staking.stake(1000 ether);
    }

    /// @notice Test claimRewards reverts with invalid stakeId
    function test_ClaimRewardsRevertsInvalidStakeId() public {
        vm.prank(user1);
        vm.expectRevert(ProgressiveStaking.InvalidStakeId.selector);
        staking.claimRewards(999);
    }

    /// @notice Test claimAllRewards reverts when no rewards
    function test_ClaimAllRewardsRevertsNoRewards() public {
        vm.prank(user1);
        staking.stake(1000 ether);

        // Immediately try to claim (no time passed = no rewards)
        vm.prank(user1);
        vm.expectRevert(ProgressiveStaking.NoRewardsToClaim.selector);
        staking.claimAllRewards();
    }

    /// @notice Test claimAllRewards reverts when treasury insufficient
    function test_ClaimAllRewardsRevertsInsufficientTreasury() public {
        vm.prank(user1);
        staking.stake(1000 ether);

        vm.warp(block.timestamp + 180 days);

        // Withdraw all treasury
        uint256 treasuryBal = staking.getTreasuryBalance();
        vm.prank(owner);
        staking.withdrawTreasury(treasuryBal);

        vm.prank(user1);
        vm.expectRevert(ProgressiveStaking.InsufficientTreasury.selector);
        staking.claimAllRewards();
    }

    /// @notice Test requestWithdraw reverts with invalid stakeId
    function test_RequestWithdrawRevertsInvalidStakeId() public {
        vm.prank(user1);
        vm.expectRevert(ProgressiveStaking.InvalidStakeId.selector);
        staking.requestWithdraw(999, 100 ether);
    }

    /// @notice Test requestWithdraw reverts with zero amount
    function test_RequestWithdrawRevertsZeroAmount() public {
        vm.prank(user1);
        staking.stake(1000 ether);

        vm.prank(user1);
        vm.expectRevert(ProgressiveStaking.ZeroAmount.selector);
        staking.requestWithdraw(1, 0);
    }

    /// @notice Test executeWithdraw reverts with invalid stakeId
    function test_ExecuteWithdrawRevertsInvalidStakeId() public {
        vm.prank(user1);
        vm.expectRevert(ProgressiveStaking.InvalidStakeId.selector);
        staking.executeWithdraw(999);
    }

    /// @notice Test cancelWithdrawRequest reverts with invalid stakeId
    function test_CancelWithdrawRevertsInvalidStakeId() public {
        vm.prank(user1);
        vm.expectRevert(ProgressiveStaking.InvalidStakeId.selector);
        staking.cancelWithdrawRequest(999);
    }

    /// @notice Test emergencyWithdraw reverts when not in emergency mode
    function test_EmergencyWithdrawRevertsNotEmergencyMode() public {
        vm.prank(user1);
        staking.stake(1000 ether);

        vm.prank(user1);
        vm.expectRevert(ProgressiveStaking.EmergencyModeNotActive.selector);
        staking.emergencyWithdraw();
    }

    /// @notice Test emergencyWithdraw reverts when user has no stakes
    function test_EmergencyWithdrawRevertsNoStakes() public {
        vm.prank(owner);
        staking.emergencyShutdown();

        vm.prank(user1);
        vm.expectRevert(ProgressiveStaking.NoStakesToWithdraw.selector);
        staking.emergencyWithdraw();
    }

    /// @notice Test depositTreasury reverts with zero amount (branch coverage)
    function test_DepositTreasuryRevertsZeroAmount_Branch() public {
        vm.prank(owner);
        vm.expectRevert(ProgressiveStaking.ZeroAmount.selector);
        staking.depositTreasury(0);
    }

    /// @notice Test withdrawTreasury reverts with zero amount (branch coverage)
    function test_WithdrawTreasuryRevertsZeroAmount_Branch() public {
        vm.prank(owner);
        vm.expectRevert(ProgressiveStaking.ZeroAmount.selector);
        staking.withdrawTreasury(0);
    }

    /// @notice Test withdrawTreasury reverts when amount exceeds balance (branch coverage)
    function test_WithdrawTreasuryRevertsInsufficientBalance_Branch() public {
        uint256 treasuryBal = staking.getTreasuryBalance();

        vm.prank(owner);
        vm.expectRevert(ProgressiveStaking.InsufficientTreasury.selector);
        staking.withdrawTreasury(treasuryBal + 1);
    }

    /// @notice Test updateTierRates reverts with invalid rate
    function test_UpdateTierRatesRevertsInvalidRate() public {
        uint256[6] memory invalidRates = [uint256(50), 70, 200, 400, 500, 10001]; // Last rate > 10000

        vm.prank(owner);
        vm.expectRevert(ProgressiveStaking.InvalidTierRates.selector);
        staking.updateTierRates(invalidRates);
    }

    /// @notice Test getTierConfig reverts with invalid tier
    function test_GetTierConfigRevertsInvalidTier() public {
        vm.expectRevert(ProgressiveStaking.InvalidTier.selector);
        staking.getTierConfig(6); // Max is 5 (0-indexed)
    }

    /// @notice Test getStakeByStakeId reverts with invalid stakeId
    function test_GetStakeByStakeIdRevertsInvalidStakeId() public {
        vm.expectRevert(ProgressiveStaking.InvalidStakeId.selector);
        staking.getStakeByStakeId(user1, 999);
    }

    /// @notice Test calculateRewards reverts with invalid stakeId
    function test_CalculateRewardsRevertsInvalidStakeId() public {
        vm.expectRevert(ProgressiveStaking.InvalidStakeId.selector);
        staking.calculateRewards(user1, 999);
    }

    /// @notice Test getCurrentTier reverts with invalid stakeId
    function test_GetCurrentTierRevertsInvalidStakeId() public {
        vm.expectRevert(ProgressiveStaking.InvalidStakeId.selector);
        staking.getCurrentTier(user1, 999);
    }
}
