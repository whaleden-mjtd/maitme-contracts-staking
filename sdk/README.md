# MAIT Progressive Staking SDK

TypeScript SDK for interacting with the MAIT Progressive Staking smart contract.

## Installation

```bash
npm install @maitme/staking-sdk viem
# or
yarn add @maitme/staking-sdk viem
# or
pnpm add @maitme/staking-sdk viem
```

## Quick Start

### Read-only Client

```typescript
import { ProgressiveStakingClient } from '@maitme/staking-sdk';
import { sepolia } from 'viem/chains';

const client = ProgressiveStakingClient.create(
  { contractAddress: '0x...' },
  'https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY',
  sepolia
);

// Get global stats
const stats = await client.getStakingStats();
console.log('Total Staked:', stats.totalStaked, 'MAIT');

// Get user stats
const userStats = await client.getUserStats('0x...');
console.log('Your Rewards:', userStats.totalRewards, 'MAIT');
```

### Client with Wallet (for transactions)

```typescript
import { createPublicClient, createWalletClient, http } from 'viem';
import { sepolia } from 'viem/chains';
import { privateKeyToAccount } from 'viem/accounts';
import { ProgressiveStakingClient } from '@maitme/staking-sdk';

const publicClient = createPublicClient({
  chain: sepolia,
  transport: http('https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY'),
});

const account = privateKeyToAccount('0x...');
const walletClient = createWalletClient({
  account,
  chain: sepolia,
  transport: http('https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY'),
});

const client = ProgressiveStakingClient.createWithWallet(
  { contractAddress: '0x...' },
  publicClient,
  walletClient
);

// Stake with automatic approval
const amount = client.parseAmount('1000'); // 1000 MAIT
const { stakeHash } = await client.stakeWithApproval(amount);
```

## API Reference

### Read Methods

| Method | Description |
|--------|-------------|
| `getStakingStats()` | Get global staking statistics |
| `getUserStats(address)` | Get formatted user stats with positions and rewards |
| `getStakeInfo(address)` | Get raw stake positions |
| `calculateTotalRewards(address)` | Get total claimable rewards |
| `getCurrentTier(address, stakeId)` | Get current tier for a position |
| `getActivePendingWithdrawals(address)` | Get active withdrawal requests |
| `isFounder(address)` | Check if address is a founder |
| `getTokenBalance(address)` | Get user's MAIT token balance |
| `getAllowance(address)` | Get current allowance for staking contract |

### Write Methods

| Method | Description |
|--------|-------------|
| `stake(amount)` | Stake tokens (requires prior approval) |
| `stakeWithApproval(amount)` | Stake with automatic approval if needed |
| `claimRewards(stakeId)` | Claim rewards for specific position |
| `claimAllRewards()` | Claim all available rewards |
| `requestWithdraw(stakeId, amount)` | Request withdrawal (starts 90-day notice) |
| `executeWithdraw(stakeId)` | Execute withdrawal after notice period |
| `cancelWithdrawRequest(stakeId)` | Cancel pending withdrawal |
| `emergencyWithdraw()` | Emergency withdraw (only in emergency mode) |

Notes:
- For partial withdrawals (`amount < position.amount`), the contract creates a new stake position for the withdrawing portion with a new `stakeId`.
- Use `getActivePendingWithdrawals(address)` to retrieve the pending request `stakeId` you should pass to `executeWithdraw` / `cancelWithdrawRequest`.

### Admin Methods

These methods require ADMIN_ROLE or DEFAULT_ADMIN_ROLE:

| Method | Description | Role Required |
|--------|-------------|---------------|
| `adminTransferStake(from, stakeId, to)` | Transfer stake ownership | ADMIN_ROLE |
| `depositTreasury(amount)` | Deposit tokens to treasury | DEFAULT_ADMIN_ROLE |
| `withdrawTreasury(amount)` | Withdraw from treasury | DEFAULT_ADMIN_ROLE |
| `pause()` | Pause the contract | ADMIN_ROLE |
| `unpause()` | Unpause the contract | ADMIN_ROLE |
| `emergencyShutdown()` | Activate emergency mode (IRREVERSIBLE) | DEFAULT_ADMIN_ROLE |

### Utility Methods

| Method | Description |
|--------|-------------|
| `parseAmount(string)` | Parse string amount to bigint (e.g., "1000" → 1000n * 10^18) |
| `formatAmount(bigint)` | Format bigint to string |
| `getNoticePeriodDays()` | Returns 90 (notice period in days) |

## Types

```typescript
interface UserStats {
  positions: FormattedStakePosition[];
  totalStaked: string;
  totalStakedRaw: bigint;
  totalRewards: string;
  totalRewardsRaw: bigint;
  pendingWithdrawals: FormattedWithdrawRequest[];
  isFounder: boolean;
}

interface FormattedStakePosition {
  stakeId: number;
  amount: string;
  amountRaw: bigint;
  startTime: Date;
  lastClaimTime: Date;
  stakingDays: number;
  currentTier: number;
}

interface FormattedWithdrawRequest {
  stakeId: number;
  amount: string;
  amountRaw: bigint;
  requestTime: Date;
  availableAt: Date;
  executed: boolean;
  cancelled: boolean;
  isReady: boolean;
  daysUntilReady: number;
}
```

## Tier Information

```typescript
import { TIER_INFO } from '@maitme/staking-sdk';

// TIER_INFO contains:
// Tier 1: 0-180 days = 0.5% APY
// Tier 2: 180-360 days = 0.7% APY
// Tier 3: 360-720 days = 2% APY
// Tier 4: 720-1080 days = 4% APY
// Tier 5: 1080-1440 days = 5% APY
// Tier 6: 1440+ days = 6% APY
```

## License

MIT
