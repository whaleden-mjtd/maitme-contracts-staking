/**
 * Basic usage example for MAIT Progressive Staking SDK
 *
 * This example shows how to:
 * 1. Create a read-only client
 * 2. Create a client with wallet for transactions
 * 3. Read staking stats and user positions
 * 4. Stake tokens
 * 5. Claim rewards
 * 6. Request and execute withdrawals
 */

import {
  createPublicClient,
  createWalletClient,
  http,
  type Address,
} from "viem";
import { sepolia } from "viem/chains";
import { privateKeyToAccount } from "viem/accounts";
import {
  ProgressiveStakingClient,
  TIER_INFO,
  CONTRACTS,
  RPC_URLS,
  TOKEN_SYMBOL,
} from "@maitme/staking-sdk";

// ============ Example 1: Read-only client ============

async function readOnlyExample() {
  console.log("=== Read-only Example ===\n");

  // Create read-only client (no wallet needed)
  const client = ProgressiveStakingClient.create(
    { contractAddress: CONTRACTS.SEPOLIA },
    RPC_URLS.SEPOLIA,
    sepolia
  );

  // Get global staking stats
  const stats = await client.getStakingStats();
  console.log("Total Staked:", stats.totalStaked, TOKEN_SYMBOL);
  console.log("Treasury Balance:", stats.treasuryBalance, TOKEN_SYMBOL);
  console.log("Is Paused:", stats.isPaused);
  console.log("Emergency Mode:", stats.isEmergencyMode);

  // Get user stats
  const userAddress: Address = "0x..."; // Replace with user address
  const userStats = await client.getUserStats(userAddress);

  console.log("\n--- User Stats ---");
  console.log("Total Staked:", userStats.totalStaked, TOKEN_SYMBOL);
  console.log("Total Rewards:", userStats.totalRewards, TOKEN_SYMBOL);
  console.log("Is Founder:", userStats.isFounder);
  console.log("Positions:", userStats.positions.length);

  // Display positions
  for (const pos of userStats.positions) {
    console.log(`\n  Position #${pos.stakeId}:`);
    console.log(`    Amount: ${pos.amount} ${TOKEN_SYMBOL}`);
    console.log(`    Staking Days: ${pos.stakingDays}`);
    console.log(`    Current Tier: ${pos.currentTier}`);
    console.log(`    Started: ${pos.startTime.toLocaleDateString()}`);
  }

  // Display pending withdrawals
  if (userStats.pendingWithdrawals.length > 0) {
    console.log("\n--- Pending Withdrawals ---");
    for (const req of userStats.pendingWithdrawals) {
      console.log(`  Stake #${req.stakeId}: ${req.amount} ${TOKEN_SYMBOL}`);
      console.log(`    Ready: ${req.isReady ? "Yes" : `No (${req.daysUntilReady} days)`}`);
    }
  }

  // Display tier info
  console.log("\n--- Tier Information ---");
  for (const tier of TIER_INFO) {
    console.log(`  Tier ${tier.tier}: ${tier.days} days = ${tier.rate} APY`);
  }
}

// ============ Example 2: Client with wallet ============

async function walletExample() {
  console.log("\n=== Wallet Example ===\n");

  // Create clients
  const publicClient = createPublicClient({
    chain: sepolia,
    transport: http(RPC_URLS.SEPOLIA),
  });

  // Create wallet from private key (for demo - use secure method in production!)
  const account = privateKeyToAccount("0x...");
  const walletClient = createWalletClient({
    account,
    chain: sepolia,
    transport: http(RPC_URLS.SEPOLIA),
  });

  // Create staking client with wallet
  const client = ProgressiveStakingClient.createWithWallet(
    { contractAddress: CONTRACTS.SEPOLIA },
    publicClient,
    walletClient
  );

  // Stake 1000 tokens (with automatic approval if needed)
  const amount = client.parseAmount("1000"); // 1000 MAIT
  console.log(`Staking 1000 ${TOKEN_SYMBOL}...`);

  const { approvalHash, stakeHash } = await client.stakeWithApproval(amount);

  if (approvalHash) {
    console.log("Approval tx:", approvalHash);
  }
  console.log("Stake tx:", stakeHash);

  // Wait for confirmation
  await publicClient.waitForTransactionReceipt({ hash: stakeHash });
  console.log("Staking confirmed!");

  // Check updated stats
  const stats = await client.getUserStats(account.address);
  console.log("New total staked:", stats.totalStaked, TOKEN_SYMBOL);
}

// ============ Example 3: Claim rewards ============

async function claimRewardsExample(client: ProgressiveStakingClient, userAddress: Address) {
  console.log("\n=== Claim Rewards Example ===\n");

  // Check available rewards
  const rewards = await client.calculateTotalRewards(userAddress);
  console.log("Available rewards:", client.formatAmount(rewards), TOKEN_SYMBOL);

  if (rewards > 0n) {
    // Claim all rewards
    const hash = await client.claimAllRewards();
    console.log("Claim tx:", hash);
  } else {
    console.log("No rewards to claim");
  }
}

// ============ Example 4: Withdrawal flow ============

async function withdrawalExample(client: ProgressiveStakingClient, userAddress: Address) {
  console.log("\n=== Withdrawal Example ===\n");

  // Get user positions
  const positions = await client.getStakeInfo(userAddress);
  if (positions.length === 0) {
    console.log("No positions to withdraw");
    return;
  }

  const position = positions[0];
  const withdrawAmount = position.amount / 2n; // Withdraw 50%

  console.log(`Requesting withdrawal of ${client.formatAmount(withdrawAmount)} ${TOKEN_SYMBOL}...`);
  console.log(`Notice period: ${client.getNoticePeriodDays()} days`);

  // Step 1: Request withdrawal
  const requestHash = await client.requestWithdraw(position.stakeId, withdrawAmount);
  console.log("Request tx:", requestHash);

  // Step 2: Wait for notice period (90 days)
  console.log("\n⏳ Wait 90 days for notice period...\n");

  // Step 3: Execute withdrawal (after notice period)
  // const executeHash = await client.executeWithdraw(position.stakeId);
  // console.log("Execute tx:", executeHash);

  // Or cancel if needed:
  // const cancelHash = await client.cancelWithdrawRequest(position.stakeId);
  // console.log("Cancel tx:", cancelHash);
}

// Run examples
async function main() {
  try {
    await readOnlyExample();
    // await walletExample();
  } catch (error) {
    console.error("Error:", error);
  }
}

main();
