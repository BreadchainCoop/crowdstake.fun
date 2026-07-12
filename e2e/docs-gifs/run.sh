#!/usr/bin/env bash
# One-command /docs GIF re-record: fork + canonical deployer + fork-pointed
# static build + capture + downscale + encode + copy into public/docs/.
# Mirrors ../onchain-journey/run.sh's stack bring-up so the clips always show
# the CURRENT UI executing REAL (fork) transactions.
#
#   npm run record            # all flows
#   FLOWS=deploy npm run record
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$(cd "$HERE/../.." && pwd)"
RPC_PORT="${RPC_PORT:-8546}"
WEB_PORT="${WEB_PORT:-4173}"
FORK_RPC="${FORK_RPC_URL:-https://rpc.gnosischain.com}"

export TEST_RPC_URL="http://localhost:${RPC_PORT}"
export TEST_BASE_URL="http://localhost:${WEB_PORT}"
# anvil dev account #0 — publicly known, auto-funded on the fork. NEVER a real key.
export TEST_PRIVATE_KEY="${TEST_PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"

ANVIL_PID=""; WEB_PID=""
cleanup() { [ -n "$ANVIL_PID" ] && kill "$ANVIL_PID" 2>/dev/null; [ -n "$WEB_PID" ] && kill "$WEB_PID" 2>/dev/null; }
trap cleanup EXIT

echo "▸ anvil fork of Gnosis (chain 100) on :${RPC_PORT}"
anvil --fork-url "$FORK_RPC" --chain-id 100 --port "$RPC_PORT" --silent &
ANVIL_PID=$!
ANVIL_UP=""
for _ in $(seq 1 30); do
  if curl -s -m 3 -X POST "$TEST_RPC_URL" -H 'content-type: application/json' \
    -d '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}' 2>/dev/null | grep -q result; then
    ANVIL_UP=1; break
  fi
  # anvil exits outright when the upstream flakes at genesis — fail fast with
  # a useful message instead of letting later steps retry against a corpse.
  kill -0 "$ANVIL_PID" 2>/dev/null || break
  sleep 1
done
[ -n "$ANVIL_UP" ] || { echo "  anvil never came up (fork upstream flaky?) — try another FORK_RPC_URL"; exit 1; }

echo "▸ deploying the canonical CrowdStakeDeployer to the fork"
# Public fork upstreams (429s, transient 500s) regularly flake exactly here —
# retry a few times before giving up.
DEPLOY_OK=""
for attempt in 1 2 3; do
  if ( cd "$APP/contracts" && PRIVATE_KEY="$TEST_PRIVATE_KEY" forge script script/DeployCrowdStakeDeployer.s.sol \
      --rpc-url "$TEST_RPC_URL" --broadcast ) >/tmp/cs-gifs-deployer.log 2>&1; then
    DEPLOY_OK=1; break
  fi
  echo "  attempt ${attempt} failed (flaky fork upstream?) — retrying in 20s"
  sleep 20
done
[ -n "$DEPLOY_OK" ] || { echo "  deployer deploy failed — see /tmp/cs-gifs-deployer.log"; exit 1; }
export TEST_DEPLOYER_ADDRESS="$(python3 -c "import json;d=json.load(open('$APP/contracts/broadcast/DeployCrowdStakeDeployer.s.sol/100/run-latest.json'));print([t['contractAddress'] for t in d['transactions'] if t.get('contractName')=='CrowdStakeDeployer'][0])")"
echo "  canonical deployer: ${TEST_DEPLOYER_ADDRESS}"

echo "▸ building static export pointed at the fork"
( cd "$APP" && NEXT_PUBLIC_RPC_URL="$TEST_RPC_URL" \
    NEXT_PUBLIC_DEPLOYER_ADDRESS="$TEST_DEPLOYER_ADDRESS" \
    corepack pnpm@9.15.4 build ) \
  >/tmp/cs-gifs-build.log 2>&1 \
  || { echo "  build failed — see /tmp/cs-gifs-build.log"; exit 1; }

echo "▸ serving out/ on :${WEB_PORT}"
( cd "$APP/out" && python3 -m http.server "$WEB_PORT" ) >/dev/null 2>&1 &
WEB_PID=$!
sleep 2

# True when the flow is selected this run (no FLOWS = everything). Every later
# stage filters through this so a FLOWS-subset re-record can never mix stale
# frames/gifs from a previous generation into public/docs.
in_flows() { [ -z "${FLOWS:-}" ] || case ",${FLOWS}," in *",$1,"*) return 0;; *) return 1;; esac; }

# Full runs regenerate everything from scratch.
if [ -z "${FLOWS:-}" ]; then rm -rf "$HERE/frames" "$HERE/scaled" "$HERE/out"; fi

echo "▸ capturing frames"
node "$HERE/capture.cjs" "${FLOWS:-}" || exit 1

echo "▸ downscaling to 900px wide (sips)"
rm -rf "$HERE/scaled"
for d in "$HERE"/frames/*/; do
  flow="$(basename "$d")"
  in_flows "$flow" || continue
  mkdir -p "$HERE/scaled/$flow"
  cp "$d"*.png "$HERE/scaled/$flow/"
  sips -Z 900 "$HERE/scaled/$flow"/*.png >/dev/null 2>&1 \
    || echo "  sips unavailable — encoding at full size"
done

echo "▸ encoding GIFs (gifenc)"
( cd "$HERE" && node encode.cjs "${FLOWS:-}" ) || exit 1

echo "▸ installing into public/docs/"
for g in "$HERE"/out/*.gif; do
  flow="$(basename "$g" .gif)"
  in_flows "$flow" || continue
  cp "$g" "$APP/public/docs/$flow.gif"
  echo "  public/docs/$flow.gif ($(du -h "$g" | cut -f1 | tr -d ' '))"
done
echo "done — review with: git diff --stat public/docs"
