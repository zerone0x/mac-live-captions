#!/usr/bin/env bash
# Prints the GitHub Release notes for a version: its CHANGELOG.md section
# (without the heading), then install and checksum lines.
#
#   scripts/release-notes.sh <version> <sha256-file> [CHANGELOG.md]
#
# Fails if the changelog has no "## [<version>]" section, has it twice, or
# the section is empty, or if the checksum file is not one
# "<64 hex>  <file name>" line. scripts/release-selftest.sh checks each rule.
set -euo pipefail

fail() { echo "release-notes: $*" >&2; exit 1; }

version="${1:?usage: release-notes.sh <version> <sha256-file> [CHANGELOG.md]}"
checksum_file="${2:?usage: release-notes.sh <version> <sha256-file> [CHANGELOG.md]}"
changelog="${3:-$(dirname "$0")/../CHANGELOG.md}"

[[ -f "$changelog" ]] || fail "missing $changelog"
[[ -f "$checksum_file" ]] || fail "missing $checksum_file"

heading="## [$version]"
count="$(awk -v h="$heading" 'index($0, h) == 1 { n++ } END { print n + 0 }' "$changelog")"
[[ "$count" -eq 1 ]] || fail "expected exactly one '$heading' section in $changelog, found $count"

# The section runs to the next "## " heading or link-reference block.
section="$(awk -v h="$heading" '
  index($0, h) == 1 { on = 1; next }
  on && /^## / { exit }
  on && /^\[[^]]+\]: / { exit }
  on { print }
' "$changelog")"
# Trim leading and trailing blank lines.
section="$(printf '%s\n' "$section" | sed -e '/./,$!d' | sed -e ':a' -e '/^[[:space:]]*$/{$d;N;ba' -e '}')"
[[ -n "${section//[[:space:]]/}" ]] || fail "section '$heading' in $changelog is empty"

lines="$(wc -l <"$checksum_file" | tr -d ' ')"
[[ "$lines" -eq 1 ]] || fail "$checksum_file must have exactly one line, has $lines"
read -r sum name <"$checksum_file" || fail "cannot read $checksum_file"
[[ "$sum" =~ ^[0-9a-f]{64}$ ]] || fail "$checksum_file does not start with a SHA-256 hash"
[[ -n "${name:-}" ]] || fail "$checksum_file has no file name"
[[ "$name" == *"$version"*.zip ]] || fail "$checksum_file names '$name', expected a zip for $version"

cat <<EOF
$section

## Install

Download \`$name\` and \`$name.sha256\`, check the zip and unzip it:

\`\`\`sh
shasum -a 256 -c $name.sha256
ditto -x -k $name .
mv LiveCaptions.app /Applications/
xattr -dr com.apple.quarantine /Applications/LiveCaptions.app
open /Applications/LiveCaptions.app
\`\`\`

The build is ad-hoc signed and not notarized, which is why the \`xattr\` step is
needed. First-run permissions, the speech model download and how to report a
problem: [README, Install](https://github.com/zerone0x/mac-live-captions/blob/v$version/README.md#install).

SHA-256 (\`$name\`): \`$sum\`
EOF
