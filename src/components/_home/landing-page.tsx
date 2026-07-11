import type { ReactNode } from "react";
import Link from "next/link";
import {
  Body,
  Button,
  Caption,
  Chip,
  Heading2,
  Heading3,
  Logo,
} from "@breadcoop/ui";
import { ArrowRight, CheckCircle } from "@phosphor-icons/react/dist/ssr";
import { FundingCalculator } from "@/components/_home/funding-calculator";
import { HowItWorks } from "@/components/_home/how-it-works";
import { YieldEngine } from "@/components/_home/yield-engine";
import { YieldSliceExplainer } from "@/components/_home/yield-slice-explainer";

const DOCS_URL = "/docs"; // in-app documentation & walkthroughs
const GITHUB_URL = "https://github.com/BreadchainCoop/crowdstake.fun";

export function LandingPage() {
  return (
    <div className="bg-paper-main min-h-screen">
      <SiteNav />
      <main>
        <Hero />
        <UnderTheHood />
        <YieldSliceExplainer />
        <HowItWorks />
        <YieldEngine />
        <CalculatorSection />
        <GetStarted />
        <CtaBand />
      </main>
      <SiteFooter />
    </div>
  );
}

/* ---------------------------------- Nav ---------------------------------- */

function SiteNav() {
  return (
    <header className="border-paper-2 bg-paper-main/80 tg-safe-top sticky top-0 z-50 border-b backdrop-blur">
      <nav className="section-container flex h-16 items-center justify-between">
        <a href="#top" className="flex items-center gap-2">
          <Logo variant="square" color="orange" size={32} />
          <span className="font-breadDisplay text-text-standard text-xl font-bold">
            Crowdstaking
          </span>
        </a>
        <div className="hidden items-center gap-8 md:flex">
          <NavLink href="#how-it-works">How it Works</NavLink>
          <NavLink href="#get-started">Get Started</NavLink>
        </div>
        <div className="flex items-center gap-3">
          <Button
            app="fund"
            variant="secondary"
            size="sm"
            as={Link}
            href={DOCS_URL}
          >
            Documentation
          </Button>
          <Button app="fund" variant="primary" size="sm" as={Link} href="/app">
            Launch App
          </Button>
        </div>
      </nav>
    </header>
  );
}

function NavLink({ href, children }: { href: string; children: ReactNode }) {
  return (
    <a
      href={href}
      className="text-surface-grey-2 hover:text-core-orange text-sm font-medium transition-colors"
    >
      {children}
    </a>
  );
}

/* --------------------------------- Hero ---------------------------------- */

