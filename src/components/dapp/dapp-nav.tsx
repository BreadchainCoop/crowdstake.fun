"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import { cn } from "@/lib/utils";
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
        "hidden shrink-0 rounded-lg border px-2.5 py-1.5 text-xs font-semibold transition-colors sm:block",
        demo
          ? "border-core-orange bg-core-orange text-white"
          : "border-paper-2 text-surface-grey-2 hover:text-text-standard",
      )}
    >
      Demo ×1000{demo ? " ●" : ""}
    </button>
  );
}

const LINKS = [
  { href: "/app", label: "Portfolio" },
  { href: "/app/deposit", label: "Deposit" },
  { href: "/app/withdraw", label: "Withdraw" },
  { href: "/app/vote", label: "Vote" },
  { href: "/app/distribute", label: "Distribute" },
  { href: "/app/deploy", label: "Deploy" },
];

function useNavLinks() {
  const { isAdmin } = useRegistryOwner();
  return isAdmin
    ? [
        ...LINKS,
        { href: "/app/recipients", label: "Recipients" },
        { href: "/app/admin", label: "Admin" },
      ]
    : LINKS;
}

function isActive(pathname: string, href: string) {
  return href === "/app" ? pathname === "/app" : pathname.startsWith(href);
}

export function DappNav() {
  const pathname = usePathname();
  const links = useNavLinks();

  return (
    <header className="border-paper-2 bg-paper-main/80 sticky top-0 z-50 border-b backdrop-blur">
      <nav className="section-container flex h-16 items-center gap-3">
        {/* Left: the instance IS the brand (white-label) — its badge + name. */}
        <InstanceSwitcher />

        {/* Center: page navigation (lg+) */}
        <div className="hidden flex-1 items-center justify-center gap-1 lg:flex">
          {links.map((l) => (
            <Link
              key={l.href}
              href={l.href}
              className={cn(
                "rounded-lg px-3 py-1.5 text-sm font-medium transition-colors",
                isActive(pathname, l.href)
                  ? "bg-core-orange/10 text-core-orange"
                  : "text-surface-grey-2 hover:text-text-standard",
              )}
            >
              {l.label}
            </Link>
          ))}
        </div>

        {/* Right: utilities */}
        <div className="ml-auto flex items-center gap-2 lg:ml-0">
          <DemoToggle />
          <ConnectButton
            showBalance={false}
            accountStatus="address"
            chainStatus="icon"
          />
        </div>
      </nav>

      {/* Compact nav row (below lg) */}
      <div className="border-paper-2 flex gap-1 overflow-x-auto border-t px-4 py-2 lg:hidden">
        {links.map((l) => (
          <Link
            key={l.href}
            href={l.href}
            className={cn(
              "rounded-lg px-3 py-1.5 text-sm font-medium whitespace-nowrap",
              isActive(pathname, l.href)
                ? "bg-core-orange/10 text-core-orange"
                : "text-surface-grey-2",
            )}
          >
            {l.label}
          </Link>
        ))}
      </div>
    </header>
  );
}
