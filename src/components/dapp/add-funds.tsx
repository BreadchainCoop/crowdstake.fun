"use client";

import { useAccount } from "wagmi";
import { Body, Caption } from "@breadcoop/ui";
import { ArrowUpRight, CreditCard, Path } from "@phosphor-icons/react";
import { useActiveChainId } from "@/components/instance-provider";
import { useActiveChain, useBaseAssetSymbol } from "@/hooks/use-chain";
import { jumperFundUrl } from "@/lib/funding";
import { cn } from "@/lib/utils";

/**
 * "Add funds" — bring the active chain's deposit asset from anywhere. Opens
 * LI.FI's hosted app (Jumper) with the destination chain + token pre-selected,
 * covering bridge, swap, and buy-with-card in one flow.
 */
export function AddFundsCard({ className }: { className?: string }) {
  const chainId = useActiveChainId();
  const { address } = useAccount();
  const { chain } = useActiveChain();
  const baseSym = useBaseAssetSymbol();
  const href = jumperFundUrl(chainId, address);

  return (
    <a
      href={href}
      target="_blank"
      rel="noreferrer"
      className={cn(
        "border-paper-2 hover:border-core-orange bg-paper-0 group flex items-center gap-4 rounded-2xl border p-4 transition-colors",
        className,
      )}
    >
      <div className="bg-core-orange/10 text-core-orange flex h-11 w-11 flex-none items-center justify-center rounded-full">
        <Path size={22} weight="bold" />
      </div>
      <div className="min-w-0 flex-1">
        <Body className="text-text-standard text-sm font-semibold">
          Add funds — bridge, swap, or buy {baseSym}
        </Body>
        <Caption className="text-surface-grey-2 mt-0.5 flex flex-wrap items-center gap-x-2 gap-y-0.5">
          <span>Bring crypto from any chain onto {chain.name}</span>
          <span className="text-surface-grey inline-flex items-center gap-1">
            <CreditCard size={12} /> or buy with a card
          </span>
          <span className="text-surface-grey text-[11px]">· via LI.FI</span>
        </Caption>
      </div>
      <ArrowUpRight
        size={18}
        weight="bold"
        className="text-surface-grey group-hover:text-core-orange flex-none"
      />
    </a>
  );
}
