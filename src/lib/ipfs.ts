/**
 * Client-side helpers for publishing the app to IPFS from the browser — no CI,
 * no repo secrets. Two ways to gather the files to pin:
 *   - self-pin: the deployed app fetches its own files via a build manifest
 *     (only valid on the root-served build; a subpath build bakes in the wrong
 *     asset paths), and
 *   - folder upload: the user drops their local `pnpm build:ipfs` output.
 */

/** The manifest emitted by scripts/gen-ipfs-manifest.mjs (build:ipfs only). */
const MANIFEST_PATH = "/ipfs-manifest.json";

/**
 * True when this build is served from a root origin (empty base path) and can
 * therefore validly re-pin itself — a subpath build (/crowdstake.fun) would
 * pin HTML/asset paths that break at an IPFS/ENS root. Static process.env ref
 * so the value is inlined per build.
 */
export const canSelfPin = !process.env.NEXT_PUBLIC_BASE_PATH;

export type Progress = (done: number, total: number) => void;

/** Fetch the running app's own files (self-pin), preserving relative paths. */
export async function collectSelfFiles(onProgress?: Progress): Promise<File[]> {
  const res = await fetch(MANIFEST_PATH, { cache: "no-store" });
  if (!res.ok) {
    throw new Error(
      "No build manifest found — this build wasn't produced by `pnpm build:ipfs`. Use the folder upload instead.",
    );
  }
  const paths = (await res.json()) as string[];
  const files: File[] = [];
  let done = 0;
  // Small concurrency so a ~100-file bundle pins quickly without hammering.
  const BATCH = 6;
  for (let i = 0; i < paths.length; i += BATCH) {
    const batch = paths.slice(i, i + BATCH);
    const fetched = await Promise.all(
      batch.map(async (path) => {
        const r = await fetch("/" + path, { cache: "no-store" });
        if (!r.ok) throw new Error(`Failed to fetch ${path}`);
        const blob = await r.blob();
        return new File([blob], path, { type: blob.type });
      }),
    );
    files.push(...fetched);
    done += batch.length;
    onProgress?.(done, paths.length);
  }
  // Include the manifest itself so the pinned copy can re-pin ITSELF from
  // wherever it's served (the generator excludes it from its own listing).
  files.push(
    new File([JSON.stringify(paths)], MANIFEST_PATH.slice(1), {
      type: "application/json",
    }),
  );
  return files;
}

/**
 * Turn a <input type="file" webkitdirectory> selection into files whose names
 * are paths relative to the site root, so uploadDirectory reconstructs the
 * site at the CID root. The site root is located by finding the shallowest
 * `index.html` in the selection — this forgives picking a PARENT of out/
 * (e.g. the repo root), which would otherwise pin every file under a broken
 * `out/` prefix. Throws when the selection contains no index.html at all.
 */
export function filesFromFolderInput(list: FileList | null): File[] {
  if (!list || list.length === 0) return [];
  const entries = Array.from(list).map((f) => ({
    f,
    rel:
      (f as File & { webkitRelativePath?: string }).webkitRelativePath ||
      f.name,
  }));
  // Shallowest index.html marks the site root; strip everything above it.
  const roots = entries
    .filter(({ rel }) => rel === "index.html" || rel.endsWith("/index.html"))
    .map(({ rel }) => rel.slice(0, -"index.html".length))
    .sort((a, b) => a.length - b.length);
  if (roots.length === 0) {
    throw new Error(
      "That folder doesn't look like a site build (no index.html). Pick the out/ folder produced by `pnpm build:ipfs`.",
    );
  }
  const root = roots[0];
  return entries
    .filter(({ rel }) => rel.startsWith(root))
    .map(
      ({ f, rel }) => new File([f], rel.slice(root.length), { type: f.type }),
    );
}

/**
 * Pin a directory to IPFS via Pinata's REST API using a user-supplied (ideally
 * scoped) JWT. Returns the directory CID. Every file is placed under a common
 * root folder whose CID Pinata returns, so the site sits at the CID root —
 * `<cid>/app/index.html`, `<cid>/_next/…` — exactly where a gateway expects it.
 *
 * An independent alternative to Storacha's email flow (useful when Storacha's
 * upload endpoint is unreachable). The JWT stays in memory and is sent only to
 * api.pinata.cloud.
 */
