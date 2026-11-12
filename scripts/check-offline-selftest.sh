#!/usr/bin/env bash
# Self-test for check-offline.sh: every fixture in bad/ must fail the check,
# and good/ must pass, so a loosened pattern can't silently stop matching.
set -uo pipefail

cd "$(dirname "$0")/.."
fixtures=scripts/fixtures/offline
status=0

for f in "$fixtures"/bad/*.swift; do
  if scripts/check-offline.sh "$f" >/dev/null 2>&1; then
    echo "selftest: expected failure but passed: $f" >&2
    status=1
  fi
done

if ! scripts/check-offline.sh "$fixtures/good" >/dev/null 2>&1; then
  echo "selftest: good fixtures were rejected" >&2
  status=1
fi

[[ $status -eq 0 ]] && echo "check-offline selftest: OK"
exit $status
