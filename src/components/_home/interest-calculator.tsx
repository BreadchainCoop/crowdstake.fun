"use client";

import { useMemo, useState } from "react";
import { Body, Caption, Heading3, Heading4 } from "@breadcoop/ui";
import { Users, CurrencyDollar, CheckCircle } from "@phosphor-icons/react";
import { cn } from "@/lib/utils";

const APY = 0.07;
const MIN_MEMBERS = 50;
const MAX_MEMBERS = 500;
const MIN_STAKE = 100;
const MAX_STAKE = 1000;

const usd = (n: number) =>
  n.toLocaleString("en-US", { maximumFractionDigits: 0 });

/**
 * Community Funding Calculator — given a monthly interest target, derives the
 * minimum community size + average stake needed at a fixed 7% APY.
 * Mirrors the original Crowdstaking landing-page calculator.
 */
export function InterestCalculator() {
  const [target, setTarget] = useState(2000);

  const result = useMemo(() => {
    const requiredTotalStaked = (target * 12) / APY;

    let members = Math.ceil(requiredTotalStaked / MAX_STAKE);
    members = Math.min(MAX_MEMBERS, Math.max(MIN_MEMBERS, members));

    const stakePerMember = Math.min(
      MAX_STAKE,
      Math.max(MIN_STAKE, requiredTotalStaked / members),
    );

    const totalStaked = members * stakePerMember;
    const actualMonthly = (totalStaked * APY) / 12;
    const achievable = actualMonthly >= target * 0.999;
    const roomToSpare = actualMonthly >= target * 1.5;

    return {
      members,
      stakePerMember,
      totalStaked,
      actualMonthly,
      achievable,
      roomToSpare,
    };
  }, [target]);

  return (
    <div className="border-primary-jade bg-paper-0 rounded-2xl border-2 p-6 shadow-2xl sm:p-8">
      <Heading3 className="text-text-standard">
        Community Funding Calculator
      </Heading3>
      <Body className="text-surface-grey-2 mt-1">
        Set your target and see the minimum requirements
      </Body>

      {/* Target slider */}
      <div className="mt-6">
        <div className="flex items-baseline justify-between">
          <Caption className="text-surface-grey-2">
            Monthly Target Interest
          </Caption>
          <span className="font-breadDisplay text-core-orange text-2xl font-bold">
            ${usd(target)}{" "}
            <span className="text-surface-grey text-base font-normal">
              /month
            </span>
          </span>
        </div>
        <input
          type="range"
          min={50}
          max={5000}
          step={50}
          value={target}
          onChange={(e) => setTarget(Number(e.target.value))}
          aria-label="Monthly target interest"
          className="bg-paper-2 accent-core-orange mt-3 h-2 w-full cursor-pointer appearance-none rounded-full"
        />
      </div>

      {/* Minimum requirements */}
      <Heading4 className="text-text-standard mt-8">
        Minimum Requirements
      </Heading4>
      <div className="mt-3 grid grid-cols-2 gap-3">
        <Stat
          icon={<Users size={20} weight="bold" className="text-primary-jade" />}
          label="Community Members"
          value={`${result.members}`}
          hint={`${result.members} members minimum`}
        />
        <Stat
          icon={
            <CurrencyDollar
              size={20}
              weight="bold"
              className="text-primary-jade"
            />
          }
          label="Average Stake per Member"
          value={`$${usd(result.stakePerMember)}`}
          hint={`$${usd(result.stakePerMember)} per member`}
        />
      </div>

      {/* Results */}
      <div className="bg-paper-1 mt-4 grid grid-cols-3 gap-3 rounded-xl p-4 text-center">
        <Result label="Total Staked" value={`$${usd(result.totalStaked)}`} />
        <Result label="APY" value="7%" />
        <Result
          label="Actual Monthly Interest"
          value={`$${usd(result.actualMonthly)}`}
        />
      </div>

      {/* Status badge */}
      <div
        className={cn(
          "mt-4 flex items-center gap-2 rounded-lg px-4 py-3 text-sm font-semibold",
          result.achievable
            ? "bg-system-green/10 text-system-green"
            : "bg-system-warning/10 text-system-warning",
        )}
      >
        {result.achievable ? (
          <>
            <CheckCircle size={18} weight="fill" />
            Target achievable!{result.roomToSpare ? " With room to spare!" : ""}
          </>
        ) : (
          "Target requires parameters outside typical ranges"
        )}
      </div>

      <Caption className="text-surface-grey mt-4 block">
        * Approximate configuration based on your monthly target interest.
        Calculations based on 7% APY. Ranges: 50–500 members, $100–$1K stakes.
      </Caption>
    </div>
  );
}

function Stat({
  icon,
  label,
  value,
  hint,
}: {
  icon: React.ReactNode;
  label: string;
  value: string;
  hint: string;
}) {
  return (
    <div className="border-paper-2 bg-paper-0 rounded-xl border p-4">
      <div className="flex items-center gap-2">
        {icon}
        <Caption className="text-surface-grey-2">{label}</Caption>
      </div>
      <p className="font-breadDisplay text-text-standard mt-2 text-2xl font-bold">
        {value}
      </p>
      <Caption className="text-surface-grey">{hint}</Caption>
    </div>
  );
}

function Result({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <p className="font-breadDisplay text-text-standard text-lg font-bold">
        {value}
      </p>
      <Caption className="text-surface-grey-2">{label}</Caption>
    </div>
  );
}
