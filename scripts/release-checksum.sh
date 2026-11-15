#!/usr/bin/env bash
# Checks a release checksum file and prints its SHA-256 hash.
#
#   scripts/release-checksum.sh <sha256-file> <expected file name>
#
# The file must be exactly one "<64 lowercase hex>  <name>" line (the format
# `shasum -a 256` writes and `shasum -c`/`sha256sum -c` read) and <name> must
# be exactly the expected release file name. When that file sits next to the
# checksum file, its hash must match too. Release names:
#   LiveCaptions-<version>.zip               (docs/DECISIONS.md 0023)
#   LiveCaptions-<version>-mac-arm64.dmg     (docs/DECISIONS.md 0026)
# scripts/release-selftest.sh checks that each rule fails.
set -euo pipefail

fail() { echo "release-checksum: $*" >&2; exit 1; }

checksum_file="${1:?usage: release-checksum.sh <sha256-file> <expected file name>}"
expected="${2:?usage: release-checksum.sh <sha256-file> <expected file name>}"

[[ -f "$checksum_file" ]] || fail "missing $checksum_file"
lines="$(wc -l <"$checksum_file" | tr -d ' ')"
[[ "$lines" -eq 1 ]] || fail "$checksum_file must have exactly one line, has $lines"
line="$(cat "$checksum_file")"
[[ "$line" =~ ^([0-9a-f]{64})\ \ (.+)$ ]] \
  || fail "$checksum_file is not '<SHA-256 hash>  <file name>': $line"
sum="${BASH_REMATCH[1]}"
name="${BASH_REMATCH[2]}"
[[ "$name" == "$expected" ]] || fail "$checksum_file names '$name', expected '$expected'"

artifact="$(dirname "$checksum_file")/$name"
if [[ -e "$artifact" ]]; then
  if command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "$artifact")" || fail "cannot hash $artifact"
  elif command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$artifact")" || fail "cannot hash $artifact"
  else
    fail "neither shasum nor sha256sum is installed"
  fi
  [[ "${actual%% *}" == "$sum" ]] || fail "$artifact does not match $checksum_file"
fi

printf '%s\n' "$sum"
