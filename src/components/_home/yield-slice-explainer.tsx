"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { Body, Caption, Chip, Heading2, Heading4 } from "@breadcoop/ui";
import {
  ArrowRight,
  ArrowsClockwise,
  Bank,
  Confetti,
  Pause,
  Play,
  Scissors,
  ShieldCheck,
  TrendUp,
  Wallet,
} from "@phosphor-icons/react";
import { cn } from "@/lib/utils";

/**
 * YieldSliceExplainer
 * -------------------
 * A friendly, step-by-step visualization of the Crowdstaking mechanism:
 * deposits earn interest through over-collateralized lending (sDAI), and only
 * a *slice of the yield* is skimmed off the top for the community's cause —
 * the principal always stays whole and withdrawable.
 *
 * The diagram is persistent; each step highlights a different part of the flow
 * (deposit → vault/lending engine → yield slice → recipients) and swaps in a
 * plain-language explanation. Autoplays gently, pausing on interaction and
 * respecting `prefers-reduced-motion`.
 */

type StepKey = "deposit" | "lend" | "accrue" | "slice" | "fund";

const STEPS: {
  key: StepKey;
  short: string;
  title: string;
  body: string;
  chip: string;
  Icon: typeof Wallet;
}[] = [
  {
    key: "deposit",
    short: "Deposit",
    title: "You deposit — and stay in control",
    body: "Add WXDAI to the shared pool and instantly receive CSTAKE, 1:1. That token is your receipt: your principal never leaves your control, and you can withdraw it in full at any time.",
    chip: "Your principal: 100% yours",
    Icon: Wallet,
  },
  {
    key: "lend",
    short: "Lend",
    title: "The pool earns through over-collateralized lending",
    body: "Behind the scenes your deposit joins an sDAI vault that lends to borrowers who must lock up more collateral than they borrow. That over-collateralization is the safety margin — the loan stays fully backed even if markets move — and borrowers pay interest for it.",
    chip: "Borrowers post more than 100%",
    Icon: Bank,
  },
  {
    key: "accrue",
    short: "Earn",
    title: "Interest stacks up on top",
    body: "That borrower interest flows back into the vault and settles as a thin layer on top of everyone's principal. The base — your money — never shrinks. Only the top grows, cycle after cycle.",
    chip: "Principal stays untouched",
    Icon: TrendUp,
  },
  {
    key: "slice",
    short: "Slice",
    title: "A slice comes off the top",
    body: "Each cycle, only that interest slice is skimmed off — never your principal. The community's weighted votes decide exactly how the slice is split across the causes you care about.",
    chip: "Only the yield moves",
    Icon: Scissors,
  },
  {
    key: "fund",
    short: "Fund",
    title: "Your cause gets funded — for free",
    body: "The slice is sent to your chosen recipients and a fresh cycle begins. Whenever you like, burn CSTAKE to get your full principal back, 1:1. You funded something real without spending a cent of your savings.",
    chip: "Withdraw principal anytime",
    Icon: Confetti,
  },
];

const AUTOPLAY_MS = 4200;

