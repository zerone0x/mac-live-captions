#!/usr/bin/env bash
# Self-test for the offline checks: every fixture in a bad/ folder must fail its
# check, and good/ must pass, so a loosened pattern can't silently stop matching.
# Runs on Linux and macOS (no Xcode needed).
#
#   scripts/fixtures/offline/            check-offline.sh (one .swift file per case)
#   scripts/fixtures/dependencies/       check-dependencies.sh (one folder per case)
#   scripts/fixtures/linked-frameworks/  check-linked-frameworks.sh
#                                        (CASE.libs = `otool -L`, optional CASE.symbols = `nm -u`)
set -uo pipefail

cd "$(dirname "$0")/.."
status=0

expect_fail() {
  if "$@" >/dev/null 2>&1; then
    echo "selftest: expected failure but passed: ${*: -1}" >&2
    status=1
  fi
}

expect_pass() {
  if ! "$@" >/dev/null 2>&1; then
    echo "selftest: expected pass but failed: $*" >&2
    "$@" >&2
    status=1
  fi
}

# Source scan.
fixtures=scripts/fixtures/offline
for f in "$fixtures"/bad/*.swift; do
  expect_fail scripts/check-offline.sh "$f"
done
expect_pass scripts/check-offline.sh "$fixtures/good"

# Remote dependencies.
fixtures=scripts/fixtures/dependencies
for d in "$fixtures"/bad/*/; do
  expect_fail scripts/check-dependencies.sh "${d%/}"
done
for d in "$fixtures"/good/*/; do
  expect_pass scripts/check-dependencies.sh "${d%/}"
done

# Linked frameworks and imported symbols of the built binary.
linked_args() {
  local libs="$1" symbols="${1%.libs}.symbols"
  if [[ -f "$symbols" ]]; then
    echo "--libs $libs --symbols $symbols"
  else
    echo "--libs $libs"
  fi
}
fixtures=scripts/fixtures/linked-frameworks
for f in "$fixtures"/bad/*.libs; do
  # shellcheck disable=SC2046 # fixture paths have no spaces
  expect_fail scripts/check-linked-frameworks.sh $(linked_args "$f")
done
for f in "$fixtures"/good/*.libs; do
  # shellcheck disable=SC2046
  expect_pass scripts/check-linked-frameworks.sh $(linked_args "$f")
done

# The real tree must pass the source checks too.
expect_pass scripts/check-offline.sh
expect_pass scripts/check-dependencies.sh

[[ $status -eq 0 ]] && echo "offline checks selftest: OK"
exit $status
