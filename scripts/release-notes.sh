#!/usr/bin/env bash
# Prints the GitHub Release notes for a version: its CHANGELOG.md section
# (without the heading), then install steps and the artifact checksums.
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

open_app='open /Applications/LiveCaptions.app'
installer_finish='clears the quarantine flag and opens the app'
signature_note='The build is ad-hoc signed and not notarized, which is why the quarantine step is needed (the installer does it for you).'
if [[ "${RELEASE_SIGNED:-0}" == 1 ]]; then
  installer_finish='opens the app'
  signature_note='The app and DMG are Developer ID signed and notarized by Apple.'
else
  open_app=$'xattr -dr com.apple.quarantine /Applications/LiveCaptions.app\n'"$open_app"
fi

print_terminal_install() {
  cat <<EOF
### Install from Terminal

\`\`\`sh
curl -fsSL https://raw.githubusercontent.com/zerone0x/mac-live-captions/main/scripts/install.sh | bash -s -- $version
\`\`\`

It downloads \`$zip\`, checks it against \`$zip.sha256\`, quits a
running LiveCaptions, replaces /Applications/LiveCaptions.app (the old app
stays if anything fails), $installer_finish. No
sudo. Leave out \`-s -- $version\` to get the latest release. The same
script is attached to this release as \`install.sh\`.
EOF
}

print_dmg_install() {
  cat <<EOF
### Install from the DMG

Download \`$dmg\` and \`$dmg.sha256\`, check the DMG and open it:

\`\`\`sh
shasum -a 256 -c $dmg.sha256
open $dmg
\`\`\`

Drag LiveCaptions to Applications in the window that opens, then run:

\`\`\`sh
$open_app
\`\`\`
EOF
}

printf '%s\n\n' "$section"
printf '%s\n\n' '## Install' 'Requires Apple Silicon and macOS 26 or later.'

if [[ "${RELEASE_SIGNED:-0}" == 1 ]]; then
  print_dmg_install
  printf '\n'
  print_terminal_install
else
  print_terminal_install
  printf '\n'
  print_dmg_install
fi

cat <<EOF

### Install from the ZIP

Download \`$zip\` and \`$zip.sha256\`:

\`\`\`sh
shasum -a 256 -c $zip.sha256
ditto -x -k $zip .
mv LiveCaptions.app /Applications/
$open_app
\`\`\`

$signature_note
First-run permissions, the speech model download and how to report a
problem: [README, Install](https://github.com/zerone0x/mac-live-captions/blob/v$version/README.md#install).

SHA-256 (\`$dmg\`): \`$dmg_sum\`

SHA-256 (\`$zip\`): \`$zip_sum\`
EOF
