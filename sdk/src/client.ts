import {
  createPublicClient,
  createWalletClient,
  http,
  formatUnits,
  parseUnits,
  type Address,
  type PublicClient,
  type WalletClient,
  type Chain,
  type Transport,
  type Account,
} from "viem";
import { PROGRESSIVE_STAKING_ABI, ERC20_ABI } from "./abi";
import type {
  StakePosition,
  WithdrawRequest,
  TierConfig,
  FormattedStakePosition,
  FormattedWithdrawRequest,
  StakingStats,
  UserStats,
  StakingClientConfig,
} from "./types";
import { NOTICE_PERIOD_DAYS } from "./types";

export class ProgressiveStakingClient {
  private publicClient: PublicClient;
  private walletClient?: WalletClient<Transport, Chain, Account>;
  private contractAddress: Address;
  private tokenAddress?: Address;
  private decimals: number = 18;

  constructor(
    config: StakingClientConfig,
    publicClient: PublicClient,
    walletClient?: WalletClient<Transport, Chain, Account>
  ) {
    this.contractAddress = config.contractAddress;
    this.tokenAddress = config.tokenAddress;
    this.publicClient = publicClient;
    this.walletClient = walletClient;
  }

  // ============ Static Factory Methods ============

  static create(
    config: StakingClientConfig,
    rpcUrl: string,
    chain: Chain
  ): ProgressiveStakingClient {
    const publicClient = createPublicClient({
      chain,
      transport: http(rpcUrl),
    });
    return new ProgressiveStakingClient(config, publicClient);
  }

  static createWithWallet(
    config: StakingClientConfig,
    publicClient: PublicClient,
    walletClient: WalletClient<Transport, Chain, Account>
  ): ProgressiveStakingClient {
    return new ProgressiveStakingClient(config, publicClient, walletClient);
  }

  // ============ Read Methods ============

