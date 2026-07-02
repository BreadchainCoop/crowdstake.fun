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

/** Gateway + ENS URLs for a freshly pinned directory CID. */
export function ipfsUrls(cid: string) {
  return {
    dweb: `https://${cid}.ipfs.dweb.link/app/`,
    w3s: `https://${cid}.ipfs.w3s.link/app/`,
    ipfsUri: `ipfs://${cid}`,
  };
}
