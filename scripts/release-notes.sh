#!/usr/bin/env bash
# Prints the GitHub Release notes for a version: its CHANGELOG.md section
# (without the heading), then install steps and the checksums of the DMG and
# the zip.
#
#   scripts/release-notes.sh <version> <zip.sha256> <dmg.sha256> [CHANGELOG.md]
#
# Fails if the changelog has no "## [<version>]" section, has it twice, or
# the section is empty, or if a checksum file is not one
# "<64 hex>  <file name>" line naming LiveCaptions-<version>.zip or
# LiveCaptions-<version>-mac-arm64.dmg (scripts/release-checksum.sh).
# scripts/release-selftest.sh checks each rule.
set -euo pipefail

fail() { echo "release-notes: $*" >&2; exit 1; }

usage="usage: release-notes.sh <version> <zip.sha256> <dmg.sha256> [CHANGELOG.md]"
version="${1:?$usage}"
zip_checksum="${2:?$usage}"
dmg_checksum="${3:?$usage}"
changelog="${4:-$(dirname "$0")/../CHANGELOG.md}"
checksum_sh="$(dirname "$0")/release-checksum.sh"

[[ -f "$changelog" ]] || fail "missing $changelog"

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

zip="LiveCaptions-$version.zip"
dmg="LiveCaptions-$version-mac-arm64.dmg"
zip_sum="$("$checksum_sh" "$zip_checksum" "$zip")" || fail "bad zip checksum file $zip_checksum"
dmg_sum="$("$checksum_sh" "$dmg_checksum" "$dmg")" || fail "bad DMG checksum file $dmg_checksum"

cat <<EOF
$section

## Install

Download \`$dmg\` and \`$dmg.sha256\`, check the DMG and open it:

\`\`\`sh
shasum -a 256 -c $dmg.sha256
open $dmg
\`\`\`

Drag LiveCaptions to Applications in the window that opens, then clear the
quarantine flag and open the app:

\`\`\`sh
xattr -dr com.apple.quarantine /Applications/LiveCaptions.app
open /Applications/LiveCaptions.app
\`\`\`

Or use the zip (\`$zip\` and \`$zip.sha256\`) instead of the DMG:

\`\`\`sh
shasum -a 256 -c $zip.sha256
ditto -x -k $zip .
mv LiveCaptions.app /Applications/
xattr -dr com.apple.quarantine /Applications/LiveCaptions.app
open /Applications/LiveCaptions.app
\`\`\`

The build is ad-hoc signed and not notarized, which is why the \`xattr\` step is
needed. First-run permissions, the speech model download and how to report a
problem: [README, Install](https://github.com/zerone0x/mac-live-captions/blob/v$version/README.md#install).

SHA-256 (\`$dmg\`): \`$dmg_sum\`

SHA-256 (\`$zip\`): \`$zip_sum\`
EOF
