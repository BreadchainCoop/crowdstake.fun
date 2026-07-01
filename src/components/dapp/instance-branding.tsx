"use client";

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

/** The active instance's token image, falling back to a symbol-initial disc. */
export function InstanceTokenBadge({ className }: { className?: string }) {
  const { tokenImageURI } = useInstanceMetadata();
  const { symbol } = useInstanceToken();
  const box = cn("h-10 w-10 shrink-0 rounded-full object-cover", className);
  return (
    <SafeImage
      uri={tokenImageURI}
      alt={`${symbol} token`}
      className={box}
      fallback={
        <div
          className={cn(
            box,
            "bg-core-orange/15 text-core-orange flex items-center justify-center text-sm font-bold",
          )}
        >
          {symbol.slice(0, 1).toUpperCase()}
        </div>
      }
    />
  );
}
