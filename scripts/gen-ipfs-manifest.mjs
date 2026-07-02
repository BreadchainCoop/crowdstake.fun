// Lists every file in out/ so the deployed app can fetch and re-pin itself to
// IPFS from the browser (self-pin). Run after `next build` in the IPFS target.
import { readdirSync, statSync, writeFileSync } from "node:fs";
import { join, relative, sep } from "node:path";

const OUT = "out";
const NAME = "ipfs-manifest.json";

function walk(dir, acc = []) {
  for (const entry of readdirSync(dir)) {
    const p = join(dir, entry);
    if (statSync(p).isDirectory()) walk(p, acc);
    else acc.push(p);
  }
  return acc;
}

try {
  const files = walk(OUT)
    .map((p) => relative(OUT, p).split(sep).join("/"))
    .filter((p) => p !== NAME)
    .sort();
  writeFileSync(join(OUT, NAME), JSON.stringify(files));
  console.log(`✓ ${NAME}: ${files.length} files`);
} catch (e) {
  console.error(`Could not write ${NAME}:`, e.message);
  process.exit(1);
}
