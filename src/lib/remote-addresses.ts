import { getAddress, isAddress, type Address } from "viem";
import { CHAINS, ENV_PINNED, type InstanceAddresses } from "@/lib/chains";

/**
 * Runtime contract-address hydration.
 *
 * The contracts-deploy workflow publishes an addresses.json manifest to the
 * rolling `contract-addresses` GitHub release on every deploy. Because this
 * frontend is a static export (GitHub Pages), fetching that manifest at
 * runtime means new deployments go live WITHOUT a frontend rebuild: the
 * baked-in addresses in chains.ts become mere fallbacks.
 *
 * Precedence (strongest first):
 *   1. Build-time NEXT_PUBLIC_* env pins (see ENV_PINNED — e2e fork builds)
 *   2. This manifest (latest release)
 *   3. Baked-in fallbacks in chains.ts
 *
 * CORS note: plain `github.com/releases/download/...` URLs don't send CORS
 * headers on the redirect, so browsers can't fetch them. api.github.com sends
 * `access-control-allow-origin: *` on every response (including the asset
 * redirect when requested with `Accept: application/octet-stream`), so we go
 * through the API: release-by-tag → asset → download. Both requests are
 * "simple" (no preflight) and anonymous (60 req/h/IP rate limit — fine for
 * one fetch per page load).
 */

const REPO = "BreadchainCoop/crowdstake.fun";
const RELEASE_TAG = "contract-addresses";
const ASSET_NAME = "addresses.json";
const FETCH_TIMEOUT_MS = 5_000;

/** Per-chain entry in the published manifest (all fields optional). */
interface ManifestChain {
  deployer?: string;
  factory?: string;
  defaultInstance?: Partial<Record<keyof InstanceAddresses, string>>;
}

interface Manifest {
  version: number;
  chains: Record<string, ManifestChain>;
}

const INSTANCE_KEYS = [
  "token",
  "distributionManager",
  "cycleModule",
  "votingModule",
  "recipientRegistry",
  "distributionStrategy",
  "votingPowerStrategy",
] as const satisfies readonly (keyof InstanceAddresses)[];

function fetchJson(url: string, accept?: string): Promise<unknown> {
  return fetch(url, {
    cache: "no-store",
    signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
    headers: accept ? { Accept: accept } : undefined,
  }).then((r) => {
    if (!r.ok) throw new Error(`${url} → HTTP ${r.status}`);
    return r.json();
  });
}

/** Fetch the manifest — direct URL override, or via the GitHub API release. */
async function fetchManifest(): Promise<Manifest> {
  // NOTE: must be a static literal for Next to inline it into the bundle.
  const override = process.env.NEXT_PUBLIC_ADDRESSES_URL;
  if (override && override.length > 0) {
    return (await fetchJson(override)) as Manifest;
  }
  const release = (await fetchJson(
    `https://api.github.com/repos/${REPO}/releases/tags/${RELEASE_TAG}`,
  )) as { assets?: { name: string; url: string }[] };
  const asset = release.assets?.find((a) => a.name === ASSET_NAME);
  if (!asset) throw new Error(`release has no ${ASSET_NAME} asset`);
  return (await fetchJson(
    asset.url,
    "application/octet-stream",
  )) as Manifest;
}

/** A checksummed address, or null if the input isn't a valid address. */
function addr(v: string | undefined): Address | null {
  return v && isAddress(v, { strict: false }) ? getAddress(v) : null;
}

/**
 * Fetch the latest published addresses and merge them into CHAINS in place.
 * In-place mutation (rather than replacement) keeps module-level captures of
 * `defaultInstance` (e.g. DEFAULT_INSTANCE in lib/instance.ts) up to date.
 * Fail-soft: on any error the baked-in addresses stay untouched.
 *
 * @returns true if anything was updated (callers re-render on that signal).
 */
export async function hydrateRemoteAddresses(): Promise<boolean> {
  // "off" (or running outside a browser) disables runtime hydration entirely.
  if (process.env.NEXT_PUBLIC_ADDRESSES_URL === "off") return false;
  if (typeof window === "undefined") return false;

  let manifest: Manifest;
  try {
    manifest = await fetchManifest();
  } catch (e) {
    console.warn("[remote-addresses] using baked-in addresses:", e);
    return false;
  }
  if (manifest?.version !== 1 || typeof manifest.chains !== "object") {
    console.warn("[remote-addresses] unrecognized manifest — ignoring");
    return false;
  }

  let updated = false;
  for (const [idStr, entry] of Object.entries(manifest.chains)) {
    const cfg = CHAINS[Number(idStr)];
    if (!cfg || !entry) continue;
    const pinned = ENV_PINNED[Number(idStr)] ?? {
      deployer: false,
      instance: false,
    };

    const deployer = addr(entry.deployer);
    if (deployer && !pinned.deployer && cfg.deployer !== deployer) {
      cfg.deployer = deployer;
      cfg.deployable = true;
      updated = true;
    }

    const di = entry.defaultInstance;
    if (di && !pinned.instance) {
      // All seven addresses must be present + valid, else skip the instance.
      const next = {} as InstanceAddresses;
      let complete = true;
      for (const k of INSTANCE_KEYS) {
        const v = addr(di[k]);
        if (v === null) {
          complete = false;
          break;
        }
        next[k] = v;
      }
      if (complete) {
        if (cfg.defaultInstance) {
          if (INSTANCE_KEYS.some((k) => cfg.defaultInstance![k] !== next[k])) {
            Object.assign(cfg.defaultInstance, next);
            updated = true;
          }
        } else {
          cfg.defaultInstance = next;
          updated = true;
        }
      }
    }
  }
  return updated;
}
