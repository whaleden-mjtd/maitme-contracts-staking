import type { Address } from "viem";

export interface StakePosition {
  readonly stakeId: bigint;
  readonly amount: bigint;
  readonly startTime: bigint;
  readonly lastClaimTime: bigint;
}

export interface WithdrawRequest {
  readonly stakeId: bigint;
  readonly amount: bigint;
  readonly requestTime: bigint;
  readonly availableAt: bigint;
  readonly executed: boolean;
  readonly cancelled: boolean;
}

export interface TierConfig {
  readonly startTime: bigint;
  readonly endTime: bigint;
  readonly rate: bigint;
}

export interface FormattedStakePosition {
  stakeId: number;
  amount: string;
  amountRaw: bigint;
  startTime: Date;
  lastClaimTime: Date;
  stakingDays: number;
  currentTier: number;
}

export interface FormattedWithdrawRequest {
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

export interface StakingStats {
  totalStaked: string;
  totalStakedRaw: bigint;
  treasuryBalance: string;
  treasuryBalanceRaw: bigint;
  isPaused: boolean;
  isEmergencyMode: boolean;
}

export interface UserStats {
  positions: FormattedStakePosition[];
  totalStaked: string;
  totalStakedRaw: bigint;
  totalRewards: string;
  totalRewardsRaw: bigint;
  pendingWithdrawals: FormattedWithdrawRequest[];
  isFounder: boolean;
}

export interface StakingClientConfig {
  contractAddress: Address;
  tokenAddress?: Address;
}

export const TIER_INFO = [
  { tier: 1, days: "0-180", rate: "0.5%", rateBps: 50 },
  { tier: 2, days: "180-360", rate: "0.7%", rateBps: 70 },
  { tier: 3, days: "360-720", rate: "2%", rateBps: 200 },
  { tier: 4, days: "720-1080", rate: "4%", rateBps: 400 },
  { tier: 5, days: "1080-1440", rate: "5%", rateBps: 500 },
  { tier: 6, days: "1440+", rate: "6%", rateBps: 600 },
] as const;

export const NOTICE_PERIOD_DAYS = 90;
export const YEAR_DAYS = 360;