function Hero() {
  return (
    <section
      id="top"
      className="section-container py-20 lg:py-28"
    >
      <div className="mx-auto flex max-w-2xl flex-col justify-center text-center">
        <h1 className="font-breadDisplay text-core-orange text-6xl leading-[1.04] font-extrabold tracking-tight break-words sm:text-7xl">
          Crowdstaking
        </h1>
        <Heading2 className="text-primary-jade mt-2 italic">
          Turning shared funds into shared futures.
        </Heading2>
        <Body className="text-surface-grey-2 mx-auto mt-6 max-w-xl text-lg">
          Crowdstaking transforms any pool of money into an interest-generating
          engine to fund your group&apos;s shared goals. Your deposited funds
          remain safely staked and fully withdrawable — only the interest gets
          allocated.
        </Body>
        <div className="mt-8 flex flex-wrap justify-center gap-4">
          <Button
            app="fund"
            variant="primary"
            as="a"
            href="#get-started"
            rightIcon={<ArrowRight weight="bold" />}
          >
            Deploy Your Instance
          </Button>
          <Button app="fund" variant="secondary" as={Link} href="/app">
            Launch App
          </Button>
        </div>
        <ul className="mt-8 flex flex-wrap justify-center gap-x-6 gap-y-2">
          {[
            "Open source protocol",
            "Fully customizable",
            "Decentralized governance",
          ].map((point) => (
            <li key={point} className="flex items-center gap-2">
              <CheckCircle
                size={18}
                weight="fill"
                className="text-system-green"
              />
              <Caption className="text-surface-grey-2">{point}</Caption>
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}

/* ---------------------------- Calculator --------------------------------- */

function CalculatorSection() {
  return (
    <section id="calculator" className="bg-paper-1 py-20">
      <div className="section-container flex justify-center">
        <FundingCalculator />
      </div>
    </section>
  );
}

/* ----------------------------- Under the Hood ---------------------------- */

function UnderTheHood() {
  return (
    <section className="bg-paper-1 py-20">
      <div className="section-container text-center">
        <Heading2 className="text-text-standard">Under the Hood</Heading2>
        <Body className="text-surface-grey-2 mx-auto mt-6 max-w-4xl text-lg">
          The Crowdstaking application is a smart contract system on Gnosis
          Chain that accepts users&apos; xDAI and converts it into sDAI
          (yield-bearing stablecoins). In exchange, stakers receive
          project-specific tokens minted at a 1:1 ratio with their
          collateralized xDAI. All interest earned on the sDAI funds their
          shared goal.
        </Body>
      </div>
    </section>
  );
}

/* ------------------------------ Get Started ------------------------------ */

function GetStarted() {
  return (
    <section id="get-started" className="bg-paper-1 py-20">
      <div className="section-container">
        <Heading2 className="text-text-standard text-center">
          Start funding your community goal today
        </Heading2>
        <Body className="text-surface-grey-2 mt-3 text-center text-lg">
          Crowdstaking is completely free and open source.
        </Body>

        <div className="mx-auto mt-12 grid max-w-4xl gap-6 md:grid-cols-2">
          <DeployCard
            badge="Recommended"
            badgeClassName="text-core-orange"
            title="Quick Deploy"
            body="Get your community protocol running in minutes with our hosted solution. Perfect for communities who want to focus on their mission, not technical setup."
            timeline="24-48 hours"
            technical="None required"
          >
            <Button app="fund" variant="primary" as={Link} href="/app/deploy">
              Start Quick Deploy
            </Button>
          </DeployCard>

          <DeployCard
            badge="Advanced"
            badgeClassName="text-primary-jade"
            title="Self-Deploy"
            body="Deploy and customize your own instance with full control over smart contracts, infrastructure, and governance parameters."
            timeline="1-2 weeks"
            technical="Solidity & Web3"
          >
            <Button app="fund" variant="secondary" as={Link} href={DOCS_URL}>
              View Documentation
            </Button>
            <Button app="fund" variant="secondary" as="a" href={GITHUB_URL}>
              Clone Repository
            </Button>
          </DeployCard>
        </div>

        <div className="mt-10 text-center">
          <Body className="text-surface-grey-2">
            Need help deciding? Our team is here to guide you.
          </Body>
          <div className="mt-3 flex justify-center">
            <Button app="fund" variant="secondary" as="a" href={GITHUB_URL}>
              Schedule a Consultation
            </Button>
          </div>
        </div>
      </div>
    </section>
  );
}

function DeployCard({
  badge,
  badgeClassName,
  title,
  body,
  timeline,
  technical,
  children,
}: {
  badge: string;
  badgeClassName?: string;
  title: string;
  body: string;
  timeline: string;
  technical: string;
  children: ReactNode;
}) {
  return (
    <div className="border-paper-2 bg-paper-0 flex flex-col rounded-2xl border-2 p-6 transition-shadow hover:shadow-xl">
      <div className="flex items-center justify-between">
        <Heading3 className="text-text-standard">{title}</Heading3>
        <Chip size="small" className={badgeClassName}>
          {badge}
        </Chip>
      </div>
      <Body className="text-surface-grey-2 mt-3">{body}</Body>
      <dl className="mt-6 space-y-2">
        <StatRow label="Timeline" value={timeline} />
        <StatRow label="Technical knowledge" value={technical} />
      </dl>
      <div className="mt-6 flex flex-wrap gap-3">{children}</div>
    </div>
  );
}

function StatRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="border-paper-2 flex items-center justify-between border-t pt-2">
      <Caption className="text-surface-grey">{label}</Caption>
      <Caption className="text-text-standard font-semibold">{value}</Caption>
    </div>
  );
}

/* ------------------------------- CTA band -------------------------------- */

function CtaBand() {
  return (
    <section className="bg-core-orange py-20 text-white">
      <div className="section-container text-center">
        <Heading2 className="text-white">
          Ready to empower your community?
        </Heading2>
        <Body className="mx-auto mt-4 max-w-3xl text-lg text-white/90">
          Join the movement of communities using Crowdstaking to fund real-world
          impact. Deploy your economic toolkit today.
        </Body>
        <div className="mt-8 flex flex-wrap justify-center gap-4">
          <Button app="fund" variant="light" as="a" href="#get-started">
            Deploy Your Instance
          </Button>
          <Button app="fund" variant="light" as={Link} href={DOCS_URL}>
            View Documentation
          </Button>
        </div>
      </div>
    </section>
  );
}

/* -------------------------------- Footer --------------------------------- */

const FOOTER_COLUMNS: { heading: string; links: string[] }[] = [
  {
    heading: "Protocol",
    links: ["Documentation", "GitHub", "Audits", "Governance"],
  },
  {
    heading: "Community",
    links: ["Discord", "Twitter", "Blog", "Case Studies"],
  },
  {
    heading: "Support",
    links: ["Help Center", "Contact", "Developer Portal", "Status"],
  },
];

function SiteFooter() {
  return (
    <footer className="border-paper-2 bg-paper-main border-t py-14">
      <div className="section-container grid gap-10 md:grid-cols-4">
        <div className="max-w-xs">
          <div className="flex items-center gap-2">
            <Logo variant="square" color="orange" size={28} />
            <span className="font-breadDisplay text-text-standard text-lg font-bold">
              Crowdstaking
            </span>
          </div>
          <Body className="text-surface-grey-2 mt-3">
            An open-source economic primitive for participatory community
            funding.
          </Body>
        </div>
        {FOOTER_COLUMNS.map((col) => (
          <div key={col.heading}>
            <Caption className="text-text-standard font-semibold">
              {col.heading}
            </Caption>
            <ul className="mt-4 space-y-2">
              {col.links.map((link) =>
                link === "Documentation" ? (
                  <li key={link}>
                    <Link
                      href={DOCS_URL}
                      className="text-surface-grey-2 hover:text-core-orange text-sm transition-colors"
                    >
                      {link}
                    </Link>
                  </li>
                ) : (
                  <li key={link}>
                    <a
                      href={GITHUB_URL}
                      className="text-surface-grey-2 hover:text-core-orange text-sm transition-colors"
                    >
                      {link}
                    </a>
                  </li>
                ),
              )}
            </ul>
          </div>
        ))}
      </div>
      <div className="section-container border-paper-2 mt-10 border-t pt-6">
        <Caption className="text-surface-grey">
          © 2024 Crowdstaking. All rights reserved.
        </Caption>
      </div>
    </footer>
  );
}
