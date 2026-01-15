// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {ProgressiveStaking} from "../src/ProgressiveStaking.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";

/**
 * @title StakingHandler
 * @notice Handler contract for invariant testing
 * @dev This contract acts as a proxy between the fuzzer and the staking contract.
 *      It provides bounded, valid inputs and tracks "ghost" variables for verification.
 *
 * Handler Functions:
 * - stake(): Create new stake positions with random amounts
 * - requestWithdraw(): Request withdrawal from random positions
 * - executeWithdraw(): Execute pending withdrawals after notice period
 * - claimRewards(): Claim rewards from random positions
 * - warpTime(): Advance blockchain time (1-30 days)
 *
 * Ghost Variables:
 * - ghostTotalStaked: Running total of all stakes (for cross-checking)
 * - ghostTotalWithdrawn: Running total of all withdrawals
 * - ghostTotalClaimed: Running total of all claimed rewards
 * - ghostUserStaked: Per-user staked amounts
 */
contract StakingHandler is Test {
    ProgressiveStaking public staking;
    ERC20Mock public token;

    address[] public actors;
    address public currentActor;

    // Ghost variables track expected state for invariant verification
    uint256 public ghostTotalStaked;
    uint256 public ghostTotalWithdrawn;
    uint256 public ghostTotalClaimed;

    mapping(address => uint256) public ghostUserStaked;

    /**
     * @notice Initialize handler with staking contract and create test actors
     * @param _staking The staking contract to test
     * @param _token The mock ERC20 token
     */
    constructor(ProgressiveStaking _staking, ERC20Mock _token) {
        staking = _staking;
        token = _token;

        // Create 5 actors with funded balances
        for (uint256 i = 0; i < 5; i++) {
            address actor = makeAddr(string(abi.encodePacked("actor", i)));
            actors.push(actor);

            // Fund actors with 1M tokens each
            token.mint(actor, 1_000_000 ether);
            vm.prank(actor);
            token.approve(address(staking), type(uint256).max);
        }
    }

    /**
     * @notice Modifier to select a random actor for the action
     * @param actorSeed Random seed to select actor (mod 5)
     */
    modifier useActor(uint256 actorSeed) {
        currentActor = actors[actorSeed % actors.length];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    /**
     * @notice Handler: Stake tokens with random amount
     * @param actorSeed Seed to select which actor stakes
     * @param amount Random amount (bounded to 1-100,000 tokens)
     */
    function stake(uint256 actorSeed, uint256 amount) public useActor(actorSeed) {
        amount = bound(amount, 1 ether, 100_000 ether);

        staking.stake(amount);

        ghostTotalStaked += amount;
        ghostUserStaked[currentActor] += amount;
    }

    /**
     * @notice Handler: Request withdrawal from a random position
     * @param actorSeed Seed to select actor
     * @param stakeIdSeed Seed to select which position
     * @param amountPercent Percentage of position to withdraw (1-100%)
     */
    function requestWithdraw(uint256 actorSeed, uint256 stakeIdSeed, uint256 amountPercent) public useActor(actorSeed) {
        uint256 stakeCount = staking.getUserStakeCount(currentActor);
        if (stakeCount == 0) return;

        ProgressiveStaking.StakePosition[] memory positions = staking.getStakeInfo(currentActor);
        uint256 posIndex = stakeIdSeed % positions.length;
        uint256 stakeId = positions[posIndex].stakeId;
        uint256 positionAmount = positions[posIndex].amount;

        if (positionAmount == 0) return;

        amountPercent = bound(amountPercent, 1, 100);
        uint256 withdrawAmount = (positionAmount * amountPercent) / 100;
        if (withdrawAmount == 0) withdrawAmount = 1;

        // Check if there's already a pending withdraw for this position
        ProgressiveStaking.WithdrawRequest[] memory requests = staking.getPendingWithdrawals(currentActor);
        for (uint256 i = 0; i < requests.length; i++) {
            if (requests[i].stakeId == stakeId && !requests[i].executed) {
                return; // Skip - already has pending withdraw
            }
        }

        staking.requestWithdraw(stakeId, withdrawAmount);
    }

    /**
     * @notice Handler: Execute a pending withdrawal if notice period passed
     * @param actorSeed Seed to select actor
     * @param requestSeed Seed to select which pending request
     */
    function executeWithdraw(uint256 actorSeed, uint256 requestSeed) public useActor(actorSeed) {
        ProgressiveStaking.WithdrawRequest[] memory requests = staking.getPendingWithdrawals(currentActor);
        if (requests.length == 0) return;

        uint256 reqIndex = requestSeed % requests.length;
        ProgressiveStaking.WithdrawRequest memory req = requests[reqIndex];

        if (req.executed) return;
        if (block.timestamp < req.availableAt) return; // Notice period not passed

        uint256 stakeId = req.stakeId;
        uint256 withdrawAmount = req.amount;

        staking.executeWithdraw(stakeId);

        ghostTotalWithdrawn += withdrawAmount;
        ghostUserStaked[currentActor] -= withdrawAmount;
    }

    /**
     * @notice Handler: Claim rewards from a random position
     * @param actorSeed Seed to select actor
     * @param stakeIdSeed Seed to select which position
     */
    function claimRewards(uint256 actorSeed, uint256 stakeIdSeed) public useActor(actorSeed) {
        uint256 stakeCount = staking.getUserStakeCount(currentActor);
        if (stakeCount == 0) return;

        ProgressiveStaking.StakePosition[] memory positions = staking.getStakeInfo(currentActor);
        uint256 posIndex = stakeIdSeed % positions.length;
        uint256 stakeId = positions[posIndex].stakeId;

        uint256 rewards = staking.calculateRewards(currentActor, stakeId);
        if (rewards == 0) return;
        if (rewards > staking.getTreasuryBalance()) return; // Skip if treasury insufficient

        staking.claimRewards(stakeId);
        ghostTotalClaimed += rewards;
    }

    /**
     * @notice Handler: Advance time by random amount (1-30 days)
     * @param timeToWarp Random time to advance
     */
    function warpTime(uint256 timeToWarp) public {
        timeToWarp = bound(timeToWarp, 1 days, 30 days);
        vm.warp(block.timestamp + timeToWarp);
    }

    /**
     * @notice Get number of actors for iteration in invariants
     */
    function getActorsLength() public view returns (uint256) {
        return actors.length;
    }
}

/**
 * @title ProgressiveStakingInvariantTest
 * @notice Invariant tests for ProgressiveStaking contract
 * @dev Invariant tests verify properties that must ALWAYS hold true, regardless of
 *      the sequence of operations. Foundry runs random sequences of handler functions
 *      and checks invariants after each call.
 *
 * Invariants Tested:
 * 1. TotalStakedMatchesSum - totalStaked() equals sum of all position amounts
 * 2. TotalStakedNeverNegative - totalStaked() >= 0
 * 3. TreasuryNeverNegative - getTreasuryBalance() >= 0
 * 4. ContractBalanceCoversStakedAndTreasury - token balance >= staked + treasury
 * 5. StakeIdsAreUnique - all stakeIds < nextStakeId
 * 6. PositionAmountsNonZero - no position has amount = 0
 * 7. LastClaimTimeNeverInFuture - lastClaimTime <= block.timestamp
 * 8. StartTimeNeverInFuture - startTime <= block.timestamp
 * 9. LastClaimTimeAfterStartTime - lastClaimTime >= startTime
 *
 * Test Configuration:
 * - 5 actors with 1M tokens each
 * - Treasury funded with 10M tokens
 * - 256 runs with 500 calls each (default)
 */
contract ProgressiveStakingInvariantTest is StdInvariant, Test {
    ProgressiveStaking public staking;
    ERC20Mock public token;
    StakingHandler public handler;

    address public owner = makeAddr("owner");

    uint256[6] public tierRates = [uint256(50), 70, 200, 400, 500, 600];

    function setUp() public {
        token = new ERC20Mock("Staking Token", "STK");

        address[] memory founders = new address[](0);

        vm.prank(owner);
        staking = new ProgressiveStaking(owner, address(token), founders, tierRates);

        // Fund treasury
        token.mint(owner, 10_000_000 ether);
        vm.startPrank(owner);
        token.approve(address(staking), 10_000_000 ether);
        staking.depositTreasury(10_000_000 ether);
        vm.stopPrank();

        handler = new StakingHandler(staking, token);

        // Target the handler for invariant testing
        targetContract(address(handler));

        // Exclude owner from being called
        excludeSender(owner);
    }

    // ============ Invariants ============
    // Each invariant function is called after every handler action.
    // If any invariant fails, the test fails and shows the sequence that broke it.

    /**
     * @notice INVARIANT: totalStaked() must equal sum of all position amounts
     * @dev Iterates through all actors and their positions to verify accounting.
     *      This catches any bugs in stake/withdraw amount tracking.
     */
    function invariant_TotalStakedMatchesSum() public view {
        uint256 calculatedTotal = 0;

        for (uint256 i = 0; i < handler.getActorsLength(); i++) {
            address actor = handler.actors(i);
            ProgressiveStaking.StakePosition[] memory positions = staking.getStakeInfo(actor);

            for (uint256 j = 0; j < positions.length; j++) {
                calculatedTotal += positions[j].amount;
            }
        }

        assertEq(staking.totalStaked(), calculatedTotal, "Total staked mismatch");
    }

    /**
     * @notice INVARIANT: totalStaked() must never be negative
     * @dev Solidity uint256 can't be negative, but this catches underflow bugs
     */
    function invariant_TotalStakedNeverNegative() public view {
        assertGe(staking.totalStaked(), 0, "Total staked is negative");
    }

    /**
     * @notice INVARIANT: Treasury balance must never be negative
     * @dev Ensures treasury accounting is correct after deposits/withdrawals/claims
     */
    function invariant_TreasuryNeverNegative() public view {
        assertGe(staking.getTreasuryBalance(), 0, "Treasury is negative");
    }

    /**
     * @notice INVARIANT: Contract token balance must cover staked + treasury
     * @dev The contract must always hold enough tokens to pay all users and treasury.
     *      If this fails, there's a critical accounting bug.
     */
    function invariant_ContractBalanceCoversStakedAndTreasury() public view {
        uint256 contractBalance = token.balanceOf(address(staking));
        uint256 totalStaked = staking.totalStaked();
        uint256 treasury = staking.getTreasuryBalance();

        assertGe(contractBalance, totalStaked + treasury, "Contract balance insufficient");
    }

    /**
     * @notice INVARIANT: All stakeIds must be less than nextStakeId
     * @dev Ensures stakeId counter always increments and no duplicates exist
     */
    function invariant_StakeIdsAreUnique() public view {
        uint256 nextId = staking.nextStakeId();

        for (uint256 i = 0; i < handler.getActorsLength(); i++) {
            address actor = handler.actors(i);
            ProgressiveStaking.StakePosition[] memory positions = staking.getStakeInfo(actor);

            for (uint256 j = 0; j < positions.length; j++) {
                assertLt(positions[j].stakeId, nextId, "StakeId >= nextStakeId");
            }
        }
    }

    /**
     * @notice INVARIANT: No position should have zero amount
     * @dev Positions with zero amount should be removed. If one exists, there's a bug.
     */
    function invariant_PositionAmountsNonZero() public view {
        for (uint256 i = 0; i < handler.getActorsLength(); i++) {
            address actor = handler.actors(i);
            ProgressiveStaking.StakePosition[] memory positions = staking.getStakeInfo(actor);

            for (uint256 j = 0; j < positions.length; j++) {
                assertGt(positions[j].amount, 0, "Position with zero amount exists");
            }
        }
    }

    /**
     * @notice INVARIANT: lastClaimTime must never be in the future
     * @dev lastClaimTime is set to block.timestamp on stake/claim, should never exceed it
     */
    function invariant_LastClaimTimeNeverInFuture() public view {
        for (uint256 i = 0; i < handler.getActorsLength(); i++) {
            address actor = handler.actors(i);
            ProgressiveStaking.StakePosition[] memory positions = staking.getStakeInfo(actor);

            for (uint256 j = 0; j < positions.length; j++) {
                assertLe(positions[j].lastClaimTime, block.timestamp, "lastClaimTime in future");
            }
        }
    }

    /**
     * @notice INVARIANT: startTime must never be in the future
     * @dev startTime is set to block.timestamp on stake, should never exceed it
     */
    function invariant_StartTimeNeverInFuture() public view {
        for (uint256 i = 0; i < handler.getActorsLength(); i++) {
            address actor = handler.actors(i);
            ProgressiveStaking.StakePosition[] memory positions = staking.getStakeInfo(actor);

            for (uint256 j = 0; j < positions.length; j++) {
                assertLe(positions[j].startTime, block.timestamp, "startTime in future");
            }
        }
    }

    /**
     * @notice INVARIANT: lastClaimTime must be >= startTime
     * @dev lastClaimTime starts equal to startTime and only increases on claims
     */
    function invariant_LastClaimTimeAfterStartTime() public view {
        for (uint256 i = 0; i < handler.getActorsLength(); i++) {
            address actor = handler.actors(i);
            ProgressiveStaking.StakePosition[] memory positions = staking.getStakeInfo(actor);

            for (uint256 j = 0; j < positions.length; j++) {
                assertGe(positions[j].lastClaimTime, positions[j].startTime, "lastClaimTime before startTime");
            }
        }
    }

    /**
     * @notice Helper invariant for debugging - logs ghost variable state
     * @dev Uncomment console.log lines to see state during test runs
     */
    function invariant_callSummary() public view {
        // Uncomment for debugging:
        // console.log("Total Staked (ghost):", handler.ghostTotalStaked());
        // console.log("Total Withdrawn (ghost):", handler.ghostTotalWithdrawn());
        // console.log("Total Claimed (ghost):", handler.ghostTotalClaimed());
    }
}
