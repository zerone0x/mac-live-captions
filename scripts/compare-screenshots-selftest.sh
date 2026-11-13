#!/usr/bin/env bash
# Self-test for scripts/compare-screenshots.swift: identical images pass, a
# different image of the same size fails with a diff PNG, a missing image
# fails, and an unreadable reference directory is an error.
#
# Synthetic images (scripts/png-fixtures.py) pin the rest (#38): a different
# size and an unreadable reference, and both thresholds from each side, so
# loosening or tightening them fails here: 10 of 10 000 pixels (0.1 %) may
# differ, 11 may not; a channel may be off by 8 of 255, not by 9; alpha
# counts.
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

pairs=0
# expect_pair <exit> <label> <reference image> <actual image>: compare one
# reference (named shot.png) with one actual image.
expect_pair() {
  local want="$1" label="$2" reference="$3" actual="$4"
  pairs=$((pairs + 1))
  local case_dir="$work/pair-$pairs"
  mkdir -p "$case_dir/ref" "$case_dir/actual"
  cp "$reference" "$case_dir/ref/shot.png"
  cp "$actual" "$case_dir/actual/shot.png"
  expect "$want" "$label" "$case_dir/ref" "$case_dir/actual"
}

synthetic="$work/synthetic"
python3 "$root/scripts/png-fixtures.py" compare "$synthetic"
s="$synthetic"
expect_pair 1 "different size is a mismatch" "$s/grey.png" "$s/grey-101.png"
if ! grep -q '^SIZE' "$work/out.txt"; then
  echo "FAIL different size: not reported as SIZE" >&2
  cat "$work/out.txt" >&2
  exit 1
fi
echo "ok   different size reported as SIZE"
expect_pair 0 "10 of 10000 pixels changed (0.1 %) passes" "$s/grey.png" "$s/grey-10-px.png"
expect_pair 1 "11 of 10000 pixels changed is a mismatch" "$s/grey.png" "$s/grey-11-px.png"
expect_pair 0 "one channel off by 8 of 255 passes" "$s/grey.png" "$s/grey-green-8.png"
expect_pair 1 "one channel off by 9 of 255 is a mismatch" "$s/grey.png" "$s/grey-green-9.png"
expect_pair 1 "alpha-only change is a mismatch" "$s/black.png" "$s/black-alpha.png"

# A reference that is not a PNG is an error, not a mismatch.
mkdir -p "$work/badref"
echo "not a png" >"$work/badref/shot.png"
mkdir -p "$work/badref-actual"
cp "$s/grey.png" "$work/badref-actual/shot.png"
expect 2 "unreadable reference is an error" "$work/badref" "$work/badref-actual"
echo "compare-screenshots self-test passed"
