// src/client.ts
import {
  createPublicClient,
  http,
  formatUnits,
  parseUnits
} from "viem";

// src/abi.ts
var PROGRESSIVE_STAKING_ABI = [
  // Read functions
  {
    inputs: [{ name: "user", type: "address" }],
    name: "getStakeInfo",
    outputs: [
      {
        components: [
          { name: "stakeId", type: "uint256" },
          { name: "amount", type: "uint256" },
          { name: "startTime", type: "uint256" },
          { name: "lastClaimTime", type: "uint256" }
        ],
        name: "",
        type: "tuple[]"
      }
    ],
    stateMutability: "view",
    type: "function"
  },
  {
    inputs: [
      { name: "user", type: "address" },
      { name: "stakeId", type: "uint256" }
    ],
    name: "getStakeByStakeId",
    outputs: [
      {
        components: [
          { name: "stakeId", type: "uint256" },
          { name: "amount", type: "uint256" },
          { name: "startTime", type: "uint256" },
          { name: "lastClaimTime", type: "uint256" }
        ],
        name: "",
        type: "tuple"
      }
    ],
    stateMutability: "view",
    type: "function"
  },
  {
    inputs: [{ name: "user", type: "address" }],
    name: "calculateTotalRewards",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function"
  },
  {
    inputs: [
      { name: "user", type: "address" },
      { name: "stakeId", type: "uint256" }
    ],
    name: "calculateRewards",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function"
  },
  {
    inputs: [
      { name: "user", type: "address" },
      { name: "stakeId", type: "uint256" }
    ],
    name: "getCurrentTier",
    outputs: [{ name: "", type: "uint8" }],
    stateMutability: "view",
    type: "function"
  },
  {
    inputs: [{ name: "user", type: "address" }],
    name: "getUserStakeCount",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function"
  },
  {
    inputs: [{ name: "user", type: "address" }],
    name: "getPendingWithdrawals",
    outputs: [
      {
        components: [
          { name: "stakeId", type: "uint256" },
          { name: "amount", type: "uint256" },
          { name: "requestTime", type: "uint256" },
          { name: "availableAt", type: "uint256" },
          { name: "executed", type: "bool" }
        ],
        name: "",
        type: "tuple[]"
      }
    ],
    stateMutability: "view",
    type: "function"
  },
  {
    inputs: [{ name: "user", type: "address" }],
    name: "getActivePendingWithdrawals",
    outputs: [
      {
        components: [
          { name: "stakeId", type: "uint256" },
          { name: "amount", type: "uint256" },
          { name: "requestTime", type: "uint256" },
          { name: "availableAt", type: "uint256" },
          { name: "executed", type: "bool" }
        ],
        name: "",
        type: "tuple[]"
      }
    ],
    stateMutability: "view",
    type: "function"
  },
  {
    inputs: [{ name: "tierIndex", type: "uint8" }],
    name: "getTierConfig",
    outputs: [
      {
        components: [
          { name: "startTime", type: "uint256" },
          { name: "endTime", type: "uint256" },
          { name: "rate", type: "uint256" }
        ],
        name: "",
        type: "tuple"
      }
    ],
    stateMutability: "view",
    type: "function"
  },
  {
    inputs: [],
    name: "getTreasuryBalance",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function"
  },
  {
    inputs: [],
    name: "totalStaked",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function"
  },
  {
    inputs: [],
    name: "stakingToken",
    outputs: [{ name: "", type: "address" }],
    stateMutability: "view",
    type: "function"
  },
  {
    inputs: [],
    name: "emergencyMode",
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "view",
    type: "function"
  },
  {
    inputs: [],
    name: "paused",
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "view",
    type: "function"
  },
  {
    inputs: [{ name: "user", type: "address" }],
    name: "pendingWithdrawCount",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function"
  },
  {
    inputs: [{ name: "user", type: "address" }],
    name: "isFounder",
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "view",
    type: "function"
  },
  // Write functions
  {
    inputs: [{ name: "amount", type: "uint256" }],
    name: "stake",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function"
  },
  {
    inputs: [{ name: "stakeId", type: "uint256" }],
    name: "claimRewards",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function"
  },
  {
    inputs: [],
    name: "claimAllRewards",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function"
  },
  {
    inputs: [
      { name: "stakeId", type: "uint256" },
      { name: "amount", type: "uint256" }
    ],
    name: "requestWithdraw",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function"
  },
  {
    inputs: [{ name: "stakeId", type: "uint256" }],
    name: "executeWithdraw",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function"
  },
  {
    inputs: [{ name: "stakeId", type: "uint256" }],
    name: "cancelWithdrawRequest",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function"
  },
  {
    inputs: [],
    name: "emergencyWithdraw",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function"
  },
  // Admin functions
  {
    inputs: [
      { name: "fromUser", type: "address" },
      { name: "stakeId", type: "uint256" },
      { name: "toUser", type: "address" }
    ],
    name: "adminTransferStake",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function"
  },
  {
    inputs: [{ name: "amount", type: "uint256" }],
    name: "depositTreasury",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function"
  },
  {
    inputs: [{ name: "amount", type: "uint256" }],
    name: "withdrawTreasury",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function"
  },
  {
    inputs: [],
    name: "pause",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function"
  },
  {
    inputs: [],
    name: "unpause",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function"
  },
  {
    inputs: [],
    name: "emergencyShutdown",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function"
  },
  // Events
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: "user", type: "address" },
      { indexed: true, name: "stakeId", type: "uint256" },
      { indexed: false, name: "amount", type: "uint256" },
      { indexed: false, name: "timestamp", type: "uint256" }
    ],
    name: "Staked",
    type: "event"
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: "user", type: "address" },
      { indexed: true, name: "stakeId", type: "uint256" },
      { indexed: false, name: "amount", type: "uint256" },
      { indexed: false, name: "timestamp", type: "uint256" }
    ],
    name: "RewardsClaimed",
    type: "event"
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: "user", type: "address" },
      { indexed: false, name: "totalAmount", type: "uint256" },
      { indexed: false, name: "timestamp", type: "uint256" }
    ],
    name: "AllRewardsClaimed",
    type: "event"
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: "user", type: "address" },
      { indexed: true, name: "stakeId", type: "uint256" },
      { indexed: false, name: "amount", type: "uint256" },
      { indexed: false, name: "requestTime", type: "uint256" },
      { indexed: false, name: "availableAt", type: "uint256" }
    ],
    name: "WithdrawRequested",
    type: "event"
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: "user", type: "address" },
      { indexed: true, name: "stakeId", type: "uint256" },
      { indexed: false, name: "amount", type: "uint256" },
      { indexed: false, name: "timestamp", type: "uint256" }
    ],
    name: "WithdrawExecuted",
    type: "event"
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: "user", type: "address" },
      { indexed: true, name: "stakeId", type: "uint256" },
      { indexed: false, name: "amount", type: "uint256" },
      { indexed: false, name: "timestamp", type: "uint256" }
    ],
    name: "WithdrawCancelled",
    type: "event"
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: "user", type: "address" },
      { indexed: false, name: "principal", type: "uint256" },
      { indexed: false, name: "rewards", type: "uint256" },
      { indexed: false, name: "timestamp", type: "uint256" }
    ],
    name: "EmergencyWithdrawn",
    type: "event"
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: "fromUser", type: "address" },
      { indexed: true, name: "toUser", type: "address" },
      { indexed: true, name: "stakeId", type: "uint256" },
      { indexed: false, name: "timestamp", type: "uint256" }
    ],
    name: "StakeTransferred",
    type: "event"
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: "admin", type: "address" },
      { indexed: false, name: "amount", type: "uint256" },
      { indexed: false, name: "timestamp", type: "uint256" }
    ],
    name: "TreasuryDeposited",
    type: "event"
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: "admin", type: "address" },
      { indexed: false, name: "amount", type: "uint256" },
      { indexed: false, name: "timestamp", type: "uint256" }
    ],
    name: "TreasuryWithdrawn",
    type: "event"
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: "admin", type: "address" },
      { indexed: false, name: "timestamp", type: "uint256" }
    ],
    name: "ContractPaused",
    type: "event"
  },
  {
    anonymous: false,
    inputs: [
      { indexed: true, name: "admin", type: "address" },
      { indexed: false, name: "timestamp", type: "uint256" }
    ],
    name: "ContractUnpaused",
    type: "event"
  }
];
var ERC20_ABI = [
  {
    inputs: [
      { name: "spender", type: "address" },
      { name: "amount", type: "uint256" }
    ],
    name: "approve",
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "nonpayable",
    type: "function"
  },
  {
    inputs: [
      { name: "owner", type: "address" },
      { name: "spender", type: "address" }
    ],
    name: "allowance",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function"
  },
  {
    inputs: [{ name: "account", type: "address" }],
    name: "balanceOf",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function"
  },
  {
    inputs: [],
    name: "decimals",
    outputs: [{ name: "", type: "uint8" }],
    stateMutability: "view",
    type: "function"
  },
  {
    inputs: [],
    name: "symbol",
    outputs: [{ name: "", type: "string" }],
    stateMutability: "view",
    type: "function"
  }
];

