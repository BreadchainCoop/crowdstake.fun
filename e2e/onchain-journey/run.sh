#!/usr/bin/env bash
# One-command on-chain journey test.
#
# Brings up a local anvil fork of Gnosis (chain id 100 preserved), builds the
# static export pointed at that fork, serves it, then drives the REAL UI with a
# key-backed injected wallet and asserts every step on-chain. No real funds, no
# wallet prompts, and no key ever enters the app build.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$(cd "$HERE/../.." && pwd)"
RPC_PORT="${RPC_PORT:-8546}"
WEB_PORT="${WEB_PORT:-4173}"
FORK_RPC="${FORK_RPC_URL:-https://rpc.gnosischain.com}"

export TEST_RPC_URL="http://localhost:${RPC_PORT}"
export TEST_BASE_URL="http://localhost:${WEB_PORT}"
# Default signer = anvil dev account #0 — publicly known, auto-funded on the
# fork. NEVER use a real/funded key for the fork default.
export TEST_PRIVATE_KEY="${TEST_PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"

ANVIL_PID=""; WEB_PID=""
cleanup() { [ -n "$ANVIL_PID" ] && kill "$ANVIL_PID" 2>/dev/null; [ -n "$WEB_PID" ] && kill "$WEB_PID" 2>/dev/null; }
trap cleanup EXIT

echo "▸ anvil fork of Gnosis (chain 100) on :${RPC_PORT}"
anvil --fork-url "$FORK_RPC" --chain-id 100 --port "$RPC_PORT" --silent &
ANVIL_PID=$!
for _ in $(seq 1 30); do
  curl -s -m 3 -X POST "$TEST_RPC_URL" -H 'content-type: application/json' \
    -d '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}' 2>/dev/null | grep -q result && break
  sleep 1
done

echo "▸ deploying CrowdStakeDeployerV2 to the fork (enables democratic instances)"
( cd "$APP/contracts" && forge script script/DeployDeployerV2.s.sol \
    --rpc-url "$TEST_RPC_URL" --broadcast --private-key "$TEST_PRIVATE_KEY" ) \
  >/tmp/cs-v2-deploy.log 2>&1 \
  || { echo "  V2 deploy failed — see /tmp/cs-v2-deploy.log"; exit 1; }
export TEST_DEPLOYER_ADDRESS="$(python3 -c "import json;d=json.load(open('$APP/contracts/broadcast/DeployDeployerV2.s.sol/100/run-latest.json'));print([t['contractAddress'] for t in d['transactions'] if t.get('contractName')=='CrowdStakeDeployerV2'][0])")"
echo "  V2 deployer: ${TEST_DEPLOYER_ADDRESS}"

echo "▸ building static export pointed at the fork + V2 deployer"
( cd "$APP" && NEXT_PUBLIC_RPC_URL="$TEST_RPC_URL" \
    NEXT_PUBLIC_DEPLOYER_ADDRESS="$TEST_DEPLOYER_ADDRESS" \
    NEXT_PUBLIC_DEPLOYER_V2=true corepack pnpm@9.15.4 build ) \
  >/tmp/cs-journey-build.log 2>&1 \
  || { echo "  build failed — see /tmp/cs-journey-build.log"; exit 1; }

echo "▸ serving out/ on :${WEB_PORT}"
( cd "$APP/out" && python3 -m http.server "$WEB_PORT" ) >/dev/null 2>&1 &
WEB_PID=$!
sleep 2

echo "▸ running journey (admin path + full lifecycle)"
node "$HERE/journey.cjs"
CODE=$?

echo "▸ running democratic journey (recipient-voted registry)"
node "$HERE/journey-democratic.cjs" || CODE=1

echo ""
bash "$HERE/check-bundle.sh" "$APP/out" || CODE=1

exit $CODE
