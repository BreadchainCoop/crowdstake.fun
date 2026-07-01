import { IPFS_GATEWAY } from "@/lib/constants";

/**
 * Off-chain instance image URIs are fully untrusted (any instance owner can set
 * them), so only allow safe schemes for an <img src>: https, ipfs, and inline
 * raster data URIs. Reject http (mixed content on the HTTPS site), javascript:,
 * data:text/html, data:image/svg (script vector), blob:, file:, and relative.
 */
export function isValidImageUri(uri: string): boolean {
  const u = uri.trim();
  if (!u) return false;
  if (u.startsWith("ipfs://")) return u.length > "ipfs://".length;
  if (u.startsWith("https://")) return u.length > "https://".length;
  if (/^data:image\/(png|jpe?g|gif|webp);/i.test(u)) return true;
  return false;
}

/** Resolve an ipfs:// URI through the configured gateway; pass https/data through. */
export function resolveUri(uri?: string): string | undefined {
  if (!uri) return undefined;
  const u = uri.trim();
  if (!isValidImageUri(u)) return undefined;
  if (u.startsWith("ipfs://")) return IPFS_GATEWAY + u.slice("ipfs://".length);
  return u;
}
