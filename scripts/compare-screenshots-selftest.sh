#!/usr/bin/env bash
# Self-test for scripts/compare-screenshots.swift: identical images pass, a
# different image of the same size fails with a diff PNG, a missing image
# fails, and an unreadable reference directory is an error.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
compare="$root/scripts/compare-screenshots.swift"
refs="$root/scripts/fixtures/screenshots"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/ref" "$work/same" "$work/changed" "$work/missing"
cp "$refs/overlay-notch-1-final-line.png" "$refs/overlay-notch-2-final-plus-volatile.png" "$work/ref/"
cp "$work/ref/"*.png "$work/same/"
cp "$work/ref/"*.png "$work/changed/"
# Same size, other caption text.
cp "$refs/overlay-notch-2-final-plus-volatile.png" "$work/changed/overlay-notch-1-final-line.png"
cp "$work/ref/overlay-notch-1-final-line.png" "$work/missing/"

expect() {
  local want="$1" label="$2"
  shift 2
  local rc=0
  swift "$compare" "$@" >"$work/out.txt" 2>&1 || rc=$?
  if [[ "$rc" -ne "$want" ]]; then
    echo "FAIL $label: exit $rc, expected $want" >&2
    cat "$work/out.txt" >&2
    exit 1
  fi
  echo "ok   $label (exit $rc)"
}

expect 0 "identical images match" "$work/ref" "$work/same"
expect 1 "changed caption is a mismatch" "$work/ref" "$work/changed"
if [[ ! -s "$work/changed/overlay-notch-1-final-line.diff.png" ]]; then
  echo "FAIL changed caption: no diff PNG written" >&2
  exit 1
fi
echo "ok   diff PNG written"
expect 1 "missing image is a mismatch" "$work/ref" "$work/missing"
expect 2 "missing reference directory is an error" "$work/nope" "$work/same"
echo "compare-screenshots self-test passed"
