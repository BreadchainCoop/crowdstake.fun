"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import { Logo } from "@breadcoop/ui";
import { cn } from "@/lib/utils";
import { useRegistryOwner } from "@/hooks/use-recipients";
import { InstanceSwitcher } from "@/components/dapp/instance-switcher";

const LINKS = [
  { href: "/app", label: "Portfolio" },
  { href: "/app/deposit", label: "Deposit" },
  { href: "/app/withdraw", label: "Withdraw" },
  { href: "/app/vote", label: "Vote" },
  { href: "/app/distribute", label: "Distribute" },
  { href: "/app/deploy", label: "Deploy" },
];

export function DappNav() {
  const pathname = usePathname();
  const { isAdmin } = useRegistryOwner();
  const links = isAdmin
    ? [
        ...LINKS,
        { href: "/app/recipients", label: "Recipients" },
        { href: "/app/admin", label: "Admin" },
      ]
    : LINKS;

  return (
    <header className="border-paper-2 bg-paper-main/80 sticky top-0 z-50 border-b backdrop-blur">
      <nav className="section-container flex h-16 items-center justify-between gap-4">
        <Link href="/" className="flex items-center gap-2">
          <Logo variant="square" color="orange" size={28} />
          <span className="font-breadDisplay text-text-standard hidden text-lg font-bold sm:block">
            Crowdstaking
          </span>
        </Link>

        <div className="hidden items-center gap-1 md:flex">
          {links.map((l) => {
            const active =
              l.href === "/app"
                ? pathname === "/app"
                : pathname.startsWith(l.href);
            return (
              <Link
                key={l.href}
                href={l.href}
                className={cn(
                  "rounded-lg px-3 py-1.5 text-sm font-medium transition-colors",
                  active
                    ? "bg-core-orange/10 text-core-orange"
                    : "text-surface-grey-2 hover:text-text-standard",
                )}
              >
                {l.label}
              </Link>
            );
          })}
        </div>

        <div className="flex items-center gap-2">
          <InstanceSwitcher />
          <ConnectButton
            showBalance={false}
            accountStatus="address"
            chainStatus="icon"
          />
        </div>
      </nav>

      {/* Mobile nav */}
      <div className="border-paper-2 flex gap-1 overflow-x-auto border-t px-4 py-2 md:hidden">
        {links.map((l) => {
          const active =
            l.href === "/app"
              ? pathname === "/app"
              : pathname.startsWith(l.href);
          return (
            <Link
              key={l.href}
              href={l.href}
              className={cn(
                "rounded-lg px-3 py-1.5 text-sm font-medium whitespace-nowrap",
                active
                  ? "bg-core-orange/10 text-core-orange"
                  : "text-surface-grey-2",
              )}
            >
              {l.label}
            </Link>
          );
        })}
      </div>
    </header>
  );
}
