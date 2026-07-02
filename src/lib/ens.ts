import {
  createPublicClient,
  getAddress,
  http,
  isAddress,
  type Address,
  type PublicClient,
} from "viem";
import { mainnet } from "viem/chains";
import { normalize } from "viem/ens";
import { ENS_RPC_URL } from "@/lib/constants";

/**
 * ENS-based instance resolution. ENS lives on Ethereum MAINNET, not Gnosis, so
 * this uses its own read-only mainnet client — never the Gnosis app client.
 *
 * The whole point: a deployer can point an ENS name (e.g. `acme.crowdstake.eth`)
 * at their instance by setting a `crowdstake.instance` text record to the
 * distribution-manager address, then serve the app under it via eth.limo. When
 * the app loads at `acme.crowdstake.eth.limo`, it reads that record and boots
 * straight into their instance — a clean, memorable, fully on-chain per-instance
 * link with no query string.
 *
 * Everything here degrades to null on failure so a flaky mainnet RPC (or a
 * non-ENS host) never blocks app load; callers fall back to ?i= / localStorage.
 */

/** Text-record key that maps an ENS name to a CrowdStake distribution manager. */
export const ENS_INSTANCE_KEY = "crowdstake.instance";

// Lazily created so bundles/pages that never resolve ENS don't spin up a
// mainnet client (and so nothing touches the network at import time).
let client: PublicClient | null = null;
function ensClient(): PublicClient {
  if (!client) {
    client = createPublicClient({
      chain: mainnet,
      transport: http(ENS_RPC_URL),
    });
  }
  return client;
}

/**
 * Recover the bare ENS name from a host served via eth.limo / eth.link (or a
 * native `.eth` browser). Returns null for every non-ENS host (github.io,
 * localhost, a raw IPFS gateway), which makes the ENS path a strict no-op there
 * — this is what keeps GitHub Pages and the e2e harness unaffected.
 *
 *   acme.crowdstake.eth.limo -> acme.crowdstake.eth
 *   crowdstake.eth.link      -> crowdstake.eth
 *   crowdstake.eth           -> crowdstake.eth
 *   localhost / *.github.io  -> null
 */
export function ensNameFromHostname(hostname: string): string | null {
  const h = hostname.toLowerCase().replace(/\.$/, "");
  const m = h.match(/^((?:[a-z0-9-]+\.)*[a-z0-9-]+\.eth)(?:\.limo|\.link)?$/);
  return m ? m[1] : null;
}

/** The ENS name for the current browser host, or null when not an ENS host. */
export function ensHostFromLocation(): string | null {
  if (typeof window === "undefined") return null;
  return ensNameFromHostname(window.location.hostname);
}

/**
 * Read an ENS name's `crowdstake.instance` text record and return the
 * distribution-manager address it points at, or null. Uses viem's
 * getEnsText (Universal Resolver — supports CCIP-read/offchain subnames).
 */
export async function resolveInstanceFromEns(
  name: string,
): Promise<Address | null> {
  try {
    const value = await ensClient().getEnsText({
      name: normalize(name),
      key: ENS_INSTANCE_KEY,
    });
    return value && isAddress(value) ? (getAddress(value) as Address) : null;
  } catch {
    return null;
  }
}
