"use client";

import { erc20Abi, maxUint256, zeroAddress, type Address } from "viem";
import { useAccount, useBalance, useReadContract } from "wagmi";
import { tokenAbi } from "@/lib/abis";
import { TOKEN_SYMBOL, TOKEN_DECIMALS } from "@/lib/constants";
import { chainConfig } from "@/lib/chains";
import { useActiveChainId, useInstance } from "@/components/instance-provider";
import { useTx } from "@/hooks/use-tx";

const LIVE = { refetchInterval: 12_000 } as const;

/**
 * The active instance's token symbol + name, read on-chain. Every instance
 * picks its own ticker at deploy time, so the UI must not hardcode one. Falls
 * back to the default symbol while the read resolves.
 */
export function useInstanceToken() {
  const a = useInstance();
  const chainId = useActiveChainId();
  const symbol = useReadContract({
    address: a.token,
    abi: tokenAbi,
    functionName: "symbol",
    chainId,
  });
  const name = useReadContract({
    address: a.token,
    abi: tokenAbi,
    functionName: "name",
    chainId,
  });
  const decimals = useReadContract({
    address: a.token,
    abi: tokenAbi,
    functionName: "decimals",
    chainId,
  });
  return {
    symbol: (symbol.data as string | undefined) || TOKEN_SYMBOL,
    name: name.data as string | undefined,
    // The project token mirrors its base asset's decimals (18 native, 6 USDC).
    decimals: (decimals.data as number | undefined) ?? TOKEN_DECIMALS,
  };
}

export function useTokenBalance(account?: Address) {
  const a = useInstance();
  const chainId = useActiveChainId();
  const { address } = useAccount();
  const owner = account ?? address;
  return useReadContract({
    address: a.token,
    abi: tokenAbi,
    functionName: "balanceOf",
    args: owner ? [owner] : undefined,
    chainId,
    query: { enabled: Boolean(owner), ...LIVE },
  });
}

/** Protocol-wide token stats: total supply + accrued (claimable) yield. */
export function useTokenStats() {
  const a = useInstance();
  const chainId = useActiveChainId();
  const totalSupply = useReadContract({
    address: a.token,
    abi: tokenAbi,
    functionName: "totalSupply",
    chainId,
    query: LIVE,
  });
  const yieldAccrued = useReadContract({
    address: a.token,
    abi: tokenAbi,
    functionName: "yieldAccrued",
    chainId,
    query: LIVE,
  });
  return {
    totalSupply: totalSupply.data,
    yieldAccrued: yieldAccrued.data,
    isLoading: totalSupply.isLoading || yieldAccrued.isLoading,
    refetch: () => {
      void totalSupply.refetch();
      void yieldAccrued.refetch();
    },
  };
}

export function useVotes(account?: Address) {
  const a = useInstance();
  const chainId = useActiveChainId();
  const { address } = useAccount();
  const owner = account ?? address;
  return useReadContract({
    address: a.token,
    abi: tokenAbi,
    functionName: "getVotes",
    args: owner ? [owner] : undefined,
    chainId,
    query: { enabled: Boolean(owner), ...LIVE },
  });
}

export function useDelegate(account?: Address) {
  const a = useInstance();
  const chainId = useActiveChainId();
  const { address } = useAccount();
  const owner = account ?? address;
  return useReadContract({
    address: a.token,
    abi: tokenAbi,
    functionName: "delegates",
    args: owner ? [owner] : undefined,
    chainId,
    query: { enabled: Boolean(owner) },
  });
}

export function useNativeBalance(account?: Address) {
  const chainId = useActiveChainId();
  const { address } = useAccount();
  const owner = account ?? address;
  return useBalance({
    address: owner,
    chainId,
    query: { enabled: Boolean(owner), ...LIVE },
  });
}

/** Wrapped-native balance + allowance granted to the token contract. */
export function useWrapped(account?: Address) {
  const a = useInstance();
  const chainId = useActiveChainId();
  const wrapped = chainConfig(chainId).wrappedToken;
  const { address } = useAccount();
  const owner = account ?? address;
  const enabled = Boolean(owner) && Boolean(wrapped);
  const balance = useReadContract({
    address: wrapped ?? zeroAddress,
    abi: erc20Abi,
    functionName: "balanceOf",
    args: owner ? [owner] : undefined,
    chainId,
    query: { enabled, ...LIVE },
  });
  const allowance = useReadContract({
    address: wrapped ?? zeroAddress,
    abi: erc20Abi,
    functionName: "allowance",
    args: owner ? [owner, a.token] : undefined,
    chainId,
    query: { enabled, ...LIVE },
  });
  return {
    balance: balance.data,
    allowance: allowance.data,
    refetch: () => {
      void balance.refetch();
      void allowance.refetch();
    },
  };
}

/* ----------------------------- Write actions ----------------------------- */

export function useApproveWrapped() {
  const a = useInstance();
  const chainId = useActiveChainId();
  const wrapped = chainConfig(chainId).wrappedToken;
  const tx = useTx();
  const approve = (amount: bigint = maxUint256) =>
    tx.run({
      address: wrapped ?? zeroAddress,
      abi: erc20Abi,
      functionName: "approve",
      args: [a.token, amount],
    });
  return { approve, ...tx };
}

/** Deposit: native (`mint(receiver){value}`) or wrapped (`mint(receiver, amount)`). */
export function useDeposit() {
  const a = useInstance();
  const { address } = useAccount();
  const tx = useTx();
  const deposit = (opts: {
    amount: bigint;
    mode: "native" | "wrapped";
    receiver?: Address;
  }) => {
    const receiver = opts.receiver ?? address ?? zeroAddress;
    if (opts.mode === "native") {
      return tx.run({
        address: a.token,
        abi: tokenAbi,
        functionName: "mint",
        args: [receiver],
        value: opts.amount,
      });
    }
    return tx.run({
      address: a.token,
      abi: tokenAbi,
      functionName: "mint",
      args: [receiver, opts.amount],
    });
  };
  return { deposit, ...tx };
}

/** Withdraw: burn the token and remit native to `receiver`. */
export function useWithdraw() {
  const a = useInstance();
  const { address } = useAccount();
  const tx = useTx();
  const withdraw = (amount: bigint, receiver?: Address) =>
    tx.run({
      address: a.token,
      abi: tokenAbi,
      functionName: "burn",
      args: [amount, receiver ?? address ?? zeroAddress],
    });
  return { withdraw, ...tx };
}

/** Manually (re)delegate voting power to an address (self by default). */
export function useDelegateVotes() {
  const a = useInstance();
  const { address } = useAccount();
  const tx = useTx();
  const delegate = (to?: Address) =>
    tx.run({
      address: a.token,
      abi: tokenAbi,
      functionName: "delegate",
      args: [to ?? address ?? zeroAddress],
    });
  return { delegate, ...tx };
}