export async function pinToPinata(
  files: File[],
  jwt: string,
  signal?: AbortSignal,
): Promise<string> {
  const form = new FormData();
  for (const f of files) form.append("file", f, `crowdstake/${f.name}`);
  form.append("pinataMetadata", JSON.stringify({ name: "crowdstake-app" }));
  // CIDv1 (base32) — required for <cid>.ipfs.<gateway> subdomain URLs; the
  // default v0 Qm… base58 CID is case-sensitive and can't be a DNS label.
  form.append("pinataOptions", JSON.stringify({ cidVersion: 1 }));
  const res = await fetch("https://api.pinata.cloud/pinning/pinFileToIPFS", {
    method: "POST",
    headers: { Authorization: `Bearer ${jwt.trim()}` },
    body: form,
    signal,
  });
  if (!res.ok) {
    const body = await res.text().catch(() => "");
    throw new Error(
      res.status === 401 || res.status === 403
        ? "Pinata rejected the key (needs the pinFileToIPFS permission)."
        : `Pinata error ${res.status}: ${body.slice(0, 200)}`,
    );
  }
  const json = (await res.json()) as { IpfsHash?: string };
  if (!json.IpfsHash) throw new Error("Pinata returned no CID.");
  return json.IpfsHash;
}

/** Default Kubo (go-ipfs) RPC API of a locally running node. */
export const LOCAL_IPFS_API = "http://127.0.0.1:5001";

/**
 * Pin a directory to a LOCAL IPFS node (Kubo / IPFS Desktop) via its RPC API —
 * the fully account-free path: no service, no key, no email. Your node hosts
 * the site and announces it to the network; public gateways fetch it from you.
 *
 * Uses /api/v0/add with cid-version=1 (subdomain gateways require CIDv1) and a
 * shared root folder; Kubo reports that folder's CID as the directory root.
 *
 * Requires the node to allow this origin on its RPC API (one-time):
 *   ipfs config --json API.HTTPHeaders.Access-Control-Allow-Origin '["*"]'
 *   ipfs config --json API.HTTPHeaders.Access-Control-Allow-Methods '["PUT","POST"]'
 * then restart the daemon.
 */
export async function pinToLocalNode(
  files: File[],
  apiUrl: string = LOCAL_IPFS_API,
  signal?: AbortSignal,
): Promise<string> {
  const base = apiUrl.replace(/\/+$/, "");
  const form = new FormData();
  for (const f of files) {
    // Kubo expects the multipart filename to be the URI-encoded relative path.
    form.append("file", f, encodeURIComponent(`crowdstake/${f.name}`));
  }
  const res = await fetch(
    `${base}/api/v0/add?recursive=true&pin=true&cid-version=1&progress=false`,
    { method: "POST", body: form, signal },
  );
  if (!res.ok) {
    const body = await res.text().catch(() => "");
    throw new Error(`IPFS node error ${res.status}: ${body.slice(0, 200)}`);
  }
  // NDJSON stream of {Name, Hash, ...}; the root folder's entry carries the CID.
  const text = await res.text();
  let root: string | null = null;
  for (const line of text.trim().split("\n")) {
    try {
      const entry = JSON.parse(line) as { Name?: string; Hash?: string };
      if (entry.Name === "crowdstake" && entry.Hash) root = entry.Hash;
    } catch {
      /* ignore non-JSON lines */
    }
  }
  if (!root) throw new Error("IPFS node returned no directory CID.");
  return root;
}

/** Gateway + ENS URLs for a freshly pinned directory CID. */
export function ipfsUrls(cid: string) {
  return {
    dweb: `https://${cid}.ipfs.dweb.link/app/`,
    w3s: `https://${cid}.ipfs.w3s.link/app/`,
    ipfsUri: `ipfs://${cid}`,
  };
}
