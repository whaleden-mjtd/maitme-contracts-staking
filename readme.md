# Smart Contract for Staking with Progressive Interest Rates

## Quick Start

### Prerequisites

- [Git](https://git-scm.com/)
- [Foundry](https://book.getfoundry.sh/getting-started/installation)

### Installation

```bash
# Clone the repository
git clone https://github.com/whaleden-mjtd/maitme-contracts-staking.git
cd maitme-contracts-staking

# Install dependencies (git submodules)
git submodule update --init --recursive

# Install Foundry (if not already installed)
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### Build

```bash
forge build
```

### Test

```bash
# Run all tests
forge test

# Run tests with verbose output
forge test -vvv

# Run specific test
forge test --match-test test_Stake

# Run tests with gas report
forge test --gas-report
```

### Local Development

```bash
# Start local Anvil node
anvil

# In another terminal, deploy to local node
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast
```

### Deploy to Testnet

1. Copy `.env.example` to `.env` and fill in your values:

```bash
cp .env.example .env
```

2. Edit `.env` with your configuration:

```
PRIVATE_KEY=your_private_key_without_0x
SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/YOUR_KEY
STAKING_TOKEN_ADDRESS=0x...
ETHERSCAN_API_KEY=your_etherscan_key
```

3. Deploy:

```bash
# Deploy to Sepolia (testnet)
forge script script/Deploy.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast --verify

# Deploy to Mainnet
forge script script/Deploy.s.sol --rpc-url $MAINNET_RPC_URL --broadcast --verify
```

### Code Coverage

```bash
forge coverage
```

### Format Code

```bash
forge fmt
```

### Project Structure

```
├── src/
│   └── ProgressiveStaking.sol    # Main staking contract
├── test/
│   ├── ProgressiveStaking.t.sol  # Test suite
│   └── mocks/
│       └── ERC20Mock.sol         # Mock token for testing
├── script/
│   └── Deploy.s.sol              # Deployment script
├── lib/                          # Dependencies (git submodules)
│   ├── forge-std/
│   └── openzeppelin-contracts/
├── foundry.toml                  # Foundry configuration
├── remappings.txt                # Import remappings
└── .env.example                  # Environment variables template
```

---

## 1. Project Overview

### Purpose
Smart contract for staking ERC20 tokens with progressive interest rates based on staking duration.

### Key Features
- **Progressive interest rates** - the longer you stake, the higher the APY
- **Automatic compound** - interest is calculated with compounding across all tiers
- **Flexible claim** - users choose when to withdraw rewards
- **3-month notice period** - protects project liquidity
- **Founder mode** - special mode without interest for founders
- **Emergency shutdown** - safety mechanism for crisis situations

## 2. Tier System (Interest Rates)

| Tier | Period | APY | Description |
|------|--------|-----|-------------|
| 1 | 0-6 months | 0.5% | Entry period |
| 2 | 6-12 months | 0.7% | Basic tier |
| 3 | 12-24 months | 2.0% | Advanced tier |
| 4 | 24-36 months | 4.0% | Loyalty tier |
| 5 | 36-48 months | 5.0% | Premium tier |
| 6 | 48+ months | 6.0% | VIP tier (unlimited) |

### Calculation Example
User stakes 10,000 tokens for 24 months:
- **Tier 1** (0-6 months): 10,000 × 0.5% × 0.5 = 25 tokens
- **Tier 2** (6-12 months): 10,025 × 0.7% × 0.5 = 35.09 tokens
- **Tier 3** (12-24 months): 10,060.09 × 2.0% × 1 = 201.2 tokens
- **Total after 24 months**: ~10,261.3 tokens

## 3. Architecture

### Separate Stake Positions
Each token deposit creates a separate stake position with its own timestamp.

**Key characteristics:**
- Each stake = separate position in array
- Separate reward calculation for each position with automatic compounding
- User sees all stake positions as a list of transactions
- Flexible claim - user chooses when to withdraw rewards
- No merging = eliminates weighted average bug risks
- Transparent - each position has clear date and interest rate

### Data Structure

```solidity
struct StakePosition {
    uint256 stakeId;           // Unique position ID (immutable)
    uint256 amount;            // Token amount
    uint256 startTime;         // Staking start time
    uint256 lastClaimTime;     // Last rewards claim
}

mapping(address => StakePosition[]) public userStakes;
mapping(address => bool) private isFounder;
uint256 public nextStakeId = 1;
mapping(address => mapping(uint256 => uint256)) private stakeIdToIndex;
```

## 4. Functional Requirements

### 4.1 Core Contract Functions

| Function | Description | Access |
|----------|-------------|--------|
| `stake(uint256 amount)` | Create new stake position | User |
| `claimRewards(uint256 stakeId)` | Withdraw rewards from specific position | User |
| `claimAllRewards()` | Withdraw rewards from all positions at once | User |
| `requestWithdraw(uint256 stakeId, uint256 amount)` | Submit withdrawal request for position | User |
| `executeWithdraw(uint256 stakeId)` | Withdraw after 3 months | User |
| `emergencyWithdraw()` | Withdraw all positions during emergency shutdown | User |
| `cancelWithdrawRequest(uint256 stakeId)` | Cancel pending withdrawal request | User |

### 4.2 View Functions (read-only, gas free)

| Function | Description |
|----------|-------------|
| `getStakeInfo(address user)` | Complete info about all stake positions |
| `getStakeByStakeId(address user, uint256 stakeId)` | Specific position details |
| `calculateRewards(address user, uint256 stakeId)` | Rewards for specific position |
| `calculateTotalRewards(address user)` | Sum of rewards from all positions |
| `getWithdrawableAmount(address user, uint256 stakeId)` | How much can be withdrawn from position |
| `getPendingWithdrawals(address user)` | Info about all withdrawal requests |
| `getCurrentTier(address user, uint256 stakeId)` | Current tier of specific position |
| `getUserStakeCount(address user)` | Number of active user positions |

### 4.3 Admin Functions

| Function | Description | Permission |
|----------|-------------|------------|
| `emergencyShutdown()` | Initiate emergency mode | Owner |
| `transferOwnership(address newOwner)` | 2-step ownership transfer | Owner |
| `acceptOwnership()` | Confirm ownership acceptance | Pending Owner |
| `grantRole(bytes32 role, address account)` | Grant Admin role | Owner |
| `revokeRole(bytes32 role, address account)` | Revoke Admin role | Owner |
| `pause() / unpause()` | Pause contract | Admin/Owner |
| `updateTierRates(uint256[] rates)` | Update interest rates | Owner |
| `depositTreasury(uint256 amount)` | Deposit tokens to treasury | Owner |
| `withdrawTreasury(uint256 amount)` | Withdraw unused tokens from treasury | Owner |
| `getTreasuryBalance()` | Display treasury balance | View |

## 5. Technical Implementation

### 5.1 Stake Mechanism

```solidity
function stake(uint256 amount) external {
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
    
    emit Staked(msg.sender, stakeId, amount, block.timestamp);
}
```

### 5.2 Withdrawal Mechanism

**3-month notice period:**
1. `requestWithdraw(stakeId, amount)` - starts 90-day countdown
2. After 90 days: `executeWithdraw(stakeId)` - actual token withdrawal
3. During notice period: rewards continue to accrue

```solidity
struct WithdrawRequest {
    uint256 stakeId;
    uint256 amount;
    uint256 requestTime;
    uint256 availableAt;    // requestTime + 90 days
    bool executed;
}
```

### 5.3 Rewards Mechanism

**Automatic compound:**
- Interest is calculated automatically with compounding on each query (VIEW function)
- Rewards mathematically accumulate continuously across all tiers
- NO transactions required for calculation

**Claim rewards:**
- `claimRewards(positionIndex)` - withdraws rewards from specific position
- `claimAllRewards()` - withdraws rewards from all positions at once
- After claim, `position.amount` doesn't increase - rewards go to wallet
- `position.lastClaimTime` is updated

### 5.4 Treasury Management

Contract has a separate treasury fund for reward payouts. Treasury must be pre-funded with tokens.

```solidity
uint256 public treasuryBalance;
uint256 public totalRewardsAllocated;

function depositTreasury(uint256 amount) external onlyOwner {
    token.transferFrom(msg.sender, address(this), amount);
    treasuryBalance += amount;
    emit TreasuryDeposited(msg.sender, amount, block.timestamp);
}
```

**Important aspects:**
- ✅ Separate account for rewards vs. user staked tokens
- ✅ Owner must keep treasury sufficiently funded
- ✅ View function `getTreasuryBalance()` for status monitoring
- ⚠️ If treasury runs out, rewards are not accrued

### 5.5 Security Features

```solidity
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
```

- **ReentrancyGuard**: Protection against reentrancy attacks
- **Pausable**: Ability to pause contract in emergency
- **Ownable2Step**: Secure ownership transfer (2 steps)
- **AccessControl**: Role-based access (Owner, Admin)
- **SafeERC20**: Safe ERC20 token handling

**Role System:**

```solidity
bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00; // Owner role
```

**Owner (DEFAULT_ADMIN_ROLE):**
- Transfer ownership
- Grant/revoke Admin roles
- Emergency shutdown
- Change tier rates

**Admin (ADMIN_ROLE):**
- Pause/Unpause contract
- View statistics
- Monitoring operations

## 6. Events

```solidity
// User actions
event Staked(address indexed user, uint256 indexed stakeId, uint256 amount, uint256 timestamp);
event RewardsClaimed(address indexed user, uint256 indexed stakeId, uint256 rewardAmount, uint256 timestamp);
event AllRewardsClaimed(address indexed user, uint256 totalRewardAmount, uint256 timestamp);
event WithdrawRequested(address indexed user, uint256 indexed stakeId, uint256 amount, uint256 timestamp, uint256 availableAt);
event WithdrawExecuted(address indexed user, uint256 indexed stakeId, uint256 amount, uint256 timestamp);
event WithdrawCancelled(address indexed user, uint256 indexed stakeId, uint256 amount, uint256 timestamp);

// Admin actions
event EmergencyShutdown(address indexed admin, uint256 timestamp, uint256 totalStaked, uint256 totalRewards);
event ContractPaused(address indexed admin, uint256 timestamp);
event ContractUnpaused(address indexed admin, uint256 timestamp);
event TierRatesUpdated(address indexed admin, uint256[] newRates, uint256 timestamp);
event TreasuryDeposited(address indexed from, uint256 amount, uint256 timestamp);
event TreasuryWithdrawn(address indexed to, uint256 amount, uint256 timestamp);

// Role management
event AdminRoleGranted(address indexed account, address indexed grantor, uint256 timestamp);
event AdminRoleRevoked(address indexed account, address indexed revoker, uint256 timestamp);
```

## 7. Gas Optimization

| Operation | 1 position | 50 positions | Note |
|-----------|------------|--------------|------|
| `stake()` | ~50-60k gas | Same | Always adds only 1 position |
| `calculateTotalRewards()` | ~30-50k gas | ~500k gas | VIEW - free |
| `claimRewards(i)` | ~60-70k gas | Same | Claim 1 position |
| `claimAllRewards()` | ~70-80k gas | ~600k gas | Batch claim |
| `requestWithdraw(i)` | ~60k gas | Same | Withdrawal 1 position |

**Mitigation strategies:**
- View functions off-chain (free)
- Optional merge function for future
- Gas refunds on cleanup

## 8. Frontend Optimization

```javascript
// ❌ WRONG: 50 separate calls
for (let i = 0; i < 50; i++) {
  await contract.getStakePosition(user, i);
}

// ✅ CORRECT: One call for all positions
const allPositions = await contract.getStakeInfo(user);
```

**View functions are free:**
- `getStakeInfo()` returns all positions at once
- `calculateTotalRewards()` aggregates off-chain
- Frontend can cache and display immediately

## 9. Founder Mode

Special mode for project founders:
- Hardcoded addresses at deploy
- No interest (APY = 0%)
- Standard 3-month notice period
- Automatic detection: founders without interest, public with interest
