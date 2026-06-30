"use client";

import type { ReactNode } from "react";
import Link from "next/link";
import { Body, Button, Caption, Logo } from "@breadcoop/ui";
import {
  ArrowRight,
  ArrowsLeftRight,
  ArrowSquareOut,
  Coins,
  HandCoins,
  Plugs,
  Rocket,
  Stack,
  Users,
  Wallet,
  ChartBar,
} from "@phosphor-icons/react";
import { ADDRESSES, DEPLOYER, addressUrl } from "@/lib/constants";

// Static export honours NEXT_PUBLIC_BASE_PATH (e.g. /crowdstake.fun on Pages).
// Plain <img> tags don't get it prepended automatically, so do it here.
const BASE = process.env.NEXT_PUBLIC_BASE_PATH || "";
const gif = (name: string) => `${BASE}/docs/${name}`;

type Flow = {
  id: string;
  n: number;
  icon: ReactNode;
  title: string;
  blurb: string;
  steps: string[];
  media: string;
};

const FLOWS: Flow[] = [
  {
    id: "explore",
    n: 1,
    icon: <ChartBar weight="duotone" />,
    title: "Explore & launch",
    blurb:
      "The landing page sizes a community fund for you: set a monthly interest target and it computes the members and stake required at the current yield.",
    steps: [
      "Drag the Community Funding Calculator to your monthly interest goal.",
      "Browse Features and How it Works to understand the deposit → yield → vote → distribute loop.",
      "Hit Launch App to open the dashboard.",
    ],
    media: "landing-tour.gif",
  },
  {
    id: "connect",
    n: 2,
    icon: <Plugs weight="duotone" />,
    title: "Connect a wallet",
    blurb:
      "Every action page is browsable before connecting — forms and live on-chain data render immediately. Connecting is only required to sign.",
    steps: [
      "Click Connect Wallet in the top bar.",
      "Pick your wallet in the RainbowKit modal (MetaMask, Rabby, WalletConnect, …).",
      "Approve the connection on Gnosis Chain (id 100). Wrong network? The button switches you.",
    ],
    media: "connect-wallet.gif",
  },
  {
    id: "deposit",
    n: 3,
    icon: <Coins weight="duotone" />,
    title: "Deposit",
    blurb:
      "Stake xDAI to mint CSTAKE 1:1. Your principal stays fully withdrawable — only the interest it earns is ever distributed.",
    steps: [
      "Choose xDAI (native) or WXDAI. Native wraps automatically.",
      "Enter an amount — you'll see exactly how much CSTAKE you receive.",
      "With WXDAI, approve once, then Deposit. Native deposits in a single transaction.",
    ],
    media: "deposit.gif",
  },
  {
    id: "withdraw",
    n: 4,
    icon: <Wallet weight="duotone" />,
    title: "Withdraw",
    blurb:
      "Burn CSTAKE to redeem your xDAI principal 1:1, any time. Your stake is never locked.",
    steps: [
      "Enter the amount of CSTAKE to redeem (Max fills your balance).",
      "Confirm — you receive the equivalent xDAI back to your wallet.",
    ],
    media: "withdraw.gif",
  },
  {
    id: "vote",
    n: 5,
    icon: <Users weight="duotone" />,
    title: "Vote",
    blurb:
      "Allocate your voting power across recipients. Each recipient's share of the next distribution is proportional to its total weighted votes.",
    steps: [
      "Review the active recipients and their current shares.",
      "Drag each slider to weight recipients (relative — they don't have to sum to 100%).",
      "Cast your vote. Your weight is scaled by your voting power and counted for the cycle.",
    ],
    media: "vote.gif",
  },
  {
    id: "distribute",
    n: 6,
    icon: <HandCoins weight="duotone" />,
    title: "Distribute",
    blurb:
      "Once a cycle completes, anyone can trigger the distribution. Accrued sDAI yield is claimed, split among recipients by their votes, and the cycle advances.",
    steps: [
      "Check the readiness panel: cycle complete, recipients present, votes cast, yield accrued.",
      "Trigger Claim & distribute — permissionless, no admin required.",
      "Yield is minted as CSTAKE to recipients pro-rata and a fresh cycle begins.",
    ],
    media: "distribute.gif",
  },
  {
    id: "recipients",
    n: 7,
    icon: <Stack weight="duotone" />,
    title: "Recipients",
    blurb:
      "The recipient registry is public and browsable by anyone. The registry admin queues additions and removals, then applies them in one transaction.",
    steps: [
      "Anyone can view the active recipients and any pending changes.",
      "The admin queues an address to add, or queues a recipient for removal.",
      "Process queue applies all pending changes; recipients then appear on the Vote page.",
    ],
    media: "recipients.gif",
  },
  {
    id: "deploy",
    n: 8,
    icon: <Rocket weight="duotone" />,
    title: "Deploy your own instance",
    blurb:
      "Launch a complete, self-owned Crowdstaking system on Gnosis in a single transaction via the CrowdStakeDeployer. You become the admin of every contract.",
    steps: [
      "Name your token and symbol, and set a cycle length in blocks (~5s each on Gnosis).",
      "Optionally set an owner (defaults to your address).",
      "Deploy — token, cycle module, voting module + power, recipient registry, and distribution manager are wired and handed to you.",
    ],
    media: "deploy.gif",
  },
  {
    id: "switch",
    n: 9,
    icon: <ArrowsLeftRight weight="duotone" />,
    title: "Switch between instances",
    blurb:
      "The app is multi-instance. Run the default deployment, your own, or anyone's — all from the same dashboard, persisted locally.",
    steps: [
      "Open the instance switcher in the top bar.",
      "Add any instance by its distribution-manager address; the app resolves the full system.",
      "Switch the active instance — every page re-reads from it.",
    ],
    media: "instance-switcher.gif",
  },
];

