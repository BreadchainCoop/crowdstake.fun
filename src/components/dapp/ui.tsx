"use client";

import type { ReactNode } from "react";
import { Body, Caption, Heading2, Heading4 } from "@breadcoop/ui";
import { cn } from "@/lib/utils";

/** Page title + subtitle used at the top of every dapp page. */
export function PageHeader({
  title,
  subtitle,
}: {
  title: string;
  subtitle?: string;
}) {
  return (
    <div className="mb-8">
      <Heading2 className="text-text-standard">{title}</Heading2>
      {subtitle && <Body className="text-surface-grey-2 mt-2">{subtitle}</Body>}
    </div>
  );
}

/** A bordered card surface. */
export function Card({
  children,
  className,
}: {
  children: ReactNode;
  className?: string;
}) {
  return (
    <div
      className={cn(
        "border-paper-2 bg-paper-0 rounded-2xl border p-6",
        className,
      )}
    >
      {children}
    </div>
  );
}

/** Labelled statistic tile. */
export function StatCard({
  label,
  value,
  sub,
  accent,
}: {
  label: string;
  value: ReactNode;
  sub?: ReactNode;
  accent?: boolean;
}) {
  return (
    <Card className={cn(accent && "border-core-orange/40 bg-core-orange/5")}>
      <Caption className="text-surface-grey-2">{label}</Caption>
      <Heading4 className="text-text-standard mt-2">{value}</Heading4>
      {sub && <Caption className="text-surface-grey mt-1 block">{sub}</Caption>}
    </Card>
  );
}

/** A horizontal progress bar (0..1). */
export function ProgressBar({ value }: { value: number }) {
  return (
    <div className="bg-paper-2 h-2 w-full overflow-hidden rounded-full">
      <div
        className="bg-core-orange h-full rounded-full transition-all"
        style={{ width: `${Math.min(100, Math.max(0, value * 100))}%` }}
      />
    </div>
  );
}

/** Empty-state hint. */
export function EmptyState({ children }: { children: ReactNode }) {
  return (
    <Card className="text-center">
      <Body className="text-surface-grey-2">{children}</Body>
    </Card>
  );
}
