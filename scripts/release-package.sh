#!/usr/bin/env bash
# Zips a verified Release build for a GitHub Release and writes its SHA-256
# checksum file, then unzips the zip again and re-verifies what a user gets.
#
#   scripts/release-package.sh <version> path/to/LiveCaptions.app <out-dir>
#
# Writes <out-dir>/LiveCaptions-<version>.zip and
# <out-dir>/LiveCaptions-<version>.zip.sha256 ("<hash>  <file name>", the
# format `shasum -a 256 -c` and `sha256sum -c` read). macOS only (ditto,
# shasum, codesign). Fails if anything is off, including an existing zip.
set -euo pipefail

fail() { echo "release-package: $*" >&2; exit 1; }

version="${1:?usage: release-package.sh <version> path/to/LiveCaptions.app <out-dir>}"
app="${2:?usage: release-package.sh <version> path/to/LiveCaptions.app <out-dir>}"
out="${3:?usage: release-package.sh <version> path/to/LiveCaptions.app <out-dir>}"
scripts="$(cd "$(dirname "$0")" && pwd)"

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version '$version' is not <major>.<minor>.<patch>"
[[ -d "$app" ]] || fail "missing app bundle: $app"
[[ "$(basename "$app")" == "LiveCaptions.app" ]] || fail "expected LiveCaptions.app, got $(basename "$app")"

name="LiveCaptions-$version.zip"
mkdir -p "$out"
[[ ! -e "$out/$name" ]] || fail "$out/$name already exists"
[[ ! -e "$out/$name.sha256" ]] || fail "$out/$name.sha256 already exists"

# Same flags as `make package`: keeps symlinks, resource forks and the
# signature intact, with LiveCaptions.app as the top-level entry.
ditto -c -k --sequesterRsrc --keepParent "$app" "$out/$name"
(cd "$out" && shasum -a 256 "$name" >"$name.sha256")
(cd "$out" && shasum -a 256 -c "$name.sha256") || fail "checksum does not verify"

# Check what a user unzips, not only what we zipped.
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
ditto -x -k "$out/$name" "$work"
entries="$(cd "$work" && ls -A)"
[[ "$entries" == "LiveCaptions.app" ]] || fail "zip must contain only LiveCaptions.app, has: $entries"
"$scripts/verify-app.sh" "$work/LiveCaptions.app" || fail "unzipped app does not verify"
"$scripts/check-linked-frameworks.sh" "$work/LiveCaptions.app" || fail "unzipped app links unexpected frameworks"
PROJECT_YML="$scripts/../project.yml" "$scripts/release-version.sh" "v$version" "$work/LiveCaptions.app" >/dev/null \
  || fail "unzipped app has the wrong version"

echo "release-package: OK $out/$name ($(cut -d' ' -f1 <"$out/$name.sha256"))"
