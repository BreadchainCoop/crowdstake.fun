import type { Metadata } from "next";
import { DappNav } from "@/components/dapp/dapp-nav";

export const metadata: Metadata = {
  title: "Crowdstaking — App",
  description:
    "Deposit, vote, and distribute community yield on the Crowdstaking protocol.",
};

export default function AppLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="bg-paper-main min-h-screen">
      <DappNav />
      <main className="section-container py-10">{children}</main>
    </div>
  );
}
