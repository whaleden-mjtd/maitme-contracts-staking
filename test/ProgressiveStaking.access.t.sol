// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ProgressiveStakingBaseTest} from "./ProgressiveStaking.base.t.sol";
import {ProgressiveStaking} from "../src/ProgressiveStaking.sol";

/**
 * @title ProgressiveStakingAccessTest
 * @notice Access control and pausable tests for ProgressiveStaking contract
 * @dev Tests role-based permissions, pause/unpause functionality, and emergency mode
 */
contract ProgressiveStakingAccessTest is ProgressiveStakingBaseTest {

    // ============ Access Control Tests ============

    /// @notice Test that only DEFAULT_ADMIN_ROLE can deposit treasury
    function test_OnlyAdminCanDepositTreasury() public {
        token.mint(user1, 1000 ether);
        vm.prank(user1);
        token.approve(address(staking), 1000 ether);

        vm.prank(user1);
        vm.expectRevert();
        staking.depositTreasury(1000 ether);
    }

    /// @notice Test that only DEFAULT_ADMIN_ROLE can withdraw treasury
    function test_OnlyAdminCanWithdrawTreasury() public {
        vm.prank(user1);
        vm.expectRevert();
        staking.withdrawTreasury(100 ether);
    }

    /// @notice Test that only DEFAULT_ADMIN_ROLE can update tier rates
    function test_OnlyAdminCanUpdateTierRates() public {
        uint256[6] memory newRates = [uint256(100), 150, 250, 450, 550, 650];

        vm.prank(user1);
        vm.expectRevert();
        staking.updateTierRates(newRates);
    }

    /// @notice Test that only DEFAULT_ADMIN_ROLE can trigger emergency shutdown
    function test_OnlyAdminCanEmergencyShutdown() public {
        vm.prank(user1);
        vm.expectRevert();
        staking.emergencyShutdown();
    }

    /// @notice Test that only ADMIN_ROLE can pause
    function test_OnlyAdminCanPause() public {
        vm.prank(user1);
        vm.expectRevert();
        staking.pause();
    }

    /// @notice Test that only ADMIN_ROLE can unpause
    function test_OnlyAdminCanUnpause() public {
        vm.prank(owner);
        staking.pause();

        vm.prank(user1);
        vm.expectRevert();
        staking.unpause();
    }

    // ============ Role Management Tests ============

    /// @notice Test granting ADMIN_ROLE to another address
    function test_GrantAdminRole() public {
        address newAdmin = makeAddr("newAdmin");

        vm.startPrank(owner);
        staking.grantRole(staking.ADMIN_ROLE(), newAdmin);
        vm.stopPrank();

        assertTrue(staking.hasRole(staking.ADMIN_ROLE(), newAdmin));

        vm.prank(newAdmin);
        staking.pause();

        assertTrue(staking.paused());
    }

    /// @notice Test revoking ADMIN_ROLE
    function test_RevokeAdminRole() public {
        address newAdmin = makeAddr("newAdmin");

        vm.startPrank(owner);
        staking.grantRole(staking.ADMIN_ROLE(), newAdmin);
        staking.revokeRole(staking.ADMIN_ROLE(), newAdmin);
        vm.stopPrank();

        assertFalse(staking.hasRole(staking.ADMIN_ROLE(), newAdmin));

        vm.prank(newAdmin);
        vm.expectRevert();
        staking.pause();
    }

    // ============ Pausable Tests ============

    /// @notice Test that stake reverts when paused
    function test_StakeRevertsWhenPaused() public {
        vm.prank(owner);
        staking.pause();

        vm.prank(user1);
        vm.expectRevert();
        staking.stake(1000 ether);
    }

    /// @notice Test that claimRewards reverts when paused
    function test_ClaimRewardsRevertsWhenPaused() public {
        vm.prank(user1);
        staking.stake(1000 ether);

        vm.warp(block.timestamp + 90 days);

        vm.prank(owner);
        staking.pause();

        vm.prank(user1);
        vm.expectRevert();
        staking.claimRewards(1);
    }

    /// @notice Test that claimAllRewards reverts when paused
    function test_ClaimAllRewardsRevertsWhenPaused() public {
        vm.prank(user1);
        staking.stake(1000 ether);

        vm.warp(block.timestamp + 90 days);

        vm.prank(owner);
        staking.pause();

        vm.prank(user1);
        vm.expectRevert();
        staking.claimAllRewards();
    }

    /// @notice Test that requestWithdraw reverts when paused
    function test_RequestWithdrawRevertsWhenPaused() public {
        vm.prank(user1);
        staking.stake(1000 ether);

        vm.prank(owner);
        staking.pause();

        vm.prank(user1);
        vm.expectRevert();
        staking.requestWithdraw(1, 500 ether);
    }

    /// @notice Test that executeWithdraw works when paused (no whenNotPaused)
    function test_ExecuteWithdrawWorksWhenPaused() public {
        vm.prank(user1);
        staking.stake(1000 ether);

        vm.prank(user1);
        staking.requestWithdraw(1, 1000 ether);

        vm.warp(block.timestamp + 90 days);

        vm.prank(owner);
        staking.pause();

        vm.prank(user1);
        staking.executeWithdraw(1);

        assertEq(staking.getUserStakeCount(user1), 0);
    }

    /// @notice Test that cancelWithdrawRequest works when paused
    function test_CancelWithdrawRequestWorksWhenPaused() public {
        vm.prank(user1);
        staking.stake(1000 ether);

        vm.prank(user1);
        staking.requestWithdraw(1, 500 ether);

        vm.prank(owner);
        staking.pause();

        vm.prank(user1);
        staking.cancelWithdrawRequest(1);

        assertEq(staking.pendingWithdrawCount(user1), 0);
    }

    /// @notice Test unpause restores functionality
    function test_UnpauseRestoresFunctionality() public {
        vm.prank(owner);
        staking.pause();

        vm.prank(owner);
        staking.unpause();

        vm.prank(user1);
        staking.stake(1000 ether);

        assertEq(staking.getUserStakeCount(user1), 1);
    }

    // ============ Emergency Mode Tests ============

    /// @notice Test that stake reverts in emergency mode
    function test_StakeRevertsInEmergencyMode() public {
        vm.prank(owner);
        staking.emergencyShutdown();

        vm.prank(user1);
        vm.expectRevert();
        staking.stake(1000 ether);
    }

    /// @notice Test emergencyWithdraw reverts when not in emergency mode
    function test_EmergencyWithdrawRevertsWhenNotEmergency() public {
        vm.prank(user1);
        staking.stake(1000 ether);

        vm.prank(user1);
        vm.expectRevert(ProgressiveStaking.EmergencyModeNotActive.selector);
        staking.emergencyWithdraw();
    }

    /// @notice Test that emergencyWithdraw properly cleans up stakeIdExists mapping
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
    }

    /// @notice Test that emergencyWithdraw reverts when user has no stakes
    function test_EmergencyWithdrawNoStakes() public {
        vm.prank(owner);
        staking.emergencyShutdown();

        vm.prank(user1);
        vm.expectRevert(ProgressiveStaking.NoStakesToWithdraw.selector);
        staking.emergencyWithdraw();
    }

    /// @notice Test emergencyWithdraw with multiple users
    function test_EmergencyWithdrawMultipleUsers() public {
        vm.prank(user1);
        staking.stake(1000 ether);

        vm.prank(user2);
        staking.stake(2000 ether);

        vm.prank(owner);
        staking.emergencyShutdown();

        vm.prank(user1);
        staking.emergencyWithdraw();

        vm.expectRevert(ProgressiveStaking.InvalidStakeId.selector);
        staking.getStakeByStakeId(user1, 1);

        ProgressiveStaking.StakePosition memory pos = staking.getStakeByStakeId(user2, 2);
        assertEq(pos.amount, 2000 ether);
    }

    /// @notice Test that emergencyWithdraw cleans up pending withdraw mappings
    function test_EmergencyWithdrawCleansPendingWithdrawMappings() public {
        vm.startPrank(user1);
        staking.stake(1000 ether);
        staking.stake(2000 ether);
        staking.requestWithdraw(1, 500 ether);
        staking.requestWithdraw(2, 1000 ether);
        vm.stopPrank();

        assertEq(staking.pendingWithdrawCount(user1), 2);

        vm.prank(owner);
        staking.emergencyShutdown();

        vm.prank(user1);
        staking.emergencyWithdraw();

        assertEq(staking.pendingWithdrawCount(user1), 0);
    }
}
