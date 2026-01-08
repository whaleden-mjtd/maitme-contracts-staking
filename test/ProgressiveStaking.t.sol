// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ProgressiveStaking} from "../src/ProgressiveStaking.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";

/**
 * @title ProgressiveStakingTest
 * @notice Test suite for ProgressiveStaking contract
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
    uint256[6] public tierRates = [uint256(50), 100, 200, 300, 400, 500];

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

    function test_Stake_MultiplePositions() public {
        vm.startPrank(user1);
        staking.stake(1000 ether);
        staking.stake(2000 ether);
        staking.stake(3000 ether);
        vm.stopPrank();

        assertEq(staking.getUserStakeCount(user1), 3);
        assertEq(staking.totalStaked(), 6000 ether);
    }

    function test_Stake_RevertZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert(ProgressiveStaking.ZeroAmount.selector);
        staking.stake(0);
    }

    // ============ Rewards Tests ============

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

    function test_CalculateRewards_Tier2() public {
        uint256 amount = 10_000 ether;

        vm.prank(user1);
        staking.stake(amount);

        // Fast forward 360 days (Tier 1 + Tier 2)
        vm.warp(block.timestamp + 360 days);

        uint256 rewards = staking.calculateTotalRewards(user1);
        // Tier 1: 10,000 * 0.5% * 0.5 = 25
        // Tier 2: 10,025 * 1.0% * 0.5 = 50.125
        // Total: ~75.125 tokens
        assertApproxEqRel(rewards, 75.125 ether, 0.01e18);
    }

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

    function test_FounderNoRewards() public {
        vm.prank(founder);
        staking.stake(10_000 ether);

        vm.warp(block.timestamp + 360 days);

        uint256 rewards = staking.calculateTotalRewards(founder);
        assertEq(rewards, 0);
    }

    // ============ Withdraw Tests ============

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
    }

    function test_ExecuteWithdraw() public {
        uint256 amount = 1000 ether;

        vm.prank(user1);
        staking.stake(amount);

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

    function test_CancelWithdrawRequest() public {
        vm.prank(user1);
        staking.stake(1000 ether);

        vm.prank(user1);
        staking.requestWithdraw(1, 1000 ether);

        vm.prank(user1);
        staking.cancelWithdrawRequest(1);

        // Position should still exist
        assertEq(staking.getUserStakeCount(user1), 1);
    }

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

    // ============ Admin Tests ============

    function test_DepositTreasury() public {
        uint256 additionalAmount = 50_000 ether;

        vm.startPrank(owner);
        token.approve(address(staking), additionalAmount);
        staking.depositTreasury(additionalAmount);
        vm.stopPrank();

        assertEq(staking.getTreasuryBalance(), TREASURY_AMOUNT + additionalAmount);
    }

    function test_WithdrawTreasury() public {
        uint256 withdrawAmount = 10_000 ether;

        vm.prank(owner);
        staking.withdrawTreasury(withdrawAmount);

        assertEq(staking.getTreasuryBalance(), TREASURY_AMOUNT - withdrawAmount);
    }

    function test_UpdateTierRates() public {
        uint256[6] memory newRates = [uint256(100), 200, 300, 400, 500, 600];

        vm.prank(owner);
        staking.updateTierRates(newRates);

        ProgressiveStaking.TierConfig memory tier0 = staking.getTierConfig(0);
        assertEq(tier0.rate, 100);
    }

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

    function test_RewardsAccumulateAcrossTiers() public {
        uint256 amount = 10_000 ether;

        vm.prank(user1);
        staking.stake(amount);

        // Fast forward 720 days (through Tier 1, 2, 3)
        vm.warp(block.timestamp + 720 days);

        uint256 rewards = staking.calculateTotalRewards(user1);

        // Rewards should be compounded across tiers
        // Tier 1: 10,000 * 0.5% * 0.5 = 25
        // Tier 2: 10,025 * 1.0% * 0.5 = 50.125
        // Tier 3: 10,075.125 * 2.0% * 1.0 = 201.5025
        // Total: ~276.6 tokens
        assertApproxEqRel(rewards, 276.6275 ether, 0.01e18);
    }
}
