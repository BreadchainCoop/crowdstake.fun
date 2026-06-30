import type { Metadata } from "next";
import "./globals.css";
import { Providers } from "@/components/providers";

export const metadata: Metadata = {
  title: "Crowdstaking — Community-Powered Funding Protocol",
  description:
    "Transform any pool of money into a democratic, interest-generating engine for your group's shared goals. Open source, free, and customizable.",
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
