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

# In another terminal, deploy to local node (uses testnet script with mock token)
forge script script/DeployTestnet.s.sol --rpc-url http://localhost:8545 --broadcast
```

### Deployment

1. Copy `.env.example` to `.env` and fill in your values:

```bash
cp .env.example .env
```

2. Edit `.env` with your configuration.

#### Deploy to Testnet (Sepolia)

Deploys a **mock ERC20 token** + staking contract. Useful for testing.

```bash
# Set environment variables
export PRIVATE_KEY=your_private_key_without_0x
export SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY
export ETHERSCAN_API_KEY=your_etherscan_key
export INITIAL_OWNER=0x...  # optional, defaults to deployer (use for multisig)
export FOUNDER_ADDRESSES=0x123...,0x456...  # optional

# Deploy
source .env
forge script script/DeployTestnet.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast --verify
```

This will:
- Deploy mock MAIT token (100M supply)
- Deploy ProgressiveStaking contract (owner = INITIAL_OWNER or deployer)
- Deposit 10M tokens to treasury

#### Deploy to Mainnet (Ethereum)

Uses **existing MAIT token**. For production deployment.

```bash
# Set environment variables
export PRIVATE_KEY=your_private_key_without_0x
export MAINNET_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY
export ETHERSCAN_API_KEY=your_etherscan_key
export STAKING_TOKEN_ADDRESS=0x...  # existing MAIT token address
export INITIAL_OWNER=0x...  # optional, defaults to deployer (use for multisig)
export TREASURY_AMOUNT=10000000000000000000000000  # 10M tokens in wei (optional)
export FOUNDER_ADDRESSES=0x123...,0x456...  # optional

# Deploy
source .env
forge script script/DeployMainnet.s.sol --rpc-url $MAINNET_RPC_URL --broadcast --verify
```

This will:
- Deploy ProgressiveStaking contract (owner = INITIAL_OWNER or deployer)
- Optionally deposit treasury (if TREASURY_AMOUNT is set)

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
│   └── ProgressiveStaking.sol       # Main staking contract
├── test/
│   ├── ProgressiveStaking.*.t.sol   # Test suites (148 tests)
│   └── mocks/
│       └── ERC20Mock.sol            # Mock token for testing
├── script/
│   ├── DeployTestnet.s.sol          # Testnet deployment (with mock token)
│   └── DeployMainnet.s.sol          # Mainnet deployment (existing token)
├── sdk/                             # TypeScript SDK
│   ├── src/                         # SDK source code
│   ├── examples/                    # Usage examples
│   └── README.md                    # SDK documentation
├── lib/                             # Dependencies (git submodules)
│   ├── forge-std/
│   └── openzeppelin-contracts/
├── ARCHITECTURE.md                  # Architecture & security documentation
├── foundry.toml                     # Foundry configuration
├── remappings.txt                   # Import remappings
└── .env.example                     # Environment variables template
```

### Architecture Documentation

For detailed architecture diagrams, state machines, and security documentation, see [ARCHITECTURE.md](./ARCHITECTURE.md).

### TypeScript SDK

For frontend integration, see the [SDK documentation](./sdk/README.md).

```bash
cd sdk
npm install
npm run build
```