  async getStakingToken(): Promise<Address> {
    if (this.tokenAddress) return this.tokenAddress;

    this.tokenAddress = await this.publicClient.readContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "stakingToken",
    });
    return this.tokenAddress;
  }

  async getStakeInfo(user: Address): Promise<readonly StakePosition[]> {
    return this.publicClient.readContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "getStakeInfo",
      args: [user],
    });
  }

  async getStakeByStakeId(
    user: Address,
    stakeId: bigint
  ): Promise<StakePosition> {
    return this.publicClient.readContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "getStakeByStakeId",
      args: [user, stakeId],
    });
  }

  async calculateTotalRewards(user: Address): Promise<bigint> {
    return this.publicClient.readContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "calculateTotalRewards",
      args: [user],
    });
  }

  async calculateRewards(user: Address, stakeId: bigint): Promise<bigint> {
    return this.publicClient.readContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "calculateRewards",
      args: [user, stakeId],
    });
  }

  async getCurrentTier(user: Address, stakeId: bigint): Promise<number> {
    return this.publicClient.readContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "getCurrentTier",
      args: [user, stakeId],
    });
  }

  async getUserStakeCount(user: Address): Promise<bigint> {
    return this.publicClient.readContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "getUserStakeCount",
      args: [user],
    });
  }

  async getPendingWithdrawals(user: Address): Promise<readonly WithdrawRequest[]> {
    return this.publicClient.readContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "getPendingWithdrawals",
      args: [user],
    });
  }

  async getActivePendingWithdrawals(
    user: Address
  ): Promise<readonly WithdrawRequest[]> {
    return this.publicClient.readContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "getActivePendingWithdrawals",
      args: [user],
    });
  }

  async getTierConfig(tierIndex: number): Promise<TierConfig> {
    return this.publicClient.readContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "getTierConfig",
      args: [tierIndex],
    });
  }

  async getTotalStaked(): Promise<bigint> {
    return this.publicClient.readContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "totalStaked",
    });
  }

  async getTreasuryBalance(): Promise<bigint> {
    return this.publicClient.readContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "getTreasuryBalance",
    });
  }

  async isPaused(): Promise<boolean> {
    return this.publicClient.readContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "paused",
    });
  }

  async isEmergencyMode(): Promise<boolean> {
    return this.publicClient.readContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "emergencyMode",
    });
  }

  async isFounder(user: Address): Promise<boolean> {
    return this.publicClient.readContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "isFounder",
      args: [user],
    });
  }

  async getTokenBalance(user: Address): Promise<bigint> {
    const tokenAddress = await this.getStakingToken();
    return this.publicClient.readContract({
      address: tokenAddress,
      abi: ERC20_ABI,
      functionName: "balanceOf",
      args: [user],
    });
  }

  async getAllowance(user: Address): Promise<bigint> {
    const tokenAddress = await this.getStakingToken();
    return this.publicClient.readContract({
      address: tokenAddress,
      abi: ERC20_ABI,
      functionName: "allowance",
      args: [user, this.contractAddress],
    });
  }

  // ============ Formatted Read Methods ============

  async getStakingStats(): Promise<StakingStats> {
    const [totalStaked, treasuryBalance, isPaused, isEmergencyMode] =
      await Promise.all([
        this.getTotalStaked(),
        this.getTreasuryBalance(),
        this.isPaused(),
        this.isEmergencyMode(),
      ]);

    return {
      totalStaked: formatUnits(totalStaked, this.decimals),
      totalStakedRaw: totalStaked,
      treasuryBalance: formatUnits(treasuryBalance, this.decimals),
      treasuryBalanceRaw: treasuryBalance,
      isPaused,
      isEmergencyMode,
    };
  }

  async getUserStats(user: Address): Promise<UserStats> {
    const [positions, totalRewards, pendingWithdrawals, isFounder] =
      await Promise.all([
        this.getStakeInfo(user),
        this.calculateTotalRewards(user),
        this.getActivePendingWithdrawals(user),
        this.isFounder(user),
      ]);

    const now = Date.now();
    const formattedPositions: FormattedStakePosition[] = await Promise.all(
      positions.map(async (pos) => {
        const tier = await this.getCurrentTier(user, pos.stakeId);
        const startDate = new Date(Number(pos.startTime) * 1000);
        const stakingDays = Math.floor(
          (now - startDate.getTime()) / (1000 * 60 * 60 * 24)
        );

        return {
          stakeId: Number(pos.stakeId),
          amount: formatUnits(pos.amount, this.decimals),
          amountRaw: pos.amount,
          startTime: startDate,
          lastClaimTime: new Date(Number(pos.lastClaimTime) * 1000),
          stakingDays,
          currentTier: tier,
        };
      })
    );

    const formattedWithdrawals: FormattedWithdrawRequest[] =
      pendingWithdrawals.map((req) => {
        const availableAt = new Date(Number(req.availableAt) * 1000);
        const isReady = now >= availableAt.getTime();
        const daysUntilReady = isReady
          ? 0
          : Math.ceil((availableAt.getTime() - now) / (1000 * 60 * 60 * 24));

        return {
          stakeId: Number(req.stakeId),
          amount: formatUnits(req.amount, this.decimals),
          amountRaw: req.amount,
          requestTime: new Date(Number(req.requestTime) * 1000),
          availableAt,
          executed: req.executed,
          cancelled: req.cancelled,
          isReady,
          daysUntilReady,
        };
      });

    const totalStaked = positions.reduce((sum, pos) => sum + pos.amount, 0n);

    return {
      positions: formattedPositions,
      totalStaked: formatUnits(totalStaked, this.decimals),
      totalStakedRaw: totalStaked,
      totalRewards: formatUnits(totalRewards, this.decimals),
      totalRewardsRaw: totalRewards,
      pendingWithdrawals: formattedWithdrawals,
      isFounder,
    };
  }

  // ============ Write Methods ============

  private ensureWalletClient(): WalletClient<Transport, Chain, Account> {
    if (!this.walletClient) {
      throw new Error("Wallet client not configured. Use createWithWallet().");
    }
    return this.walletClient;
  }

  async approve(amount: bigint): Promise<`0x${string}`> {
    const walletClient = this.ensureWalletClient();
    const tokenAddress = await this.getStakingToken();

    const hash = await walletClient.writeContract({
      address: tokenAddress,
      abi: ERC20_ABI,
      functionName: "approve",
      args: [this.contractAddress, amount],
    });

    return hash;
  }

  async approveIfNeeded(amount: bigint): Promise<`0x${string}` | null> {
    const walletClient = this.ensureWalletClient();
    const allowance = await this.getAllowance(walletClient.account.address);

    if (allowance < amount) {
      return this.approve(amount);
    }
    return null;
  }

  async stake(amount: bigint): Promise<`0x${string}`> {
    const walletClient = this.ensureWalletClient();

    const hash = await walletClient.writeContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "stake",
      args: [amount],
    });

    return hash;
  }

  async stakeWithApproval(amount: bigint): Promise<{
    approvalHash?: `0x${string}`;
    stakeHash: `0x${string}`;
  }> {
    const approvalHash = await this.approveIfNeeded(amount);
    if (approvalHash) {
      await this.publicClient.waitForTransactionReceipt({ hash: approvalHash });
    }
    const stakeHash = await this.stake(amount);
    return { approvalHash: approvalHash ?? undefined, stakeHash };
  }

  async claimRewards(stakeId: bigint): Promise<`0x${string}`> {
    const walletClient = this.ensureWalletClient();

    return walletClient.writeContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "claimRewards",
      args: [stakeId],
    });
  }

  async claimAllRewards(): Promise<`0x${string}`> {
    const walletClient = this.ensureWalletClient();

    return walletClient.writeContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "claimAllRewards",
    });
  }

  async requestWithdraw(
    stakeId: bigint,
    amount: bigint
  ): Promise<`0x${string}`> {
    const walletClient = this.ensureWalletClient();

    return walletClient.writeContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "requestWithdraw",
      args: [stakeId, amount],
    });
  }

  async executeWithdraw(stakeId: bigint): Promise<`0x${string}`> {
    const walletClient = this.ensureWalletClient();

    return walletClient.writeContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "executeWithdraw",
      args: [stakeId],
    });
  }

  async cancelWithdrawRequest(stakeId: bigint): Promise<`0x${string}`> {
    const walletClient = this.ensureWalletClient();

    return walletClient.writeContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "cancelWithdrawRequest",
      args: [stakeId],
    });
  }

  async emergencyWithdraw(): Promise<`0x${string}`> {
    const walletClient = this.ensureWalletClient();

    return walletClient.writeContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "emergencyWithdraw",
    });
  }

  // ============ Admin Methods ============

  /**
   * Transfer stake from one user to another (admin only)
   * Used for web2->web3 user migration
   */
  async adminTransferStake(
    fromUser: Address,
    stakeId: bigint,
    toUser: Address
  ): Promise<`0x${string}`> {
    const walletClient = this.ensureWalletClient();

    return walletClient.writeContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "adminTransferStake",
      args: [fromUser, stakeId, toUser],
    });
  }

  /**
   * Deposit tokens to treasury for reward payments (admin only)
   */
  async depositTreasury(amount: bigint): Promise<`0x${string}`> {
    const walletClient = this.ensureWalletClient();

    return walletClient.writeContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "depositTreasury",
      args: [amount],
    });
  }

  /**
   * Withdraw tokens from treasury (admin only)
   */
  async withdrawTreasury(amount: bigint): Promise<`0x${string}`> {
    const walletClient = this.ensureWalletClient();

    return walletClient.writeContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "withdrawTreasury",
      args: [amount],
    });
  }

  /**
   * Pause the contract (admin only)
   */
  async pause(): Promise<`0x${string}`> {
    const walletClient = this.ensureWalletClient();

    return walletClient.writeContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "pause",
    });
  }

  /**
   * Unpause the contract (admin only)
   */
  async unpause(): Promise<`0x${string}`> {
    const walletClient = this.ensureWalletClient();

    return walletClient.writeContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "unpause",
    });
  }

  /**
   * Activate emergency mode - IRREVERSIBLE (admin only)
   */
  async emergencyShutdown(): Promise<`0x${string}`> {
    const walletClient = this.ensureWalletClient();

    return walletClient.writeContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "emergencyShutdown",
    });
  }

  // ============ Utility Methods ============

  parseAmount(amount: string): bigint {
    return parseUnits(amount, this.decimals);
  }

  formatAmount(amount: bigint): string {
    return formatUnits(amount, this.decimals);
  }

  getNoticePeriodDays(): number {
    return NOTICE_PERIOD_DAYS;
  }

  getContractAddress(): Address {
    return this.contractAddress;
  }
}
