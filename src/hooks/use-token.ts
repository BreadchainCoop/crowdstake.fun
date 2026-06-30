"use client";

import { erc20Abi, maxUint256, zeroAddress, type Address } from "viem";
import { useAccount, useBalance, useReadContract } from "wagmi";
import { tokenAbi } from "@/lib/abis";
import { ADDRESSES, CHAIN_ID, WXDAI } from "@/lib/constants";
import { useTx } from "@/hooks/use-tx";

const LIVE = { refetchInterval: 12_000 } as const;

export function useTokenBalance(account?: Address) {
  const { address } = useAccount();
  const owner = account ?? address;
  return useReadContract({
    address: ADDRESSES.token,
    abi: tokenAbi,
    functionName: "balanceOf",
    args: owner ? [owner] : undefined,
    chainId: CHAIN_ID,
    query: { enabled: Boolean(owner), ...LIVE },
  });
}

/** Protocol-wide token stats: total supply + accrued (claimable) yield. */
export function useTokenStats() {
  const totalSupply = useReadContract({
    address: ADDRESSES.token,
    abi: tokenAbi,
    functionName: "totalSupply",
    chainId: CHAIN_ID,
    query: LIVE,
  });
  const yieldAccrued = useReadContract({
    address: ADDRESSES.token,
    abi: tokenAbi,
    functionName: "yieldAccrued",
    chainId: CHAIN_ID,
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
  const { address } = useAccount();
  const owner = account ?? address;
  return useReadContract({
    address: ADDRESSES.token,
    abi: tokenAbi,
    functionName: "getVotes",
    args: owner ? [owner] : undefined,
    chainId: CHAIN_ID,
    query: { enabled: Boolean(owner), ...LIVE },
  });
}

export function useDelegate(account?: Address) {
  const { address } = useAccount();
  const owner = account ?? address;
  return useReadContract({
    address: ADDRESSES.token,
    abi: tokenAbi,
    functionName: "delegates",
    args: owner ? [owner] : undefined,
    chainId: CHAIN_ID,
    query: { enabled: Boolean(owner) },
  });
}

export function useNativeBalance(account?: Address) {
  const { address } = useAccount();
  const owner = account ?? address;
  return useBalance({
    address: owner,
    chainId: CHAIN_ID,
    query: { enabled: Boolean(owner), ...LIVE },
  });
}

/** wxDAI balance + current allowance granted to the token contract. */
export function useWxdai(account?: Address) {
  const { address } = useAccount();
  const owner = account ?? address;
  const balance = useReadContract({
    address: WXDAI,
    abi: erc20Abi,
    functionName: "balanceOf",
    args: owner ? [owner] : undefined,
    chainId: CHAIN_ID,
    query: { enabled: Boolean(owner), ...LIVE },
  });
  const allowance = useReadContract({
    address: WXDAI,
    abi: erc20Abi,
    functionName: "allowance",
    args: owner ? [owner, ADDRESSES.token] : undefined,
    chainId: CHAIN_ID,
    query: { enabled: Boolean(owner) },
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

export function useApproveWxdai() {
  const tx = useTx();
  const approve = (amount: bigint = maxUint256) =>
    tx.run({
      address: WXDAI,
      abi: erc20Abi,
      functionName: "approve",
      args: [ADDRESSES.token, amount],
    });
  return { approve, ...tx };
}

/** Deposit: native xDAI (`mint(receiver){value}`) or wxDAI (`mint(receiver, amount)`). */
export function useDeposit() {
  const { address } = useAccount();
  const tx = useTx();
  const deposit = (opts: {
    amount: bigint;
    mode: "native" | "wxdai";
    receiver?: Address;
  }) => {
    const receiver = opts.receiver ?? address ?? zeroAddress;
    if (opts.mode === "native") {
      return tx.run({
        address: ADDRESSES.token,
        abi: tokenAbi,
        functionName: "mint",
        args: [receiver],
        value: opts.amount,
      });
    }
    return tx.run({
      address: ADDRESSES.token,
      abi: tokenAbi,
      functionName: "mint",
      args: [receiver, opts.amount],
    });
  };
  return { deposit, ...tx };
}

/** Withdraw: burn CSTAKE and remit native xDAI to `receiver`. */
export function useWithdraw() {
  const { address } = useAccount();
  const tx = useTx();
  const withdraw = (amount: bigint, receiver?: Address) =>
    tx.run({
      address: ADDRESSES.token,
      abi: tokenAbi,
      functionName: "burn",
      args: [amount, receiver ?? address ?? zeroAddress],
    });
  return { withdraw, ...tx };
}
