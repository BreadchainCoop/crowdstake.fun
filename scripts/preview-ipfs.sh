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
    3. Enter your email → Publish to IPFS.
    4. Click the Storacha link in your inbox (pick the FREE plan if prompted).
    5. It uploads, then shows a CID + gateway URLs.
    6. Verify it: open  https://<CID>.ipfs.dweb.link/app/
       and a specific instance:  https://<CID>.ipfs.dweb.link/app/?i=<distributionManager>

  (First run needs a free Storacha account — the email step creates it.
   No account? Sign up at https://console.storacha.network first.)

  Ctrl-C to stop.

EOF
wait "$WEB_PID"
