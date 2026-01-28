import { Address, PublicClient, WalletClient, Transport, Chain, Account } from 'viem';

interface StakePosition {
    readonly stakeId: bigint;
    readonly amount: bigint;
    readonly startTime: bigint;
    readonly lastClaimTime: bigint;
}
interface WithdrawRequest {
    readonly stakeId: bigint;
    readonly amount: bigint;
    readonly requestTime: bigint;
    readonly availableAt: bigint;
    readonly executed: boolean;
    readonly cancelled: boolean;
}
interface TierConfig {
    readonly startTime: bigint;
    readonly endTime: bigint;
    readonly rate: bigint;
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
interface StakingStats {
    totalStaked: string;
    totalStakedRaw: bigint;
    treasuryBalance: string;
    treasuryBalanceRaw: bigint;
    isPaused: boolean;
    isEmergencyMode: boolean;
}
interface UserStats {
    positions: FormattedStakePosition[];
    totalStaked: string;
    totalStakedRaw: bigint;
    totalRewards: string;
    totalRewardsRaw: bigint;
    pendingWithdrawals: FormattedWithdrawRequest[];
    isFounder: boolean;
}
interface StakingClientConfig {
    contractAddress: Address;
    tokenAddress?: Address;
}
declare const TIER_INFO: readonly [{
    readonly tier: 1;
    readonly days: "0-180";
    readonly rate: "0.5%";
    readonly rateBps: 50;
}, {
    readonly tier: 2;
    readonly days: "180-360";
    readonly rate: "0.7%";
    readonly rateBps: 70;
}, {
    readonly tier: 3;
    readonly days: "360-720";
    readonly rate: "2%";
    readonly rateBps: 200;
}, {
    readonly tier: 4;
    readonly days: "720-1080";
    readonly rate: "4%";
    readonly rateBps: 400;
}, {
    readonly tier: 5;
    readonly days: "1080-1440";
    readonly rate: "5%";
    readonly rateBps: 500;
}, {
    readonly tier: 6;
    readonly days: "1440+";
    readonly rate: "6%";
    readonly rateBps: 600;
}];
declare const NOTICE_PERIOD_DAYS = 90;
declare const YEAR_DAYS = 360;

declare class ProgressiveStakingClient {
    private publicClient;
    private walletClient?;
    private contractAddress;
    private tokenAddress?;
    private decimals;
    constructor(config: StakingClientConfig, publicClient: PublicClient, walletClient?: WalletClient<Transport, Chain, Account>);
    static create(config: StakingClientConfig, rpcUrl: string, chain: Chain): ProgressiveStakingClient;
    static createWithWallet(config: StakingClientConfig, publicClient: PublicClient, walletClient: WalletClient<Transport, Chain, Account>): ProgressiveStakingClient;
    getStakingToken(): Promise<Address>;
    getStakeInfo(user: Address): Promise<readonly StakePosition[]>;
    getStakeByStakeId(user: Address, stakeId: bigint): Promise<StakePosition>;
    calculateTotalRewards(user: Address): Promise<bigint>;
    calculateRewards(user: Address, stakeId: bigint): Promise<bigint>;
    getCurrentTier(user: Address, stakeId: bigint): Promise<number>;
    getUserStakeCount(user: Address): Promise<bigint>;
    getPendingWithdrawals(user: Address): Promise<readonly WithdrawRequest[]>;
    getActivePendingWithdrawals(user: Address): Promise<readonly WithdrawRequest[]>;
    getTierConfig(tierIndex: number): Promise<TierConfig>;
    getTotalStaked(): Promise<bigint>;
    getTreasuryBalance(): Promise<bigint>;
    isPaused(): Promise<boolean>;
    isEmergencyMode(): Promise<boolean>;
    isFounder(user: Address): Promise<boolean>;
    getTokenBalance(user: Address): Promise<bigint>;
    getAllowance(user: Address): Promise<bigint>;
    getStakingStats(): Promise<StakingStats>;
    getUserStats(user: Address): Promise<UserStats>;
    private ensureWalletClient;
    approve(amount: bigint): Promise<`0x${string}`>;
    approveIfNeeded(amount: bigint): Promise<`0x${string}` | null>;
    stake(amount: bigint): Promise<`0x${string}`>;
    stakeWithApproval(amount: bigint): Promise<{
        approvalHash?: `0x${string}`;
        stakeHash: `0x${string}`;
    }>;
    claimRewards(stakeId: bigint): Promise<`0x${string}`>;
    claimAllRewards(): Promise<`0x${string}`>;
    requestWithdraw(stakeId: bigint, amount: bigint): Promise<`0x${string}`>;
    executeWithdraw(stakeId: bigint): Promise<`0x${string}`>;
    cancelWithdrawRequest(stakeId: bigint): Promise<`0x${string}`>;
    emergencyWithdraw(): Promise<`0x${string}`>;
    /**
     * Transfer stake from one user to another (admin only)
     * Used for web2->web3 user migration
     */
    adminTransferStake(fromUser: Address, stakeId: bigint, toUser: Address): Promise<`0x${string}`>;
    /**
     * Deposit tokens to treasury for reward payments (admin only)
     */
    depositTreasury(amount: bigint): Promise<`0x${string}`>;
    /**
     * Withdraw tokens from treasury (admin only)
     */
    withdrawTreasury(amount: bigint): Promise<`0x${string}`>;
    /**
     * Pause the contract (admin only)
     */
    pause(): Promise<`0x${string}`>;
    /**
     * Unpause the contract (admin only)
     */
    unpause(): Promise<`0x${string}`>;
    /**
     * Activate emergency mode - IRREVERSIBLE (admin only)
     */
    emergencyShutdown(): Promise<`0x${string}`>;
    parseAmount(amount: string): bigint;
    formatAmount(amount: bigint): string;
    getNoticePeriodDays(): number;
    getContractAddress(): Address;
}

declare const PROGRESSIVE_STAKING_ABI: readonly [{
    readonly inputs: readonly [{
        readonly name: "user";
        readonly type: "address";
    }];
    readonly name: "getStakeInfo";
    readonly outputs: readonly [{
        readonly components: readonly [{
            readonly name: "stakeId";
            readonly type: "uint256";
        }, {
            readonly name: "amount";
            readonly type: "uint256";
        }, {
            readonly name: "startTime";
            readonly type: "uint256";
        }, {
            readonly name: "lastClaimTime";
            readonly type: "uint256";
        }];
        readonly name: "";
        readonly type: "tuple[]";
    }];
    readonly stateMutability: "view";
    readonly type: "function";
}, {
    readonly inputs: readonly [{
        readonly name: "user";
        readonly type: "address";
    }, {
        readonly name: "stakeId";
        readonly type: "uint256";
    }];
    readonly name: "getStakeByStakeId";
    readonly outputs: readonly [{
        readonly components: readonly [{
            readonly name: "stakeId";
            readonly type: "uint256";
        }, {
            readonly name: "amount";
            readonly type: "uint256";
        }, {
            readonly name: "startTime";
            readonly type: "uint256";
        }, {
            readonly name: "lastClaimTime";
            readonly type: "uint256";
        }];
        readonly name: "";
        readonly type: "tuple";
    }];
    readonly stateMutability: "view";
    readonly type: "function";
}, {
    readonly inputs: readonly [{
        readonly name: "user";
        readonly type: "address";
    }];
    readonly name: "calculateTotalRewards";
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
    }];
    readonly stateMutability: "view";
    readonly type: "function";
}, {
    readonly inputs: readonly [{
        readonly name: "user";
        readonly type: "address";
    }, {
        readonly name: "stakeId";
        readonly type: "uint256";
    }];
    readonly name: "calculateRewards";
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
    }];
    readonly stateMutability: "view";
    readonly type: "function";
}, {
    readonly inputs: readonly [{
        readonly name: "user";
        readonly type: "address";
    }, {
        readonly name: "stakeId";
        readonly type: "uint256";
    }];
    readonly name: "getCurrentTier";
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint8";
    }];
    readonly stateMutability: "view";
    readonly type: "function";
}, {
    readonly inputs: readonly [{
        readonly name: "user";
        readonly type: "address";
    }];
    readonly name: "getUserStakeCount";
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
    }];
    readonly stateMutability: "view";
    readonly type: "function";
}, {
    readonly inputs: readonly [{
        readonly name: "user";
        readonly type: "address";
    }];
    readonly name: "getPendingWithdrawals";
    readonly outputs: readonly [{
        readonly components: readonly [{
            readonly name: "stakeId";
            readonly type: "uint256";
        }, {
            readonly name: "amount";
            readonly type: "uint256";
        }, {
            readonly name: "requestTime";
            readonly type: "uint256";
        }, {
            readonly name: "availableAt";
            readonly type: "uint256";
        }, {
            readonly name: "executed";
            readonly type: "bool";
        }, {
            readonly name: "cancelled";
            readonly type: "bool";
        }];
        readonly name: "";
        readonly type: "tuple[]";
    }];
    readonly stateMutability: "view";
    readonly type: "function";
}, {
    readonly inputs: readonly [{
        readonly name: "user";
        readonly type: "address";
    }];
    readonly name: "getActivePendingWithdrawals";
    readonly outputs: readonly [{
        readonly components: readonly [{
            readonly name: "stakeId";
            readonly type: "uint256";
        }, {
            readonly name: "amount";
            readonly type: "uint256";
        }, {
            readonly name: "requestTime";
            readonly type: "uint256";
        }, {
            readonly name: "availableAt";
            readonly type: "uint256";
        }, {
            readonly name: "executed";
            readonly type: "bool";
        }, {
            readonly name: "cancelled";
            readonly type: "bool";
        }];
        readonly name: "";
        readonly type: "tuple[]";
    }];
    readonly stateMutability: "view";
    readonly type: "function";
}, {
    readonly inputs: readonly [{
        readonly name: "tierIndex";
        readonly type: "uint8";
    }];
    readonly name: "getTierConfig";
    readonly outputs: readonly [{
        readonly components: readonly [{
            readonly name: "startTime";
            readonly type: "uint256";
        }, {
            readonly name: "endTime";
            readonly type: "uint256";
        }, {
            readonly name: "rate";
            readonly type: "uint256";
        }];
        readonly name: "";
        readonly type: "tuple";
    }];
    readonly stateMutability: "view";
    readonly type: "function";
}, {
    readonly inputs: readonly [];
    readonly name: "getTreasuryBalance";
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
    }];
    readonly stateMutability: "view";
    readonly type: "function";
}, {
    readonly inputs: readonly [];
    readonly name: "totalStaked";
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
    }];
    readonly stateMutability: "view";
    readonly type: "function";
}, {
    readonly inputs: readonly [];
    readonly name: "stakingToken";
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "address";
    }];
    readonly stateMutability: "view";
    readonly type: "function";
}, {
    readonly inputs: readonly [];
    readonly name: "emergencyMode";
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
    }];
    readonly stateMutability: "view";
    readonly type: "function";
}, {
    readonly inputs: readonly [];
    readonly name: "paused";
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
    }];
    readonly stateMutability: "view";
    readonly type: "function";
}, {
    readonly inputs: readonly [{
        readonly name: "user";
        readonly type: "address";
    }];
    readonly name: "pendingWithdrawCount";
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
    }];
    readonly stateMutability: "view";
    readonly type: "function";
}, {
    readonly inputs: readonly [{
        readonly name: "user";
        readonly type: "address";
    }];
    readonly name: "isFounder";
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
    }];
    readonly stateMutability: "view";
    readonly type: "function";
}, {
    readonly inputs: readonly [{
        readonly name: "amount";
        readonly type: "uint256";
    }];
    readonly name: "stake";
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
    readonly type: "function";
}, {
    readonly inputs: readonly [{
        readonly name: "stakeId";
        readonly type: "uint256";
    }];
    readonly name: "claimRewards";
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
    readonly type: "function";
}, {
    readonly inputs: readonly [];
    readonly name: "claimAllRewards";
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
    readonly type: "function";
}, {
    readonly inputs: readonly [{
        readonly name: "stakeId";
        readonly type: "uint256";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
    }];
    readonly name: "requestWithdraw";
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
    readonly type: "function";
}, {
    readonly inputs: readonly [{
        readonly name: "stakeId";
        readonly type: "uint256";
    }];
    readonly name: "executeWithdraw";
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
    readonly type: "function";
}, {
    readonly inputs: readonly [{
        readonly name: "stakeId";
        readonly type: "uint256";
    }];
    readonly name: "cancelWithdrawRequest";
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
    readonly type: "function";
}, {
    readonly inputs: readonly [];
    readonly name: "emergencyWithdraw";
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
    readonly type: "function";
}, {
    readonly inputs: readonly [{
        readonly name: "fromUser";
        readonly type: "address";
    }, {
        readonly name: "stakeId";
        readonly type: "uint256";
    }, {
        readonly name: "toUser";
        readonly type: "address";
    }];
    readonly name: "adminTransferStake";
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
    readonly type: "function";
}, {
    readonly inputs: readonly [{
        readonly name: "amount";
        readonly type: "uint256";
    }];
    readonly name: "depositTreasury";
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
    readonly type: "function";
}, {
    readonly inputs: readonly [{
        readonly name: "amount";
        readonly type: "uint256";
    }];
    readonly name: "withdrawTreasury";
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
    readonly type: "function";
}, {
    readonly inputs: readonly [];
    readonly name: "pause";
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
    readonly type: "function";
}, {
    readonly inputs: readonly [];
    readonly name: "unpause";
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
    readonly type: "function";
}, {
    readonly inputs: readonly [];
    readonly name: "emergencyShutdown";
    readonly outputs: readonly [];
    readonly stateMutability: "nonpayable";
    readonly type: "function";
}, {
    readonly anonymous: false;
    readonly inputs: readonly [{
        readonly indexed: true;
        readonly name: "user";
        readonly type: "address";
    }, {
        readonly indexed: true;
        readonly name: "stakeId";
        readonly type: "uint256";
    }, {
        readonly indexed: false;
        readonly name: "amount";
        readonly type: "uint256";
    }, {
        readonly indexed: false;
        readonly name: "timestamp";
        readonly type: "uint256";
    }];
    readonly name: "Staked";
    readonly type: "event";
}, {
    readonly anonymous: false;
    readonly inputs: readonly [{
        readonly indexed: true;
        readonly name: "user";
        readonly type: "address";
    }, {
        readonly indexed: true;
        readonly name: "stakeId";
        readonly type: "uint256";
    }, {
        readonly indexed: false;
        readonly name: "amount";
        readonly type: "uint256";
    }, {
        readonly indexed: false;
        readonly name: "timestamp";
        readonly type: "uint256";
    }];
    readonly name: "RewardsClaimed";
    readonly type: "event";
}, {
    readonly anonymous: false;
    readonly inputs: readonly [{
        readonly indexed: true;
        readonly name: "user";
        readonly type: "address";
    }, {
        readonly indexed: false;
        readonly name: "totalAmount";
        readonly type: "uint256";
    }, {
        readonly indexed: false;
        readonly name: "timestamp";
        readonly type: "uint256";
    }];
    readonly name: "AllRewardsClaimed";
    readonly type: "event";
}, {
    readonly anonymous: false;
    readonly inputs: readonly [{
        readonly indexed: true;
        readonly name: "user";
        readonly type: "address";
    }, {
        readonly indexed: true;
        readonly name: "stakeId";
        readonly type: "uint256";
    }, {
        readonly indexed: false;
        readonly name: "amount";
        readonly type: "uint256";
    }, {
        readonly indexed: false;
        readonly name: "requestTime";
        readonly type: "uint256";
    }, {
        readonly indexed: false;
        readonly name: "availableAt";
        readonly type: "uint256";
    }];
    readonly name: "WithdrawRequested";
    readonly type: "event";
}, {
    readonly anonymous: false;
    readonly inputs: readonly [{
        readonly indexed: true;
        readonly name: "user";
        readonly type: "address";
    }, {
        readonly indexed: true;
        readonly name: "stakeId";
        readonly type: "uint256";
    }, {
        readonly indexed: false;
        readonly name: "amount";
        readonly type: "uint256";
    }, {
        readonly indexed: false;
        readonly name: "timestamp";
        readonly type: "uint256";
    }];
    readonly name: "WithdrawExecuted";
    readonly type: "event";
}, {
    readonly anonymous: false;
    readonly inputs: readonly [{
        readonly indexed: true;
        readonly name: "user";
        readonly type: "address";
    }, {
        readonly indexed: true;
        readonly name: "stakeId";
        readonly type: "uint256";
    }, {
        readonly indexed: false;
        readonly name: "amount";
        readonly type: "uint256";
    }, {
        readonly indexed: false;
        readonly name: "timestamp";
        readonly type: "uint256";
    }];
    readonly name: "WithdrawCancelled";
    readonly type: "event";
}, {
    readonly anonymous: false;
    readonly inputs: readonly [{
        readonly indexed: true;
        readonly name: "user";
        readonly type: "address";
    }, {
        readonly indexed: false;
        readonly name: "principal";
        readonly type: "uint256";
    }, {
        readonly indexed: false;
        readonly name: "rewards";
        readonly type: "uint256";
    }, {
        readonly indexed: false;
        readonly name: "timestamp";
        readonly type: "uint256";
    }];
    readonly name: "EmergencyWithdrawn";
    readonly type: "event";
}, {
    readonly anonymous: false;
    readonly inputs: readonly [{
        readonly indexed: true;
        readonly name: "fromUser";
        readonly type: "address";
    }, {
        readonly indexed: true;
        readonly name: "toUser";
        readonly type: "address";
    }, {
        readonly indexed: true;
        readonly name: "stakeId";
        readonly type: "uint256";
    }, {
        readonly indexed: false;
        readonly name: "timestamp";
        readonly type: "uint256";
    }];
    readonly name: "StakeTransferred";
    readonly type: "event";
}, {
    readonly anonymous: false;
    readonly inputs: readonly [{
        readonly indexed: true;
        readonly name: "admin";
        readonly type: "address";
    }, {
        readonly indexed: false;
        readonly name: "amount";
        readonly type: "uint256";
    }, {
        readonly indexed: false;
        readonly name: "timestamp";
        readonly type: "uint256";
    }];
    readonly name: "TreasuryDeposited";
    readonly type: "event";
}, {
    readonly anonymous: false;
    readonly inputs: readonly [{
        readonly indexed: true;
        readonly name: "admin";
        readonly type: "address";
    }, {
        readonly indexed: false;
        readonly name: "amount";
        readonly type: "uint256";
    }, {
        readonly indexed: false;
        readonly name: "timestamp";
        readonly type: "uint256";
    }];
    readonly name: "TreasuryWithdrawn";
    readonly type: "event";
}, {
    readonly anonymous: false;
    readonly inputs: readonly [{
        readonly indexed: true;
        readonly name: "admin";
        readonly type: "address";
    }, {
        readonly indexed: false;
        readonly name: "timestamp";
        readonly type: "uint256";
    }];
    readonly name: "ContractPaused";
    readonly type: "event";
}, {
    readonly anonymous: false;
    readonly inputs: readonly [{
        readonly indexed: true;
        readonly name: "admin";
        readonly type: "address";
    }, {
        readonly indexed: false;
        readonly name: "timestamp";
        readonly type: "uint256";
    }];
    readonly name: "ContractUnpaused";
    readonly type: "event";
}];
declare const ERC20_ABI: readonly [{
    readonly inputs: readonly [{
        readonly name: "spender";
        readonly type: "address";
    }, {
        readonly name: "amount";
        readonly type: "uint256";
    }];
    readonly name: "approve";
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "bool";
    }];
    readonly stateMutability: "nonpayable";
    readonly type: "function";
}, {
    readonly inputs: readonly [{
        readonly name: "owner";
        readonly type: "address";
    }, {
        readonly name: "spender";
        readonly type: "address";
    }];
    readonly name: "allowance";
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
    }];
    readonly stateMutability: "view";
    readonly type: "function";
}, {
    readonly inputs: readonly [{
        readonly name: "account";
        readonly type: "address";
    }];
    readonly name: "balanceOf";
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint256";
    }];
    readonly stateMutability: "view";
    readonly type: "function";
}, {
    readonly inputs: readonly [];
    readonly name: "decimals";
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "uint8";
    }];
    readonly stateMutability: "view";
    readonly type: "function";
}, {
    readonly inputs: readonly [];
    readonly name: "symbol";
    readonly outputs: readonly [{
        readonly name: "";
        readonly type: "string";
    }];
    readonly stateMutability: "view";
    readonly type: "function";
}];

/**
 * Contract addresses for different networks
 */
declare const CONTRACTS: {
    /** Sepolia testnet staking contract */
    readonly SEPOLIA: Address;
    /** Ethereum mainnet staking contract */
    readonly MAINNET: Address;
};
/**
 * RPC endpoints (replace YOUR_API_KEY with actual keys)
 */
declare const RPC_URLS: {
    readonly SEPOLIA: "https://eth-sepolia.g.alchemy.com/v2/YOUR_API_KEY";
    readonly MAINNET: "https://eth-mainnet.g.alchemy.com/v2/YOUR_API_KEY";
};
/**
 * Token symbol
 */
declare const TOKEN_SYMBOL = "MAIT";
/**
 * Token decimals
 */
declare const TOKEN_DECIMALS = 18;

export { CONTRACTS, ERC20_ABI, type FormattedStakePosition, type FormattedWithdrawRequest, NOTICE_PERIOD_DAYS, PROGRESSIVE_STAKING_ABI, ProgressiveStakingClient, RPC_URLS, type StakePosition, type StakingClientConfig, type StakingStats, TIER_INFO, TOKEN_DECIMALS, TOKEN_SYMBOL, type TierConfig, type UserStats, type WithdrawRequest, YEAR_DAYS };
