#!/usr/bin/env bash
# Build the root-served (IPFS) target and serve it locally so you can exercise
# the in-browser "Publish to IPFS" flow for real. Same server topology as an
# IPFS/ENS root (plain static server, empty base path), so self-pin works.
#
#   bash scripts/preview-ipfs.sh          # builds, then serves on :4185
#   PORT=8080 bash scripts/preview-ipfs.sh
#   SKIP_BUILD=1 bash scripts/preview-ipfs.sh   # reuse an existing out/
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$(cd "$HERE/.." && pwd)"
PORT="${PORT:-4185}"
PM="corepack pnpm@9.15.4"

command -v python3 >/dev/null || { echo "python3 is required to serve out/"; exit 1; }

if [ "${SKIP_BUILD:-0}" != "1" ]; then
  echo "▸ building the IPFS target (empty base path + ipfs-manifest.json)…"
  ( cd "$APP" && $PM build:ipfs ) || { echo "  build failed"; exit 1; }
fi
[ -f "$APP/out/ipfs-manifest.json" ] || { echo "  out/ipfs-manifest.json missing — run without SKIP_BUILD"; exit 1; }

WEB_PID=""
cleanup() { [ -n "$WEB_PID" ] && kill "$WEB_PID" 2>/dev/null; }
trap cleanup EXIT

( cd "$APP/out" && python3 -m http.server "$PORT" ) >/dev/null 2>&1 &
WEB_PID=$!
sleep 1

URL="http://localhost:${PORT}"
cat <<EOF

  ✓ Serving the IPFS build at ${URL}

  Test the IPFS publish flow:
    1. Open  ${URL}/app/publish/
    2. Leave "What to publish" on "This running app" (self-pin).
    3. Pin with "Pinata" (works today): paste a free API key scoped to
       pinFileToIPFS from https://app.pinata.cloud/developers/api-keys
       → Publish to IPFS.
    4. It uploads, then shows a CID + gateway URLs.
    5. Verify it: open  https://<CID>.ipfs.dweb.link/app/
       and a specific instance:  https://<CID>.ipfs.dweb.link/app/?i=<distributionManager>

  (Storacha is the other provider, but its upload endpoint up.storacha.network
   is currently unreachable in DNS — use Pinata until it's back.)

  Ctrl-C to stop.

EOF
wait "$WEB_PID"