const SYSTEM = [
  ["Project token (CSTAKE)", ADDRESSES.token],
  ["Distribution manager", ADDRESSES.distributionManager],
  ["Cycle module", ADDRESSES.cycleModule],
  ["Voting module", ADDRESSES.votingModule],
  ["Recipient registry", ADDRESSES.recipientRegistry],
  ["Distribution strategy", ADDRESSES.distributionStrategy],
  ["Voting-power strategy", ADDRESSES.votingPowerStrategy],
  ["CrowdStake deployer", DEPLOYER],
] as const;

export default function DocsPage() {
  return (
    <div className="bg-paper-main min-h-screen">
      <DocsNav />

      {/* Hero */}
      <header className="section-container pt-16 pb-10">
        <Caption className="text-core-orange font-semibold tracking-wide uppercase">
          Documentation
        </Caption>
        <h1 className="font-breadDisplay text-text-standard mt-3 text-5xl font-extrabold tracking-tight sm:text-6xl">
          Every flow, end to end
        </h1>
        <Body className="text-surface-grey-2 mt-4 max-w-2xl text-lg">
          A step-by-step walkthrough of Crowdstaking on Gnosis — from sizing a
          community fund to depositing, voting, distributing yield, and
          deploying your own instance. Each section pairs a short recording with
          the exact steps.
        </Body>
        <div className="mt-6 flex flex-wrap gap-3">
          <Button app="fund" variant="primary" as={Link} href="/app">
            Open the app
          </Button>
          <Button app="fund" variant="secondary" as={Link} href="/">
            Back to home
          </Button>
        </div>
      </header>

      {/* Contents */}
      <nav className="section-container pb-8">
        <div className="border-paper-2 bg-paper-0 rounded-2xl border p-5">
          <Caption className="text-surface-grey-2">On this page</Caption>
          <ol className="mt-3 grid gap-x-6 gap-y-2 sm:grid-cols-2 lg:grid-cols-3">
            {FLOWS.map((f) => (
              <li key={f.id}>
                <a
                  href={`#${f.id}`}
                  className="text-text-standard hover:text-core-orange flex items-center gap-2 text-sm font-medium transition-colors"
                >
                  <span className="bg-core-orange/10 text-core-orange inline-flex h-6 w-6 shrink-0 items-center justify-center rounded-full text-xs font-bold">
                    {f.n}
                  </span>
                  {f.title}
                </a>
              </li>
            ))}
          </ol>
        </div>
      </nav>

      {/* Walkthrough note */}
      <div className="section-container pb-12">
        <div className="border-primary-jade/30 bg-primary-jade/5 rounded-2xl border px-5 py-4">
          <Body className="text-surface-grey-2 text-sm">
            <span className="text-text-standard font-semibold">
              About these recordings.
            </span>{" "}
            The clips are real UI walkthroughs captured against the live
            dashboard reading on-chain Gnosis state. The wallet-signing step is
            shown up to the confirmation prompt; the signed transactions
            themselves (deposit, vote, distribute, deploy, admin) are verified
            on-chain — see the live system addresses at the bottom of this page.
          </Body>
        </div>
      </div>

      {/* Flows */}
      <main className="section-container space-y-20 pb-24">
        {FLOWS.map((f, i) => (
          <FlowSection key={f.id} flow={f} eager={i === 0} />
        ))}

        {/* Live system */}
        <section id="system" className="scroll-mt-20">
          <div className="flex items-center gap-3">
            <span className="bg-core-orange/10 text-core-orange inline-flex h-9 w-9 items-center justify-center rounded-xl">
              <ArrowSquareOut weight="duotone" size={20} />
            </span>
            <h2 className="font-breadDisplay text-text-standard text-3xl font-extrabold tracking-tight">
              Live on Gnosis
            </h2>
          </div>
          <Body className="text-surface-grey-2 mt-3 max-w-2xl">
            The default instance is deployed and verifiable on Gnosis mainnet
            (chain id 100). Every contract below is live — open it on
            Gnosisscan.
          </Body>
          <div className="border-paper-2 divide-paper-2 bg-paper-0 mt-6 divide-y overflow-hidden rounded-2xl border">
            {SYSTEM.map(([label, addr]) => (
              <a
                key={label}
                href={addressUrl(addr)}
                target="_blank"
                rel="noreferrer"
                className="hover:bg-paper-1 flex items-center justify-between gap-4 px-5 py-3.5 transition-colors"
              >
                <span className="text-text-standard text-sm font-medium">
                  {label}
                </span>
                <span className="text-surface-grey-2 hover:text-core-orange flex items-center gap-2 font-mono text-xs sm:text-sm">
                  {addr}
                  <ArrowSquareOut size={14} />
                </span>
              </a>
            ))}
          </div>
        </section>

        {/* Footer CTA */}
        <section className="border-paper-2 bg-paper-0 rounded-3xl border px-8 py-12 text-center">
          <h2 className="font-breadDisplay text-text-standard text-3xl font-extrabold tracking-tight">
            Ready to try it?
          </h2>
          <Body className="text-surface-grey-2 mx-auto mt-3 max-w-xl">
            Open the dashboard to deposit, vote, and distribute — or deploy your
            own community instance in one transaction.
          </Body>
          <div className="mt-6 flex flex-wrap justify-center gap-3">
            <Button
              app="fund"
              variant="primary"
              as={Link}
              href="/app"
              rightIcon={<ArrowRight weight="bold" />}
            >
              Launch App
            </Button>
            <Button app="fund" variant="secondary" as={Link} href="/app/deploy">
              Deploy an instance
            </Button>
          </div>
        </section>
      </main>
    </div>
  );
}

