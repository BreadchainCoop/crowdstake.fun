"use client";

import { useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { CaretDown } from "@phosphor-icons/react";
import { cn } from "@/lib/utils";
import { WalletButton } from "@/components/dapp/wallet-button";
import { useRegistryOwner } from "@/hooks/use-recipients";
import { InstanceSwitcher } from "@/components/dapp/instance-switcher";
import { useDemoMode } from "@/components/demo-mode-provider";

/** Display-only ×1000 toggle for demos (never changes real transaction amounts). */
function DemoToggle() {
  const { demo, setDemo } = useDemoMode();
  return (
    <button
      onClick={() => setDemo(!demo)}
      title="Demo mode: multiply displayed amounts ×1000 (does not change real amounts)"
      className={cn(
        "hidden h-8 shrink-0 items-center rounded-full border px-3 text-xs font-semibold transition-colors sm:inline-flex",
        demo
          ? "border-core-orange bg-core-orange text-white"
          : "border-paper-2 text-surface-grey-2 hover:text-text-standard",
      )}
    >
      ×1000{demo ? " on" : ""}
    </button>
  );
}

/** The everyday actions stay visible; everything else lives under More. */
const PRIMARY = [
  { href: "/app", label: "Portfolio" },
  { href: "/app/deposit", label: "Deposit" },
  { href: "/app/withdraw", label: "Withdraw" },
  { href: "/app/vote", label: "Vote" },
  { href: "/app/distribute", label: "Distribute" },
];

const SECONDARY = [
  { href: "/app/yield", label: "Yield split" },
  { href: "/app/history", label: "History" },
  { href: "/app/deploy", label: "Deploy" },
];

const ADMIN = [
  { href: "/app/recipients", label: "Recipients" },
  { href: "/app/admin", label: "Admin" },
];

function useSecondaryLinks() {
  const { isAdmin } = useRegistryOwner();
  return isAdmin ? [...SECONDARY, ...ADMIN] : SECONDARY;
}

function isActive(pathname: string, href: string) {
  // trailingSlash builds report "/app/" on hard loads — normalize both forms.
  const p = pathname.replace(/\/+$/, "") || "/";
  return href === "/app" ? p === "/app" : p.startsWith(href);
}

function NavLink({
  href,
  label,
  pathname,
  className,
  onClick,
}: {
  href: string;
  label: string;
  pathname: string;
  className?: string;
  onClick?: () => void;
}) {
  return (
    <Link
      href={href}
      onClick={onClick}
      className={cn(
        "rounded-full px-3.5 py-1.5 text-sm font-medium whitespace-nowrap transition-colors",
        isActive(pathname, href)
          ? "bg-core-orange/10 text-core-orange"
          : "text-surface-grey-2 hover:bg-paper-1 hover:text-text-standard",
        className,
      )}
    >
      {label}
    </Link>
  );
}

/** Overflow menu for the less-frequent pages (admin entries when relevant). */
function MoreMenu({ pathname }: { pathname: string }) {
  const [open, setOpen] = useState(false);
  const links = useSecondaryLinks();
  const anyActive = links.some((l) => isActive(pathname, l.href));

  return (
    <div className="relative">
      <button
        onClick={() => setOpen((v) => !v)}
        className={cn(
          "flex items-center gap-1 rounded-full px-3.5 py-1.5 text-sm font-medium transition-colors",
          anyActive
            ? "bg-core-orange/10 text-core-orange"
            : "text-surface-grey-2 hover:bg-paper-1 hover:text-text-standard",
        )}
      >
        More
        <CaretDown
          size={12}
          weight="bold"
          className={cn("transition-transform", open && "rotate-180")}
        />
      </button>
      {open && (
        <>
          <div className="fixed inset-0 z-40" onClick={() => setOpen(false)} />
          <div className="border-paper-2 bg-paper-0 absolute right-0 z-50 mt-2 flex w-44 flex-col gap-0.5 rounded-xl border p-1.5 shadow-xl">
            {links.map((l) => (
              <NavLink
                key={l.href}
                {...l}
                pathname={pathname}
                className="block px-3 py-2"
                onClick={() => setOpen(false)}
              />
            ))}
          </div>
        </>
      )}
    </div>
  );
}

export function DappNav() {
  const pathname = usePathname();
  const secondary = useSecondaryLinks();

  return (
    <header className="border-paper-2 bg-paper-main/85 tg-safe-top sticky top-0 z-50 border-b backdrop-blur-md">
      <nav className="section-container flex h-16 items-center gap-3">
        {/* Left: the instance IS the brand (white-label) — its badge + name. */}
        <InstanceSwitcher />

        {/* Center: everyday pages + an overflow menu (lg+). */}
        <div className="hidden flex-1 items-center justify-center gap-0.5 lg:flex">
          {PRIMARY.map((l) => (
            <NavLink key={l.href} {...l} pathname={pathname} />
          ))}
          <MoreMenu pathname={pathname} />
        </div>

        {/* Right: utilities */}
        <div className="ml-auto flex items-center gap-2 lg:ml-0">
          <DemoToggle />
          <WalletButton size="sm" nav />
        </div>
      </nav>

      {/* Compact nav row (below lg): everyday pages scroll, the rest follow. */}
      <div className="-mt-1 flex scrollbar-none gap-0.5 overflow-x-auto px-4 pb-2 lg:hidden">
        {[...PRIMARY, ...secondary].map((l) => (
          <NavLink key={l.href} {...l} pathname={pathname} />
        ))}
      </div>
    </header>
  );
}
