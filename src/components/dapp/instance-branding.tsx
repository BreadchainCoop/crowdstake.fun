"use client";

import { useInstanceKind } from "@/hooks/use-instance-kind";
import { useInstanceMetadata } from "@/hooks/use-instance-metadata";
import { useInstanceToken } from "@/hooks/use-token";
import { SafeImage } from "@/components/dapp/safe-image";
import { cn } from "@/lib/utils";

/** Full-width instance banner shown above the app; renders nothing when unset. */
export function InstanceHeaderBanner() {
  const { bannerImageURI } = useInstanceMetadata();
  if (!bannerImageURI) return null;
  return (
    <div className="border-paper-2 border-b">
      <SafeImage
        uri={bannerImageURI}
        alt="Instance banner"
        className="h-28 w-full object-cover sm:h-36"
      />
    </div>
  );
}

/** The active instance's token image, falling back to an initial disc. */
export function InstanceTokenBadge({ className }: { className?: string }) {
  const { tokenImageURI } = useInstanceMetadata();
  const { name, symbol } = useInstanceToken();
  const { isPool } = useInstanceKind();
  // Pools carry the UNDERLYING's symbol (every Gnosis pool would badge "W") —
  // their identity is the community name. Token instances keep the ticker.
  const label = isPool ? name || symbol : symbol;
  const box = cn("h-10 w-10 shrink-0 rounded-full object-cover", className);
  return (
    <SafeImage
      uri={tokenImageURI}
      alt={isPool ? `${label} pool` : `${label} token`}
      className={box}
      fallback={
        <div
          className={cn(
            box,
            "bg-core-orange/15 text-core-orange flex items-center justify-center text-sm font-bold",
          )}
        >
          {(label || "?").slice(0, 1).toUpperCase()}
        </div>
      }
    />
  );
}
