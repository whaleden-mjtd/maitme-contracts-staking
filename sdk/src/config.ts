import type { Address } from "viem";

/**
 * Contract addresses for different networks
 */
export const CONTRACTS = {
  /** Sepolia testnet staking contract */
  SEPOLIA: "0x..." as Address,
  /** Ethereum mainnet staking contract */
  MAINNET: "0x..." as Address,
} as const;

/**
 * RPC endpoints (replace YOUR_API_KEY with actual keys)
 */
export const RPC_URLS = {
  SEPOLIA: "https://eth-sepolia.g.alchemy.com/v2/YOUR_API_KEY",
  MAINNET: "https://eth-mainnet.g.alchemy.com/v2/YOUR_API_KEY",
} as const;

/**
 * Token symbol
 */
export const TOKEN_SYMBOL = "MAIT";

/**
 * Token decimals
 */
export const TOKEN_DECIMALS = 18;
