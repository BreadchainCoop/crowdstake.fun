"use client";

import { useState, type ReactNode } from "react";
import { resolveUri } from "@/lib/metadata";

/**
 * Renders an untrusted off-chain image URI safely: only https/ipfs/raster-data
 * URIs are ever set as src (via resolveUri), with no-referrer + lazy loading,
 * falling back to `fallback` on an invalid URI or load error.
 */
export function SafeImage({
  uri,
  alt,
  className,
  fallback = null,
}: {
  uri?: string;
  alt: string;
  className?: string;
  fallback?: ReactNode;
}) {
  const [errored, setErrored] = useState(false);
  const src = resolveUri(uri);
  if (!src || errored) return <>{fallback}</>;
  return (
    // eslint-disable-next-line @next/next/no-img-element
    <img
      src={src}
      alt={alt}
      className={className}
      loading="lazy"
      referrerPolicy="no-referrer"
      onError={() => setErrored(true)}
    />
  );
}