export function YieldSliceExplainer() {
  const [active, setActive] = useState(0);
  const [playing, setPlaying] = useState(true);
  const reducedMotion = usePrefersReducedMotion();
  const step = STEPS[active].key;

  // Gentle autoplay; disabled when paused or when the user prefers reduced motion.
  useEffect(() => {
    if (!playing || reducedMotion) return;
    const id = window.setTimeout(
      () => setActive((i) => (i + 1) % STEPS.length),
      AUTOPLAY_MS,
    );
    return () => window.clearTimeout(id);
  }, [active, playing, reducedMotion]);

  const go = useCallback((i: number) => {
    setActive(((i % STEPS.length) + STEPS.length) % STEPS.length);
    setPlaying(false); // manual navigation pauses the reel
  }, []);

  return (
    <section id="mechanism" className="py-20">
      <div className="section-container">
        <div className="mx-auto max-w-3xl text-center">
          <div className="flex justify-center">
            <Chip size="small" className="text-primary-jade">
              How the mechanism works
            </Chip>
          </div>
          <Heading2 className="text-text-standard mt-4">
            Where the funding comes from
          </Heading2>
          <Body className="text-surface-grey-2 mx-auto mt-4 text-lg">
            Your savings do the work while staying yours. Here&apos;s how a slice
            of yield — and only the yield — turns into funding for your
            community.
          </Body>
        </div>

        <div className="border-paper-2 bg-paper-0 mt-12 overflow-hidden rounded-3xl border-2 shadow-xl">
          <FlowDiagram step={step} reducedMotion={reducedMotion} />

          {/* Step rail */}
          <div className="border-paper-2 bg-paper-1 border-t">
            <ol className="flex flex-wrap">
              {STEPS.map((s, i) => {
                const activeStep = i === active;
                return (
                  <li key={s.key} className="flex-1 basis-32">
                    <button
                      type="button"
                      onClick={() => go(i)}
                      aria-current={activeStep ? "step" : undefined}
                      className={cn(
                        "group flex w-full items-center gap-2 border-b-2 px-3 py-3 transition-colors",
                        activeStep
                          ? "border-core-orange bg-paper-0"
                          : "hover:bg-paper-0/60 border-transparent",
                      )}
                    >
                      <span
                        className={cn(
                          "font-breadDisplay flex h-7 w-7 flex-none items-center justify-center rounded-full text-sm font-bold transition-colors",
                          activeStep
                            ? "bg-core-orange text-white"
                            : "bg-paper-2 text-surface-grey-2 group-hover:text-text-standard",
                        )}
                      >
                        {i + 1}
                      </span>
                      <span
                        className={cn(
                          "text-left text-sm font-semibold transition-colors",
                          activeStep
                            ? "text-text-standard"
                            : "text-surface-grey-2",
                        )}
                      >
                        {s.short}
                      </span>
                    </button>
                  </li>
                );
              })}
            </ol>
          </div>

          {/* Active step detail */}
          <StepDetail
            index={active}
            playing={playing}
            reducedMotion={reducedMotion}
            onPrev={() => go(active - 1)}
            onNext={() => go(active + 1)}
            onTogglePlay={() => setPlaying((p) => !p)}
          />
        </div>
      </div>
    </section>
  );
}

/* ------------------------------- Step detail ------------------------------ */

function StepDetail({
  index,
  playing,
  reducedMotion,
  onPrev,
  onNext,
  onTogglePlay,
}: {
  index: number;
  playing: boolean;
  reducedMotion: boolean;
  onPrev: () => void;
  onNext: () => void;
  onTogglePlay: () => void;
}) {
  const s = STEPS[index];
  return (
    <div className="grid gap-6 p-6 sm:grid-cols-[auto_1fr_auto] sm:items-start sm:p-8">
      <div className="bg-core-orange/10 flex h-14 w-14 flex-none items-center justify-center rounded-2xl">
        <s.Icon size={28} weight="bold" className="text-core-orange" />
      </div>

      <div key={s.key} className={reducedMotion ? undefined : "animate-fade-in"}>
        <div className="flex flex-wrap items-center gap-3">
          <Heading4 className="text-text-standard">{s.title}</Heading4>
          <Chip size="small" className="text-primary-jade">
            {s.chip}
          </Chip>
        </div>
        <Body className="text-surface-grey-2 mt-2 max-w-2xl">{s.body}</Body>
      </div>

      <div className="flex items-center gap-2 sm:flex-col">
        <NavButton label="Previous step" onClick={onPrev}>
          <ArrowRight size={18} weight="bold" className="rotate-180" />
        </NavButton>
        <NavButton
          label={playing ? "Pause" : "Play"}
          onClick={onTogglePlay}
          highlight
        >
          {playing ? (
            <Pause size={18} weight="fill" />
          ) : (
            <Play size={18} weight="fill" />
          )}
        </NavButton>
        <NavButton label="Next step" onClick={onNext}>
          <ArrowRight size={18} weight="bold" />
        </NavButton>
      </div>
    </div>
  );
}

