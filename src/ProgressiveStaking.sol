// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title ProgressiveStaking
 * @notice Staking contract with progressive interest rates based on staking duration
 * @dev Implements tier-based APY system with automatic compounding
 */
contract ProgressiveStaking is ReentrancyGuard, Pausable, Ownable2Step, AccessControl {
    using SafeERC20 for IERC20;

    // ============ Constants ============

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    uint256 public constant NOTICE_PERIOD = 90 days;
    uint256 public constant YEAR_DURATION = 360 days;
    uint256 public constant RATE_PRECISION = 10000; // 100.00%
    uint8 public constant MAX_TIERS = 6;

    // ============ Structs ============

    struct StakePosition {
        uint256 stakeId;
        uint256 amount;
        uint256 startTime;
        uint256 lastClaimTime;
    }

    struct WithdrawRequest {
        uint256 stakeId;
        uint256 amount;
        uint256 requestTime;
        uint256 availableAt;
        bool executed;
    }

    struct TierConfig {
        uint256 startTime;
        uint256 endTime;
        uint256 rate; // in basis points (50 = 0.5%)
    }

    // ============ State Variables ============

    IERC20 public immutable stakingToken;

    uint256 public nextStakeId = 1;
    uint256 public treasuryBalance;
    uint256 public totalStaked;
    bool public emergencyMode;

    mapping(address => StakePosition[]) public userStakes;
    mapping(address => mapping(uint256 => uint256)) private stakeIdToIndex;
    mapping(address => mapping(uint256 => bool)) private stakeIdExists;
    mapping(address => WithdrawRequest[]) public userWithdrawRequests;
    mapping(address => bool) public isFounder;

    TierConfig[MAX_TIERS] public tiers;

    // ============ Events ============

    event Staked(address indexed user, uint256 indexed stakeId, uint256 amount, uint256 timestamp);
    event RewardsClaimed(address indexed user, uint256 indexed stakeId, uint256 rewardAmount, uint256 timestamp);
    event AllRewardsClaimed(address indexed user, uint256 totalRewardAmount, uint256 timestamp);
    event WithdrawRequested(
        address indexed user, uint256 indexed stakeId, uint256 amount, uint256 timestamp, uint256 availableAt
    );
    event WithdrawExecuted(address indexed user, uint256 indexed stakeId, uint256 amount, uint256 timestamp);
    event WithdrawCancelled(address indexed user, uint256 indexed stakeId, uint256 amount, uint256 timestamp);
    event EmergencyShutdown(address indexed admin, uint256 timestamp, uint256 totalStaked, uint256 totalRewards);
    event ContractPaused(address indexed admin, uint256 timestamp);
    event ContractUnpaused(address indexed admin, uint256 timestamp);
    event TierRatesUpdated(address indexed admin, uint256[MAX_TIERS] newRates, uint256 timestamp);
    event TreasuryDeposited(address indexed from, uint256 amount, uint256 timestamp);
    event TreasuryWithdrawn(address indexed to, uint256 amount, uint256 timestamp);

    // ============ Errors ============

    error ZeroAmount();
    error InvalidStakeId();
    error NoRewardsToClaim();
    error InsufficientTreasury();
    error WithdrawNotReady();
    error WithdrawAlreadyExecuted();
    error NoWithdrawRequest();
    error EmergencyModeActive();
    error EmergencyModeNotActive();
    error InvalidTierRates();
    error PositionHasPendingWithdraw();

    // ============ Constructor ============

    constructor(
        address initialOwner,
        address _stakingToken,
        address[] memory _founders,
        uint256[MAX_TIERS] memory _tierRates
    ) Ownable(initialOwner) {
        stakingToken = IERC20(_stakingToken);

        _grantRole(DEFAULT_ADMIN_ROLE, initialOwner);

        for (uint256 i = 0; i < _founders.length; i++) {
            isFounder[_founders[i]] = true;
        }

        _initializeTiers(_tierRates);
    }

    // ============ External Functions - User ============

    function stake(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        if (emergencyMode) revert EmergencyModeActive();

        uint256 stakeId = nextStakeId++;

        StakePosition memory newStake = StakePosition({
            stakeId: stakeId,
            amount: amount,
            startTime: block.timestamp,
            lastClaimTime: block.timestamp
        });

        userStakes[msg.sender].push(newStake);
        uint256 positionIndex = userStakes[msg.sender].length - 1;
        stakeIdToIndex[msg.sender][stakeId] = positionIndex;
        stakeIdExists[msg.sender][stakeId] = true;

        totalStaked += amount;

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, stakeId, amount, block.timestamp);
    }

    function claimRewards(uint256 stakeId) external nonReentrant whenNotPaused {
        if (!stakeIdExists[msg.sender][stakeId]) revert InvalidStakeId();

        uint256 positionIndex = stakeIdToIndex[msg.sender][stakeId];
        uint256 rewards = _calculatePositionRewards(msg.sender, positionIndex);

        if (rewards == 0) revert NoRewardsToClaim();
        if (treasuryBalance < rewards) revert InsufficientTreasury();

        userStakes[msg.sender][positionIndex].lastClaimTime = block.timestamp;
        treasuryBalance -= rewards;

        stakingToken.safeTransfer(msg.sender, rewards);

        emit RewardsClaimed(msg.sender, stakeId, rewards, block.timestamp);
    }

    function claimAllRewards() external nonReentrant whenNotPaused {
        uint256 totalRewards = 0;
        uint256 length = userStakes[msg.sender].length;

        for (uint256 i = 0; i < length; i++) {
            uint256 rewards = _calculatePositionRewards(msg.sender, i);
            if (rewards > 0) {
                userStakes[msg.sender][i].lastClaimTime = block.timestamp;
                totalRewards += rewards;
            }
        }

        if (totalRewards == 0) revert NoRewardsToClaim();
        if (treasuryBalance < totalRewards) revert InsufficientTreasury();

        treasuryBalance -= totalRewards;

        stakingToken.safeTransfer(msg.sender, totalRewards);

        emit AllRewardsClaimed(msg.sender, totalRewards, block.timestamp);
    }

    function requestWithdraw(uint256 stakeId, uint256 amount) external nonReentrant whenNotPaused {
        if (!stakeIdExists[msg.sender][stakeId]) revert InvalidStakeId();
        if (amount == 0) revert ZeroAmount();

        uint256 positionIndex = stakeIdToIndex[msg.sender][stakeId];
        StakePosition storage position = userStakes[msg.sender][positionIndex];

        if (amount > position.amount) revert ZeroAmount();

        // Check if there's already a pending withdraw for this stakeId
        if (_hasPendingWithdraw(msg.sender, stakeId)) revert PositionHasPendingWithdraw();

        uint256 availableAt = block.timestamp + NOTICE_PERIOD;

        WithdrawRequest memory request = WithdrawRequest({
            stakeId: stakeId,
            amount: amount,
            requestTime: block.timestamp,
            availableAt: availableAt,
            executed: false
        });

        userWithdrawRequests[msg.sender].push(request);

        emit WithdrawRequested(msg.sender, stakeId, amount, block.timestamp, availableAt);
    }

    function executeWithdraw(uint256 stakeId) external nonReentrant {
        if (!stakeIdExists[msg.sender][stakeId]) revert InvalidStakeId();

        (uint256 requestIndex, bool found) = _findWithdrawRequest(msg.sender, stakeId);
        if (!found) revert NoWithdrawRequest();

        WithdrawRequest storage request = userWithdrawRequests[msg.sender][requestIndex];

        if (request.executed) revert WithdrawAlreadyExecuted();
        if (block.timestamp < request.availableAt) revert WithdrawNotReady();

        request.executed = true;

        uint256 positionIndex = stakeIdToIndex[msg.sender][stakeId];
        StakePosition storage position = userStakes[msg.sender][positionIndex];

        // Claim any pending rewards first
        uint256 rewards = _calculatePositionRewards(msg.sender, positionIndex);
        if (rewards > 0 && treasuryBalance >= rewards) {
            treasuryBalance -= rewards;
            stakingToken.safeTransfer(msg.sender, rewards);
            emit RewardsClaimed(msg.sender, stakeId, rewards, block.timestamp);
        }

        uint256 withdrawAmount = request.amount;
        position.amount -= withdrawAmount;
        position.lastClaimTime = block.timestamp;
        totalStaked -= withdrawAmount;

        // If position is empty, remove it
        if (position.amount == 0) {
            _removePosition(msg.sender, positionIndex);
        }

        stakingToken.safeTransfer(msg.sender, withdrawAmount);

        emit WithdrawExecuted(msg.sender, stakeId, withdrawAmount, block.timestamp);
    }

    function cancelWithdrawRequest(uint256 stakeId) external nonReentrant {
        if (!stakeIdExists[msg.sender][stakeId]) revert InvalidStakeId();

        (uint256 requestIndex, bool found) = _findWithdrawRequest(msg.sender, stakeId);
        if (!found) revert NoWithdrawRequest();

        WithdrawRequest storage request = userWithdrawRequests[msg.sender][requestIndex];
        if (request.executed) revert WithdrawAlreadyExecuted();

        uint256 amount = request.amount;
        request.executed = true; // Mark as executed to prevent reuse

        emit WithdrawCancelled(msg.sender, stakeId, amount, block.timestamp);
    }

    function emergencyWithdraw() external nonReentrant {
        if (!emergencyMode) revert EmergencyModeNotActive();

        uint256 totalAmount = 0;
        uint256 totalRewards = 0;
        uint256 length = userStakes[msg.sender].length;

        for (uint256 i = 0; i < length; i++) {
            totalAmount += userStakes[msg.sender][i].amount;
            totalRewards += _calculatePositionRewards(msg.sender, i);
        }

        // Clear all positions
        delete userStakes[msg.sender];

        totalStaked -= totalAmount;

        // Transfer principal
        if (totalAmount > 0) {
            stakingToken.safeTransfer(msg.sender, totalAmount);
        }

        // Transfer rewards if treasury has enough
        if (totalRewards > 0 && treasuryBalance >= totalRewards) {
            treasuryBalance -= totalRewards;
            stakingToken.safeTransfer(msg.sender, totalRewards);
        }
    }

    // ============ External Functions - Admin ============

    function depositTreasury(uint256 amount) external onlyOwner {
        if (amount == 0) revert ZeroAmount();

        treasuryBalance += amount;
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        emit TreasuryDeposited(msg.sender, amount, block.timestamp);
    }

    function withdrawTreasury(uint256 amount) external onlyOwner {
        if (amount == 0) revert ZeroAmount();
        if (amount > treasuryBalance) revert InsufficientTreasury();

        treasuryBalance -= amount;
        stakingToken.safeTransfer(msg.sender, amount);

        emit TreasuryWithdrawn(msg.sender, amount, block.timestamp);
    }

    function updateTierRates(uint256[MAX_TIERS] calldata newRates) external onlyOwner {
        for (uint8 i = 0; i < MAX_TIERS; i++) {
            if (newRates[i] > RATE_PRECISION) revert InvalidTierRates();
            tiers[i].rate = newRates[i];
        }

        emit TierRatesUpdated(msg.sender, newRates, block.timestamp);
    }

    function emergencyShutdown() external onlyOwner {
        emergencyMode = true;
        _pause();

        uint256 totalRewards = 0; // Would need to calculate across all users

        emit EmergencyShutdown(msg.sender, block.timestamp, totalStaked, totalRewards);
    }

    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
        emit ContractPaused(msg.sender, block.timestamp);
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
        emit ContractUnpaused(msg.sender, block.timestamp);
    }

    // ============ View Functions ============

    function getStakeInfo(address user) external view returns (StakePosition[] memory) {
        return userStakes[user];
    }

    function getStakeByStakeId(address user, uint256 stakeId) external view returns (StakePosition memory) {
        if (!stakeIdExists[user][stakeId]) revert InvalidStakeId();
        uint256 positionIndex = stakeIdToIndex[user][stakeId];
        return userStakes[user][positionIndex];
    }

    function calculateRewards(address user, uint256 stakeId) external view returns (uint256) {
        if (!stakeIdExists[user][stakeId]) revert InvalidStakeId();
        uint256 positionIndex = stakeIdToIndex[user][stakeId];
        return _calculatePositionRewards(user, positionIndex);
    }

    function calculateTotalRewards(address user) external view returns (uint256) {
        uint256 totalRewards = 0;
        uint256 length = userStakes[user].length;

        for (uint256 i = 0; i < length; i++) {
            totalRewards += _calculatePositionRewards(user, i);
        }

        return totalRewards;
    }

    function getPendingWithdrawals(address user) external view returns (WithdrawRequest[] memory) {
        return userWithdrawRequests[user];
    }

    function getCurrentTier(address user, uint256 stakeId) external view returns (uint8) {
        if (!stakeIdExists[user][stakeId]) revert InvalidStakeId();
        uint256 positionIndex = stakeIdToIndex[user][stakeId];
        StakePosition memory position = userStakes[user][positionIndex];

        uint256 stakingDuration = block.timestamp - position.startTime;
        return _getTierForDuration(stakingDuration);
    }

    function getUserStakeCount(address user) external view returns (uint256) {
        return userStakes[user].length;
    }

    function getTreasuryBalance() external view returns (uint256) {
        return treasuryBalance;
    }

    function getTierConfig(uint8 tier) external view returns (TierConfig memory) {
        return tiers[tier];
    }

    // ============ Internal Functions ============

    function _initializeTiers(uint256[MAX_TIERS] memory _tierRates) internal {
        // Tier 1: 0-6 months
        tiers[0] = TierConfig({startTime: 0, endTime: 180 days, rate: _tierRates[0]});

        // Tier 2: 6-12 months
        tiers[1] = TierConfig({startTime: 180 days, endTime: 360 days, rate: _tierRates[1]});

        // Tier 3: 12-24 months
        tiers[2] = TierConfig({startTime: 360 days, endTime: 720 days, rate: _tierRates[2]});

        // Tier 4: 24-36 months
        tiers[3] = TierConfig({startTime: 720 days, endTime: 1080 days, rate: _tierRates[3]});

        // Tier 5: 36-48 months
        tiers[4] = TierConfig({startTime: 1080 days, endTime: 1440 days, rate: _tierRates[4]});

        // Tier 6: 48+ months (unlimited)
        tiers[5] = TierConfig({startTime: 1440 days, endTime: type(uint256).max, rate: _tierRates[5]});
    }

    function _calculatePositionRewards(address user, uint256 positionIndex) internal view returns (uint256) {
        StakePosition memory position = userStakes[user][positionIndex];

        // Founders don't earn rewards
        if (isFounder[user]) return 0;

        uint256 totalRewards = 0;
        uint256 currentAmount = position.amount;

        uint256 totalAge = block.timestamp - position.startTime;
        uint256 ageAtLastClaim = position.lastClaimTime - position.startTime;

        for (uint8 tier = 0; tier < MAX_TIERS; tier++) {
            uint256 tierStart = tiers[tier].startTime;
            uint256 tierEnd = tiers[tier].endTime;

            // If we haven't reached this tier yet, stop
            if (totalAge < tierStart) break;

            // Calculate time range to process in this tier
            uint256 tierProcessStart = _max(ageAtLastClaim, tierStart);
            uint256 tierProcessEnd = _min(totalAge, tierEnd);

            // Skip if already processed or not yet reached
            if (tierProcessEnd <= ageAtLastClaim) continue;
            if (tierProcessStart >= totalAge) break;

            uint256 timeInTier = tierProcessEnd - tierProcessStart;

            if (timeInTier > 0) {
                uint256 tierRate = tiers[tier].rate;
                uint256 tierRewards = (currentAmount * tierRate * timeInTier) / (YEAR_DURATION * RATE_PRECISION);

                totalRewards += tierRewards;
                currentAmount += tierRewards; // Compound for next tier
            }
        }

        return totalRewards;
    }

    function _getTierForDuration(uint256 duration) internal view returns (uint8) {
        for (uint8 i = 0; i < MAX_TIERS; i++) {
            if (duration >= tiers[i].startTime && duration < tiers[i].endTime) {
                return i + 1; // Return 1-indexed tier
            }
        }
        return MAX_TIERS; // Return max tier if beyond all
    }

    function _hasPendingWithdraw(address user, uint256 stakeId) internal view returns (bool) {
        uint256 length = userWithdrawRequests[user].length;
        for (uint256 i = 0; i < length; i++) {
            if (userWithdrawRequests[user][i].stakeId == stakeId && !userWithdrawRequests[user][i].executed) {
                return true;
            }
        }
        return false;
    }

    function _findWithdrawRequest(address user, uint256 stakeId) internal view returns (uint256, bool) {
        uint256 length = userWithdrawRequests[user].length;
        for (uint256 i = 0; i < length; i++) {
            if (userWithdrawRequests[user][i].stakeId == stakeId && !userWithdrawRequests[user][i].executed) {
                return (i, true);
            }
        }
        return (0, false);
    }

    function _removePosition(address user, uint256 index) internal {
        uint256 lastIndex = userStakes[user].length - 1;

        // Get the stakeId being removed BEFORE any swapping
        uint256 removedStakeId = userStakes[user][index].stakeId;

        if (index != lastIndex) {
            // Move last position to the removed index
            StakePosition memory lastPosition = userStakes[user][lastIndex];
            userStakes[user][index] = lastPosition;
            stakeIdToIndex[user][lastPosition.stakeId] = index;
        }

        // Mark the removed stakeId as non-existent
        stakeIdExists[user][removedStakeId] = false;

        userStakes[user].pop();
    }

    function _max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