Quick example:
```typescript
import { ProgressiveStakingClient } from '@maitme/staking-sdk';

const client = ProgressiveStakingClient.create(
  { contractAddress: '0x...' },
  'https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY',
  sepolia
);

const stats = await client.getUserStats('0x...');
console.log('Total Staked:', stats.totalStaked, 'MAIT');
console.log('Rewards:', stats.totalRewards, 'MAIT');
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

### Operational Notes (Custody / Web2 Integration)

- **Pending withdrawal limit:** Each address can have at most `MAX_PENDING_WITHDRAWALS` active (non-executed) withdrawal requests at once.
- **Stake count limit:** Each address can have at most `MAX_STAKES_PER_ADDRESS` active stake positions at once (to keep `emergencyWithdraw` and other per-position loops reliable).
- **Custody scaling:** If you custody multiple end-users under a single on-chain address (e.g., a Web2 custody account), withdrawals may be rate-limited by this cap.
- **Recommended approach:** Use multiple custody addresses (batching/sharding) and move stake positions between them using `adminTransferStake(from, stakeId, to)` **before** creating withdrawal requests.
- **Important:** `adminTransferStake` cannot move a position that already has a pending withdrawal request.

### 4.2 View Functions (read-only, gas free)

| Function | Description |
|----------|-------------|
| `getStakeInfo(address user)` | Complete info about all stake positions |
| `getStakeByStakeId(address user, uint256 stakeId)` | Specific position details |
| `calculateRewards(address user, uint256 stakeId)` | Rewards for specific position |
| `calculateTotalRewards(address user)` | Sum of rewards from all positions |
| `getWithdrawableAmount(address user, uint256 stakeId)` | How much can be withdrawn from position |
| `getPendingWithdrawals(address user)` | All withdrawal requests (including executed - for history) |
| `getActivePendingWithdrawals(address user)` | Only active (non-executed) withdrawal requests |
| `getCurrentTier(address user, uint256 stakeId)` | Current tier of specific position |
| `getUserStakeCount(address user)` | Number of active user positions |

### 4.3 Admin Functions

| Function | Description | Permission |
|----------|-------------|------------|
| `emergencyShutdown()` | Initiate emergency mode | DEFAULT_ADMIN_ROLE |
| `grantRole(bytes32 role, address account)` | Grant role | DEFAULT_ADMIN_ROLE |
| `revokeRole(bytes32 role, address account)` | Revoke role | DEFAULT_ADMIN_ROLE |
| `pause() / unpause()` | Pause contract | ADMIN_ROLE |
| `updateTierRates(uint256[] rates)` | Update interest rates | DEFAULT_ADMIN_ROLE |
| `depositTreasury(uint256 amount)` | Deposit tokens to treasury | DEFAULT_ADMIN_ROLE |
| `withdrawTreasury(uint256 amount)` | Withdraw unused tokens from treasury | DEFAULT_ADMIN_ROLE |
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
3. During notice period: reward accrual for the position is frozen at the request time (rewards do not increase while a request is pending)

```solidity
struct WithdrawRequest {
    uint256 stakeId;
    uint256 amount;
    uint256 requestTime;
    uint256 availableAt;    // requestTime + 90 days
    bool executed;
    bool cancelled;
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

function depositTreasury(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
    token.transferFrom(msg.sender, address(this), amount);
    treasuryBalance += amount;
    emit TreasuryDeposited(msg.sender, amount, block.timestamp);
}
```

**Important aspects:**
- ✅ Separate account for rewards vs. user staked tokens
- ✅ Admin (DEFAULT_ADMIN_ROLE) must keep treasury sufficiently funded
- ✅ View function `getTreasuryBalance()` for status monitoring
- ⚠️ If treasury runs out, rewards are not accrued

### 5.5 Security Features

```solidity
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
```

- **ReentrancyGuard**: Protection against reentrancy attacks
- **Pausable**: Ability to pause contract in emergency
- **AccessControl**: Role-based access (DEFAULT_ADMIN_ROLE, ADMIN_ROLE)
- **SafeERC20**: Safe ERC20 token handling

**Role System:**

```solidity
bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00; // Owner role
```

**DEFAULT_ADMIN_ROLE (Owner-level):**
- Grant/revoke roles
- Emergency shutdown
- Change tier rates
- Treasury management (deposit/withdraw)

**ADMIN_ROLE (Operator-level):**
- Pause/Unpause contract
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
event EmergencyWithdrawn(address indexed user, uint256 principal, uint256 rewards, uint256 timestamp);

// Admin actions
event EmergencyShutdown(address indexed admin, uint256 timestamp, uint256 totalStaked, uint256 totalRewards);
event ContractPaused(address indexed admin, uint256 timestamp);
event ContractUnpaused(address indexed admin, uint256 timestamp);
event TierRatesUpdated(address indexed admin, uint256[6] newRates, uint256 timestamp);
event TreasuryDeposited(address indexed from, uint256 amount, uint256 timestamp);
event TreasuryWithdrawn(address indexed to, uint256 amount, uint256 timestamp);
event StakeTransferred(address indexed from, address indexed to, uint256 indexed stakeId, uint256 timestamp);
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

---

## 10. Change Log

### v1.1.0 - Admin Stake Transfer (Web2→Web3 Conversion)

**New Requirement:** Support for users transitioning from web2 (custodial) to web3 (self-custody).

**Use Case:**
- Some users purchase tokens through traditional channels (web2) and have their stakes managed by a single admin address
- When a user wants to take control of their tokens (web3), the admin can transfer the stake to the user's own wallet

**New Function:**
```solidity
function adminTransferStake(
    address fromUser,
    uint256 stakeId,
    address toUser
) external onlyRole(ADMIN_ROLE)
```

**Behavior:**
- ✅ Only callable by `ADMIN_ROLE`
- ✅ Preserves `startTime` (tier progression continues)
- ✅ Does NOT auto-claim rewards (new owner claims them)
- ❌ Cannot transfer if stake has pending withdrawal request
- ❌ Cannot transfer to zero address or self

**New Event:**
```solidity
event StakeTransferred(address indexed from, address indexed to, uint256 indexed stakeId, uint256 timestamp);
```

**Security:**
- Admin-only operation prevents phishing attacks
- Off-chain identity verification recommended before transfer
- Pending withdrawals must be cancelled or executed first
