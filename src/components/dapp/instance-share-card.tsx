"use client";

import { useState } from "react";
import { QRCodeSVG } from "qrcode.react";
import { Check, Copy } from "@phosphor-icons/react";
import type { Address } from "viem";
import { Body, Caption } from "@breadcoop/ui";
import { instanceShareUrl } from "@/lib/instance";
import { cn, copyToClipboard } from "@/lib/utils";

function LinkRow({
  label,
  url,
  hint,
}: {
  label: string;
  url: string;
  hint?: string;
}) {
  const [copied, setCopied] = useState(false);
  return (
    <div className="mt-3">
      <div className="flex items-center justify-between gap-2">
        <Caption className="text-surface-grey-2 font-semibold">{label}</Caption>
        {hint && (
          <Caption className="text-surface-grey text-[11px]">{hint}</Caption>
        )}
      </div>
      <div className="mt-1 flex items-center gap-2">
        <input
          readOnly
          value={url}
          onFocus={(e) => e.currentTarget.select()}
          className="border-paper-2 bg-paper-main text-text-standard w-full rounded-lg border px-2.5 py-2 font-mono text-xs outline-none"
        />
        <button
          onClick={async () => {
            if (await copyToClipboard(url)) {
              setCopied(true);
              setTimeout(() => setCopied(false), 1600);
            }
          }}
          aria-label={`Copy ${label} link`}
          className={cn(
            "flex flex-none items-center gap-1.5 rounded-lg px-3 py-2 text-sm font-semibold text-white",
            copied ? "bg-system-green" : "bg-core-orange",
          )}
        >
          {copied ? (
            <>
              <Check size={16} weight="bold" /> Copied
            </>
          ) : (
            <>
              <Copy size={16} /> Copy
            </>
          )}
        </button>
      </div>
    </div>
  );
}

/**
 * The instance's shareable page link (the `?i=<distributionManager>` deep link)
 * with a copy button and a QR. This is how a deployer hands their community its
 * own standalone page.
 */
export function InstanceShareCard({
  distributionManager,
  chainId,
}: {
  distributionManager: Address;
  chainId?: number;
}) {
  const shareUrl = instanceShareUrl(distributionManager, chainId);

  return (
    <div className="border-core-orange/30 bg-core-orange/5 rounded-xl border p-4">
      <div className="flex items-start gap-4">
        <div className="min-w-0 flex-1">
          <Caption className="text-text-standard font-semibold">
            Your instance&apos;s shareable page
          </Caption>
          <Body className="text-surface-grey-2 mt-1 text-sm">
            Anyone who opens this link lands on this instance — no setup needed.
          </Body>
          <LinkRow label="Link" url={shareUrl} />
        </div>
        <div className="hidden shrink-0 flex-col items-center sm:flex">
          <div className="border-paper-2 rounded-lg border bg-white p-2">
            <QRCodeSVG value={shareUrl} size={112} marginSize={2} />
          </div>
          <Caption className="text-surface-grey mt-1 block text-center text-[11px]">
            Scan to open
          </Caption>
        </div>
      </div>
    </div>
  );
}