// src/types.ts
var TIER_INFO = [
  { tier: 1, days: "0-180", rate: "0.5%", rateBps: 50 },
  { tier: 2, days: "180-360", rate: "0.7%", rateBps: 70 },
  { tier: 3, days: "360-720", rate: "2%", rateBps: 200 },
  { tier: 4, days: "720-1080", rate: "4%", rateBps: 400 },
  { tier: 5, days: "1080-1440", rate: "5%", rateBps: 500 },
  { tier: 6, days: "1440+", rate: "6%", rateBps: 600 }
];
var NOTICE_PERIOD_DAYS = 90;
var YEAR_DAYS = 360;

// src/client.ts
var ProgressiveStakingClient = class _ProgressiveStakingClient {
  constructor(config, publicClient, walletClient) {
    this.decimals = 18;
    this.contractAddress = config.contractAddress;
    this.tokenAddress = config.tokenAddress;
    this.publicClient = publicClient;
    this.walletClient = walletClient;
  }
  // ============ Static Factory Methods ============
  static create(config, rpcUrl, chain) {
    const publicClient = createPublicClient({
      chain,
      transport: http(rpcUrl)
    });
    return new _ProgressiveStakingClient(config, publicClient);
  }
  static createWithWallet(config, publicClient, walletClient) {
    return new _ProgressiveStakingClient(config, publicClient, walletClient);
  }
  // ============ Read Methods ============
  async getStakingToken() {
    if (this.tokenAddress) return this.tokenAddress;
    this.tokenAddress = await this.publicClient.readContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "stakingToken"
    });
    return this.tokenAddress;
  }
  async getStakeInfo(user) {
    return this.publicClient.readContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "getStakeInfo",
      args: [user]
    });
  }
  async getStakeByStakeId(user, stakeId) {
    return this.publicClient.readContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "getStakeByStakeId",
      args: [user, stakeId]
    });
  }
  async calculateTotalRewards(user) {
    return this.publicClient.readContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "calculateTotalRewards",
      args: [user]
    });
  }
  async calculateRewards(user, stakeId) {
    return this.publicClient.readContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "calculateRewards",
      args: [user, stakeId]
    });
  }
  async getCurrentTier(user, stakeId) {
    return this.publicClient.readContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "getCurrentTier",
      args: [user, stakeId]
    });
  }
  async getUserStakeCount(user) {
    return this.publicClient.readContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "getUserStakeCount",
      args: [user]
    });
  }
  async getPendingWithdrawals(user) {
    return this.publicClient.readContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "getPendingWithdrawals",
      args: [user]
    });
  }
  async getActivePendingWithdrawals(user) {
    return this.publicClient.readContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "getActivePendingWithdrawals",
      args: [user]
    });
  }
  async getTierConfig(tierIndex) {
    return this.publicClient.readContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "getTierConfig",
      args: [tierIndex]
    });
  }
  async getTotalStaked() {
    return this.publicClient.readContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "totalStaked"
    });
  }
  async getTreasuryBalance() {
    return this.publicClient.readContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "getTreasuryBalance"
    });
  }
  async isPaused() {
    return this.publicClient.readContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "paused"
    });
  }
  async isEmergencyMode() {
    return this.publicClient.readContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "emergencyMode"
    });
  }
  async isFounder(user) {
    return this.publicClient.readContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "isFounder",
      args: [user]
    });
  }
  async getTokenBalance(user) {
    const tokenAddress = await this.getStakingToken();
    return this.publicClient.readContract({
      address: tokenAddress,
      abi: ERC20_ABI,
      functionName: "balanceOf",
      args: [user]
    });
  }
  async getAllowance(user) {
    const tokenAddress = await this.getStakingToken();
    return this.publicClient.readContract({
      address: tokenAddress,
      abi: ERC20_ABI,
      functionName: "allowance",
      args: [user, this.contractAddress]
    });
  }
  // ============ Formatted Read Methods ============
  async getStakingStats() {
    const [totalStaked, treasuryBalance, isPaused, isEmergencyMode] = await Promise.all([
      this.getTotalStaked(),
      this.getTreasuryBalance(),
      this.isPaused(),
      this.isEmergencyMode()
    ]);
    return {
      totalStaked: formatUnits(totalStaked, this.decimals),
      totalStakedRaw: totalStaked,
      treasuryBalance: formatUnits(treasuryBalance, this.decimals),
      treasuryBalanceRaw: treasuryBalance,
      isPaused,
      isEmergencyMode
    };
  }
  async getUserStats(user) {
    const [positions, totalRewards, pendingWithdrawals, isFounder] = await Promise.all([
      this.getStakeInfo(user),
      this.calculateTotalRewards(user),
      this.getActivePendingWithdrawals(user),
      this.isFounder(user)
    ]);
    const now = Date.now();
    const formattedPositions = await Promise.all(
      positions.map(async (pos) => {
        const tier = await this.getCurrentTier(user, pos.stakeId);
        const startDate = new Date(Number(pos.startTime) * 1e3);
        const stakingDays = Math.floor(
          (now - startDate.getTime()) / (1e3 * 60 * 60 * 24)
        );
        return {
          stakeId: Number(pos.stakeId),
          amount: formatUnits(pos.amount, this.decimals),
          amountRaw: pos.amount,
          startTime: startDate,
          lastClaimTime: new Date(Number(pos.lastClaimTime) * 1e3),
          stakingDays,
          currentTier: tier
        };
      })
    );
    const formattedWithdrawals = pendingWithdrawals.map((req) => {
      const availableAt = new Date(Number(req.availableAt) * 1e3);
      const isReady = now >= availableAt.getTime();
      const daysUntilReady = isReady ? 0 : Math.ceil((availableAt.getTime() - now) / (1e3 * 60 * 60 * 24));
      return {
        stakeId: Number(req.stakeId),
        amount: formatUnits(req.amount, this.decimals),
        amountRaw: req.amount,
        requestTime: new Date(Number(req.requestTime) * 1e3),
        availableAt,
        executed: req.executed,
        isReady,
        daysUntilReady
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
      isFounder
    };
  }
  // ============ Write Methods ============
  ensureWalletClient() {
    if (!this.walletClient) {
      throw new Error("Wallet client not configured. Use createWithWallet().");
    }
    return this.walletClient;
  }
  async approve(amount) {
    const walletClient = this.ensureWalletClient();
    const tokenAddress = await this.getStakingToken();
    const hash = await walletClient.writeContract({
      address: tokenAddress,
      abi: ERC20_ABI,
      functionName: "approve",
      args: [this.contractAddress, amount]
    });
    return hash;
  }
  async approveIfNeeded(amount) {
    const walletClient = this.ensureWalletClient();
    const allowance = await this.getAllowance(walletClient.account.address);
    if (allowance < amount) {
      return this.approve(amount);
    }
    return null;
  }
  async stake(amount) {
    const walletClient = this.ensureWalletClient();
    const hash = await walletClient.writeContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "stake",
      args: [amount]
    });
    return hash;
  }
  async stakeWithApproval(amount) {
    const approvalHash = await this.approveIfNeeded(amount);
    if (approvalHash) {
      await this.publicClient.waitForTransactionReceipt({ hash: approvalHash });
    }
    const stakeHash = await this.stake(amount);
    return { approvalHash: approvalHash ?? void 0, stakeHash };
  }
  async claimRewards(stakeId) {
    const walletClient = this.ensureWalletClient();
    return walletClient.writeContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "claimRewards",
      args: [stakeId]
    });
  }
  async claimAllRewards() {
    const walletClient = this.ensureWalletClient();
    return walletClient.writeContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "claimAllRewards"
    });
  }
  async requestWithdraw(stakeId, amount) {
    const walletClient = this.ensureWalletClient();
    return walletClient.writeContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "requestWithdraw",
      args: [stakeId, amount]
    });
  }
  async executeWithdraw(stakeId) {
    const walletClient = this.ensureWalletClient();
    return walletClient.writeContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "executeWithdraw",
      args: [stakeId]
    });
  }
  async cancelWithdrawRequest(stakeId) {
    const walletClient = this.ensureWalletClient();
    return walletClient.writeContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "cancelWithdrawRequest",
      args: [stakeId]
    });
  }
  async emergencyWithdraw() {
    const walletClient = this.ensureWalletClient();
    return walletClient.writeContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "emergencyWithdraw"
    });
  }
  // ============ Admin Methods ============
  /**
   * Transfer stake from one user to another (admin only)
   * Used for web2->web3 user migration
   */
  async adminTransferStake(fromUser, stakeId, toUser) {
    const walletClient = this.ensureWalletClient();
    return walletClient.writeContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "adminTransferStake",
      args: [fromUser, stakeId, toUser]
    });
  }
  /**
   * Deposit tokens to treasury for reward payments (admin only)
   */
  async depositTreasury(amount) {
    const walletClient = this.ensureWalletClient();
    return walletClient.writeContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "depositTreasury",
      args: [amount]
    });
  }
  /**
   * Withdraw tokens from treasury (admin only)
   */
  async withdrawTreasury(amount) {
    const walletClient = this.ensureWalletClient();
    return walletClient.writeContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "withdrawTreasury",
      args: [amount]
    });
  }
  /**
   * Pause the contract (admin only)
   */
  async pause() {
    const walletClient = this.ensureWalletClient();
    return walletClient.writeContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "pause"
    });
  }
  /**
   * Unpause the contract (admin only)
   */
  async unpause() {
    const walletClient = this.ensureWalletClient();
    return walletClient.writeContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "unpause"
    });
  }
  /**
   * Activate emergency mode - IRREVERSIBLE (admin only)
   */
  async emergencyShutdown() {
    const walletClient = this.ensureWalletClient();
    return walletClient.writeContract({
      address: this.contractAddress,
      abi: PROGRESSIVE_STAKING_ABI,
      functionName: "emergencyShutdown"
    });
  }
  // ============ Utility Methods ============
  parseAmount(amount) {
    return parseUnits(amount, this.decimals);
  }
  formatAmount(amount) {
    return formatUnits(amount, this.decimals);
  }
  getNoticePeriodDays() {
    return NOTICE_PERIOD_DAYS;
  }
  getContractAddress() {
    return this.contractAddress;
  }
};

// src/config.ts
var CONTRACTS = {
  /** Sepolia testnet staking contract */
  SEPOLIA: "0x...",
  /** Ethereum mainnet staking contract */
  MAINNET: "0x..."
};
var RPC_URLS = {
  SEPOLIA: "https://eth-sepolia.g.alchemy.com/v2/YOUR_API_KEY",
  MAINNET: "https://eth-mainnet.g.alchemy.com/v2/YOUR_API_KEY"
};
var TOKEN_SYMBOL = "MAIT";
var TOKEN_DECIMALS = 18;
export {
  CONTRACTS,
  ERC20_ABI,
  NOTICE_PERIOD_DAYS,
  PROGRESSIVE_STAKING_ABI,
  ProgressiveStakingClient,
  RPC_URLS,
  TIER_INFO,
  TOKEN_DECIMALS,
  TOKEN_SYMBOL,
  YEAR_DAYS
};
