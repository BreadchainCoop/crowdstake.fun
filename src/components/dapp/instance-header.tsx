"use client";

import type { ReactNode } from "react";
import { Caption, Heading3 } from "@breadcoop/ui";
import {
  ArrowsClockwise,
  Coins,
  Gavel,
  ShieldCheck,
  TrendUp,
  UsersThree,
} from "@phosphor-icons/react";
import { InstanceTokenBadge } from "@/components/dapp/instance-branding";
import { LiveYield } from "@/components/dapp/live-yield";
import { useInstanceToken, useTokenStats } from "@/hooks/use-token";
import { useRecipients } from "@/hooks/use-recipients";
import { useCycle } from "@/hooks/use-cycle";
import { useRegistryKind } from "@/hooks/use-recipient-voting";
import { useAmountFormatter } from "@/components/demo-mode-provider";
import { cn } from "@/lib/utils";

/** cs2-style stat pill: orange-outlined chip with an icon + label + value. */
function Chip({
  icon,
  label,
  children,
}: {
  icon: ReactNode;
  label: string;
  children: ReactNode;
}) {
  return (
    <div className="border-core-orange/40 bg-paper-0 flex items-center gap-2.5 rounded-full border px-4 py-2">
      <span className="text-core-orange flex-none">{icon}</span>
      <span className="flex flex-col leading-tight">
        <span className="text-surface-grey text-[11px] font-semibold tracking-wide uppercase">
          {label}
        </span>
        <span className="text-text-standard text-sm font-bold tabular-nums">
          {children}
        </span>
      </span>
    </div>
  );
}

/**
 * The instance's identity header — avatar, name, governance model, and a row of
 * live stat chips. Turns an anonymous address into a place that feels like a
 * community's own page.
 */
export function InstanceHeader() {
  const { name, symbol } = useInstanceToken();
  const { totalSupply } = useTokenStats();
  const { recipients } = useRecipients();
  const cycle = useCycle();
  const { kind } = useRegistryKind();
  const fmt = useAmountFormatter();

  const democratic = kind === "voting";

  return (
    <div className="border-paper-2 bg-paper-0 mb-8 rounded-2xl border p-5 sm:p-6">
      <div className="flex items-center gap-4">
        <InstanceTokenBadge className="h-14 w-14" />
        <div className="min-w-0">
          <Heading3 className="text-text-standard truncate">
            {name || symbol || "Crowdstaking instance"}
          </Heading3>
          <div className="mt-1 flex flex-wrap items-center gap-2">
            <span className="text-surface-grey-2 font-mono text-sm">
              ${symbol}
            </span>
            <span
              className={cn(
                "inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[11px] font-semibold",
                democratic
                  ? "bg-system-green/10 text-system-green"
                  : "bg-core-orange/10 text-core-orange",
              )}
            >
              {democratic ? (
                <Gavel size={12} weight="fill" />
              ) : (
                <ShieldCheck size={12} weight="fill" />
              )}
              {democratic ? "Democratic" : "Admin-managed"}
            </span>
          </div>
        </div>
      </div>

      <div className="mt-5 flex flex-wrap gap-2.5">
        <Chip icon={<Coins size={18} weight="fill" />} label="Total staked">
          {fmt(totalSupply)} {symbol}
        </Chip>
        <Chip icon={<TrendUp size={18} weight="fill" />} label="Live yield">
          <LiveYield symbol={symbol} />
        </Chip>
        <Chip icon={<UsersThree size={18} weight="fill" />} label="Recipients">
          {recipients.length}
        </Chip>
        <Chip icon={<ArrowsClockwise size={18} weight="fill" />} label="Cycle">
          <span className="flex items-center gap-1.5">
            #{cycle.cycleNumber?.toString() ?? "—"}
            <Caption
              className={cn(
                "text-[11px]",
                cycle.isComplete ? "text-system-green" : "text-surface-grey",
              )}
            >
              {cycle.isComplete ? "ready" : "in progress"}
            </Caption>
          </span>
        </Chip>
      </div>
    </div>
  );
}