function NavButton({
  label,
  onClick,
  highlight,
  children,
}: {
  label: string;
  onClick: () => void;
  highlight?: boolean;
  children: React.ReactNode;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label={label}
      className={cn(
        "flex h-10 w-10 items-center justify-center rounded-full border transition-colors",
        highlight
          ? "border-core-orange text-core-orange hover:bg-core-orange hover:text-white"
          : "border-paper-2 text-surface-grey-2 hover:border-core-orange hover:text-core-orange",
      )}
    >
      {children}
    </button>
  );
}

/* ------------------------------ Flow diagram ------------------------------ */

function FlowDiagram({
  step,
  reducedMotion,
}: {
  step: StepKey;
  reducedMotion: boolean;
}) {
  // Which parts of the picture are "lit" for the current step.
  const on = {
    deposit: step === "deposit",
    engine: step === "lend",
    slice: step === "accrue" || step === "slice",
    skim: step === "slice",
    recipients: step === "fund",
  };
  // The interest layer grows as we move from earning → slicing.
  const sliceTall = step === "accrue" || step === "slice" || step === "fund";
  const motion = reducedMotion ? "" : "transition-all duration-700 ease-out";

  return (
    <div className="bg-paper-0 p-6 sm:p-10">
      <div className="grid items-center gap-6 lg:grid-cols-[1fr_auto_1.1fr_auto_1fr]">
        {/* 1 — Deposit in */}
        <FlowCard
          lit={on.deposit}
          reducedMotion={reducedMotion}
          icon={<Wallet size={22} weight="bold" />}
          label="Your deposit"
          value="WXDAI → CSTAKE"
          sub="minted 1:1"
        />

        <Connector active={on.deposit} reducedMotion={reducedMotion} />

        {/* 2 — The vault: principal + yield slice */}
        <div className="flex flex-col items-center">
          <Caption className="text-surface-grey mb-2 font-semibold tracking-wide uppercase">
            The vault
          </Caption>
          <div
            className={cn(
              "relative w-full max-w-[240px] rounded-2xl border-2 p-2",
              on.slice || on.skim
                ? "border-core-orange"
                : "border-paper-2",
              motion,
            )}
          >
            {/* Yield slice — off the top */}
            <div
              className={cn(
                "relative flex items-center justify-center overflow-hidden rounded-lg",
                motion,
              )}
              style={{ height: sliceTall ? 58 : 34 }}
            >
              <div
                className={cn(
                  "bg-core-orange absolute inset-0 rounded-lg",
                  on.slice ? "opacity-100" : "opacity-70",
                  on.skim && !reducedMotion ? "animate-slice-lift" : "",
                  motion,
                )}
              />
              <span className="font-breadDisplay relative z-10 text-sm font-bold text-white">
                Yield slice
              </span>
            </div>

            {/* Skim line — where the cut happens */}
            <div className="relative my-1 flex items-center justify-center">
              <div
                className={cn(
                  "w-full",
                  on.skim
                    ? "bg-core-orange h-0.5 rounded-full"
                    : "border-surface-grey/50 border-t-2 border-dashed",
                  motion,
                )}
              />
              {on.skim && (
                <Scissors
                  size={16}
                  weight="fill"
                  className={cn(
                    "text-core-orange absolute -right-1 bg-paper-0",
                    reducedMotion ? "" : "animate-fade-in",
                  )}
                />
              )}
            </div>

            {/* Principal — always yours */}
            <div className="bg-primary-jade flex h-[140px] flex-col items-center justify-center rounded-lg px-3 text-center">
              <span className="font-breadDisplay text-lg font-bold text-white">
                Your principal
              </span>
              <span className="mt-1 text-xs font-medium text-white/85">
                stays whole · withdrawable 1:1
              </span>
            </div>
          </div>

          {/* Engine plinth — over-collateralized lending */}
          <div
            className={cn(
              "mt-3 flex w-full max-w-[240px] items-center justify-center gap-2 rounded-xl border px-3 py-2",
              on.engine
                ? "border-primary-jade bg-primary-jade/10"
                : "border-paper-2 bg-paper-1",
              motion,
            )}
          >
            <ShieldCheck
              size={18}
              weight="bold"
              className={on.engine ? "text-primary-jade" : "text-surface-grey"}
            />
            <span
              className={cn(
                "text-xs font-semibold",
                on.engine ? "text-primary-jade" : "text-surface-grey-2",
              )}
            >
              Over-collateralized loans · sDAI
            </span>
          </div>
        </div>

        <Connector
          active={on.skim || on.recipients}
          reducedMotion={reducedMotion}
          label="the slice"
        />

        {/* 3 — Recipients out */}
        <FlowCard
          lit={on.recipients}
          reducedMotion={reducedMotion}
          icon={<Confetti size={22} weight="bold" />}
          label="Your cause"
          value="Voted recipients"
          sub="funded each cycle"
        />
      </div>

      {/* Withdraw-anytime loop */}
      <div className="mt-6 flex items-center justify-center gap-2">
        <ArrowsClockwise
          size={16}
          weight="bold"
          className="text-surface-grey"
        />
        <Caption className="text-surface-grey">
          Your principal loops back to you — burn CSTAKE for WXDAI 1:1, anytime.
        </Caption>
      </div>
    </div>
  );
}

