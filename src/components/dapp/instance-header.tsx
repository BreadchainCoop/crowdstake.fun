"use client";

import type { ReactNode } from "react";
import { Caption, Heading3 } from "@breadcoop/ui";
import {
  ArrowsClockwise,
  Coins,
  Gavel,
  Percent,
  ShieldCheck,
  TrendUp,
  UsersFour,
  UsersThree,
} from "@phosphor-icons/react";
import { parseUnits } from "viem";
import { InstanceTokenBadge } from "@/components/dapp/instance-branding";
import { LiveYield } from "@/components/dapp/live-yield";
import { useInstanceToken, useTokenStats } from "@/hooks/use-token";
import { useRecipients } from "@/hooks/use-recipients";
import { useCycle } from "@/hooks/use-cycle";
import { useRegistryKind } from "@/hooks/use-recipient-voting";
import { useApy } from "@/hooks/use-apy";
import { useBackers } from "@/hooks/use-backers";
import { useFamily } from "@/hooks/use-family";
import { scaleTo18, useFamilyStats } from "@/hooks/use-family-stats";
import { useDistributionHistoryForFamily } from "@/hooks/use-distribution-history";
import { useLiveYield } from "@/hooks/use-live-yield";
import {
  useAmountFormatter,
  useAmountFormatter18,
} from "@/components/demo-mode-provider";
import { cn } from "@/lib/utils";

/** cs2-style stat pill: orange-outlined chip with an icon + label + value. */
function Chip({
  icon,
  label,
  children,
  title,
}: {
  icon: ReactNode;
  label: string;
  children: ReactNode;
  title?: string;
}) {
  return (
    <div
      title={title}
      className="border-core-orange/40 bg-paper-0 flex items-center gap-2.5 rounded-full border px-4 py-2"
    >
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
  const { name, symbol, decimals } = useInstanceToken();
  const { totalSupply } = useTokenStats();
  const { recipients } = useRecipients();
  const cycle = useCycle();
  const { kind } = useRegistryKind();
  const fmt = useAmountFormatter();
  const fmt18 = useAmountFormatter18();
  const family = useFamily();
  const fstats = useFamilyStats(family);
  // Unique holders across every family chain (union — one person on two
  // chains is one backer). Counted from a bounded Transfer-log window, so
  // communities older than the lookback undercount until backfill exists.
  const backers = useBackers(family);
  // Total funding generated — v2's flagship number: everything EVER distributed
  // (all chains) + what's accruing right now. Mounting the header kicks off the
  // history event scan, but it shares the history page's localStorage cache, so
  // repeat visits only top up the gap since the last scan.
  const { history, isLoading: historyLoading } =
    useDistributionHistoryForFamily(family);
  const singleLiveYield = useLiveYield();
  // Families are rated across ALL their chains — the browsed chain alone can
  // be empty while the community earns elsewhere.
  const apy = useApy(
    family.isFamily
      ? {
          familyId: family.familyId,
          ratePerMs: fstats.ratePerMs,
          totalStaked18: fstats.totalStaked18,
        }
      : undefined,
  );

  const democratic = kind === "voting";
  // Families: headline the whole community (all chains summed, 18-dp
  // normalized), not just the chain being viewed.
  const familyMode = family.isFamily && fstats.totalStaked18 !== undefined;
  const chainsNote = familyMode ? ` · ${fstats.chains} chains` : "";

  // All-time distributed is a decimals-normalized decimal number (chains mix
  // 6-dp and 18-dp); re-quantize to 18 dp so it sums with the accruing bigints
  // and demo-scales through the same formatter.
  const distributed18 =
    history !== null ? safeParse18(history.totalNormalized) : undefined;
  const accruing18 = family.isFamily
    ? fstats.yieldAccrued18
    : singleLiveYield !== undefined
      ? scaleTo18(singleLiveYield, decimals)
      : undefined;
  // While the history scan runs, show the accruing part alone (with a note)
  // rather than nothing.
  const generated18 =
    distributed18 !== undefined || accruing18 !== undefined
      ? (distributed18 ?? 0n) + (accruing18 ?? 0n)
      : undefined;
  const scanningHistory = historyLoading && history === null;

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
        <Chip
          icon={<Coins size={18} weight="fill" />}
          label={`Total staked${chainsNote}`}
        >
          {familyMode
            ? `${fmt18(fstats.totalStaked18)} ${symbol}`
            : `${fmt(totalSupply)} ${symbol}`}
        </Chip>
        <Chip
          icon={<TrendUp size={18} weight="fill" />}
          label={`Live yield${chainsNote}`}
        >
          {familyMode ? (
            // 6 fractional digits like the ticking single-chain counter —
            // young families accrue amounts a 4-dp display rounds to zero.
            `${fmt18(fstats.yieldAccrued18, 6)} ${symbol}`
          ) : (
            <LiveYield symbol={symbol} />
          )}
        </Chip>
        <Chip icon={<Percent size={18} weight="fill" />} label="APY">
          {apy !== undefined ? `≈ ${apy.toFixed(1)}%` : "—"}
        </Chip>
        <Chip icon={<UsersThree size={18} weight="fill" />} label="Recipients">
          {recipients.length}
        </Chip>
        <Chip
          icon={<UsersFour size={18} weight="fill" />}
          label="Backers"
          title="Unique holders, counted from recent on-chain transfers. Communities older than the scanned window may show fewer backers than they really have."
        >
          {backers.count !== undefined
            ? `${backers.partial || backers.capped ? "≈ " : ""}${backers.count}`
            : "—"}
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

      {/* Total funding generated — distributed all-time + currently accruing. */}
      <div className="border-core-orange/40 bg-core-orange/5 mt-5 rounded-xl border px-5 py-4">
        <span className="font-breadDisplay text-text-standard block text-3xl font-bold tabular-nums">
          {generated18 !== undefined ? (
            <>
              {/* 6 frac digits like the live-yield chip — young communities
                  have generated amounts a 4-dp display rounds to zero. */}
              {fmt18(generated18, 6)}{" "}
              <span className="text-surface-grey-2 text-xl">{symbol}</span>
            </>
          ) : (
            "—"
          )}
        </span>
        <Caption className="text-surface-grey mt-1">
          Total funding generated — distributed + accruing
          {chainsNote}
          {scanningHistory && " · scanning history…"}
        </Caption>
      </div>
    </div>
  );
}

/** parseUnits-safe 18-dp quantization: Number.toFixed goes exponential at
 * >= 1e21 (parseUnits throws on it), so fall back to a whole-unit BigInt. */
function safeParse18(n: number): bigint {
  try {
    return parseUnits(n.toFixed(18), 18);
  } catch {
    return BigInt(Math.round(n)) * 10n ** 18n;
  }
}
