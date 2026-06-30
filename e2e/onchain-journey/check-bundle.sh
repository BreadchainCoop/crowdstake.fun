#!/usr/bin/env bash
# Security gate: fail if the signing key leaked into the shipped static bundle.
# The key lives only in this test process — it must never reach out/.
OUT="${1:-../../out}"
KEY="${TEST_PRIVATE_KEY:-}"
FAIL=0

if [ -n "$KEY" ]; then
  STRIPPED="${KEY#0x}"
  if grep -rIq -- "$STRIPPED" "$OUT" 2>/dev/null; then
    echo "▸ bundle safety check"
    echo "  ✗ FAIL: TEST_PRIVATE_KEY found in the built bundle ($OUT)"
    FAIL=1
  fi
fi

if [ "$FAIL" -eq 0 ]; then
  echo "▸ bundle safety check"
  echo "  ✓ no signing key in the shipped bundle ($OUT)"
fi
exit "$FAIL"