function FlowCard({
  lit,
  reducedMotion,
  icon,
  label,
  value,
  sub,
}: {
  lit: boolean;
  reducedMotion: boolean;
  icon: React.ReactNode;
  label: string;
  value: string;
  sub: string;
}) {
  return (
    <div
      className={cn(
        "rounded-2xl border-2 p-5 text-center",
        lit
          ? "border-core-orange bg-core-orange/5 shadow-md"
          : "border-paper-2 bg-paper-0",
        reducedMotion ? "" : "transition-all duration-500",
        lit && !reducedMotion ? "scale-[1.03]" : "",
      )}
    >
      <div
        className={cn(
          "mx-auto flex h-11 w-11 items-center justify-center rounded-xl",
          lit ? "bg-core-orange text-white" : "bg-paper-1 text-surface-grey-2",
          reducedMotion ? "" : "transition-colors duration-500",
        )}
      >
        {icon}
      </div>
      <p className="font-breadDisplay text-text-standard mt-3 font-bold">
        {value}
      </p>
      <Caption className="text-surface-grey-2">{label}</Caption>
      <Caption className="text-surface-grey mt-0.5 block">{sub}</Caption>
    </div>
  );
}

function Connector({
  active,
  reducedMotion,
  label,
}: {
  active: boolean;
  reducedMotion: boolean;
  label?: string;
}) {
  return (
    <div className="flex flex-col items-center justify-center py-2 lg:py-0">
      {label && (
        <Caption
          className={cn(
            "mb-1 font-semibold whitespace-nowrap",
            active ? "text-core-orange" : "text-surface-grey",
          )}
        >
          {label}
        </Caption>
      )}
      <ArrowRight
        size={26}
        weight="bold"
        className={cn(
          "rotate-90 lg:rotate-0",
          active ? "text-core-orange" : "text-paper-2",
          reducedMotion ? "" : "transition-colors duration-500",
          active && !reducedMotion ? "animate-nudge" : "",
        )}
      />
    </div>
  );
}

/* -------------------------------- utilities ------------------------------- */

function usePrefersReducedMotion() {
  const [reduced, setReduced] = useState(false);
  const mql = useRef<MediaQueryList | null>(null);
  useEffect(() => {
    mql.current = window.matchMedia("(prefers-reduced-motion: reduce)");
    const update = () => setReduced(mql.current?.matches ?? false);
    update();
    mql.current.addEventListener("change", update);
    return () => mql.current?.removeEventListener("change", update);
  }, []);
  return reduced;
}
