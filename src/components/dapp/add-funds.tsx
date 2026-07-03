"use client";

import { useEffect, useState } from "react";
import dynamic from "next/dynamic";
import { useAccount } from "wagmi";
import { Body, Caption } from "@breadcoop/ui";
import {
  ArrowUpRight,
  CreditCard,
  Path,
  SpinnerGap,
  X,
} from "@phosphor-icons/react";
import { useActiveChainId } from "@/components/instance-provider";
import { useActiveChain, useBaseAssetSymbol } from "@/hooks/use-chain";
import { fundToToken, jumperFundUrl } from "@/lib/funding";
import { cn } from "@/lib/utils";

// The widget drags a heavy, browser-only dependency tree — load it only when
// the modal opens, never on the server or in the initial bundle.
const FundLifiWidget = dynamic(() => import("./lifi-widget"), {
  ssr: false,
  loading: () => (
    <div className="flex h-72 items-center justify-center">
      <SpinnerGap size={28} className="text-core-orange animate-spin" />
    </div>
  ),
});

/**
 * "Add funds" — bring the active chain's deposit asset from anywhere. Opens an
 * embedded LI.FI widget (bridge + swap + buy-with-card) in a modal, with the
 * destination locked to this instance's deposit asset and, when connected, the
 * user's own wallet as the recipient. Falls back to LI.FI's hosted app for
 * anyone who'd rather run the flow in a new tab.
 */
export function AddFundsCard({ className }: { className?: string }) {
  const chainId = useActiveChainId();
  const { address } = useAccount();
  const { chain } = useActiveChain();
  const baseSym = useBaseAssetSymbol();
  const [open, setOpen] = useState(false);

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className={cn(
          "border-paper-2 hover:border-core-orange bg-paper-0 group flex w-full items-center gap-4 rounded-2xl border p-4 text-left transition-colors",
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
      </button>

      {open && (
        <FundModal
          chainId={chainId}
          address={address}
          baseSym={baseSym}
          onClose={() => setOpen(false)}
        />
      )}
    </>
  );
}

function FundModal({
  chainId,
  address,
  baseSym,
  onClose,
}: {
  chainId: number;
  address?: string;
  baseSym: string;
  onClose: () => void;
}) {
  // Close on Escape, and lock body scroll while the modal is up.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    document.addEventListener("keydown", onKey);
    const prevOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.removeEventListener("keydown", onKey);
      document.body.style.overflow = prevOverflow;
    };
  }, [onClose]);

  return (
    <div
      className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/40 p-4 sm:items-center"
      onClick={onClose}
    >
      <div
        className="bg-paper-main relative my-8 w-full max-w-md rounded-2xl p-4 shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="mb-3 flex items-center justify-between">
          <div>
            <Body className="text-text-standard text-sm font-semibold">
              Add {baseSym}
            </Body>
            <Caption className="text-surface-grey-2">
              Bridge, swap, or buy — funds land in your wallet, ready to deposit.
            </Caption>
          </div>
          <button
            type="button"
            onClick={onClose}
            aria-label="Close"
            className="text-surface-grey hover:text-text-standard hover:bg-paper-1 flex-none rounded-lg p-1.5"
          >
            <X size={18} weight="bold" />
          </button>
        </div>

        <FundLifiWidget
          toChainId={chainId}
          toToken={fundToToken(chainId)}
          toAddress={address}
        />

        <a
          href={jumperFundUrl(chainId, address)}
          target="_blank"
          rel="noreferrer"
          className="text-surface-grey hover:text-core-orange mt-3 inline-flex items-center gap-1 text-xs"
        >
          Prefer LI.FI&apos;s site? Open in a new tab
          <ArrowUpRight size={12} weight="bold" />
        </a>
      </div>
    </div>
  );
}