function FlowSection({ flow, eager }: { flow: Flow; eager?: boolean }) {
  return (
    <section id={flow.id} className="scroll-mt-20">
      <div className="flex items-center gap-3">
        <span className="bg-core-orange/10 text-core-orange inline-flex h-9 w-9 items-center justify-center rounded-xl text-xl">
          {flow.icon}
        </span>
        <Caption className="text-surface-grey font-semibold">
          Step {flow.n}
        </Caption>
      </div>
      <h2 className="font-breadDisplay text-text-standard mt-2 text-3xl font-extrabold tracking-tight">
        {flow.title}
      </h2>
      <Body className="text-surface-grey-2 mt-3 max-w-2xl">{flow.blurb}</Body>

      <div className="mt-6 grid gap-8 lg:grid-cols-[1fr_1.4fr] lg:items-start">
        <ol className="space-y-4">
          {flow.steps.map((s, i) => (
            <li key={i} className="flex gap-3">
              <span className="bg-core-orange mt-0.5 inline-flex h-6 w-6 shrink-0 items-center justify-center rounded-full text-xs font-bold text-white">
                {i + 1}
              </span>
              <Body className="text-text-standard">{s}</Body>
            </li>
          ))}
        </ol>

        <figure className="border-paper-2 bg-paper-0 overflow-hidden rounded-2xl border shadow-sm">
          <div className="border-paper-2 bg-paper-1 flex items-center gap-1.5 border-b px-4 py-2.5">
            <span className="h-2.5 w-2.5 rounded-full bg-[#ff5f57]" />
            <span className="h-2.5 w-2.5 rounded-full bg-[#febc2e]" />
            <span className="h-2.5 w-2.5 rounded-full bg-[#28c840]" />
            <Caption className="text-surface-grey ml-3 truncate">
              crowdstake.fun — {flow.title}
            </Caption>
          </div>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={gif(flow.media)}
            alt={`${flow.title} walkthrough`}
            width={900}
            height={563}
            className="block h-auto w-full"
            loading={eager ? "eager" : "lazy"}
          />
        </figure>
      </div>
    </section>
  );
}

function DocsNav() {
  return (
    <header className="border-paper-2 bg-paper-main/80 sticky top-0 z-50 border-b backdrop-blur">
      <nav className="section-container flex h-16 items-center justify-between">
        <Link href="/" className="flex items-center gap-2">
          <Logo variant="square" color="orange" size={32} />
          <span className="font-breadDisplay text-text-standard text-xl font-bold">
            Crowdstaking
          </span>
        </Link>
        <div className="flex items-center gap-3">
          <Button app="fund" variant="secondary" size="sm" as={Link} href="/">
            Home
          </Button>
          <Button app="fund" variant="primary" size="sm" as={Link} href="/app">
            Launch App
          </Button>
        </div>
      </nav>
    </header>
  );
}
