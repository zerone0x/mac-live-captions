#!/usr/bin/env bash
# Self-test for the release checks (scripts/release-version.sh,
# scripts/release-checksum.sh and scripts/release-notes.sh): the good inputs
# pass and each bad input fails for the expected reason, so a loosened check
# cannot let a v0.2.0 tag ship a 0.1.0 app, publish a Release with empty
# notes, or attach a DMG or zip under the wrong name or checksum.
#
# The built-app cases need plutil and run on macOS (CI). On another OS they
# are skipped with a message; on macOS a missing plutil fails.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
version_sh="$PWD/scripts/release-version.sh"
notes_sh="$PWD/scripts/release-notes.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
status=0

expect_pass() { # case name, expected stdout, command...
  local name="$1" want="$2" out
  shift 2
  if ! out="$("$@" 2>"$work/stderr")"; then
    echo "selftest: $name: expected pass, got: $(cat "$work/stderr")" >&2
    status=1
  elif [[ -n "$want" && "$out" != *"$want"* ]]; then
    echo "selftest: $name: output does not contain '$want': $out" >&2
    status=1
  fi
}

expect_fail() { # case name, expected message substring, command...
  local name="$1" want="$2" out
  shift 2
  if out="$("$@" 2>&1)"; then
    echo "selftest: $name: expected failure but passed: $out" >&2
    status=1
  elif [[ "$out" != *"$want"* ]]; then
    echo "selftest: $name: failed for the wrong reason: $out" >&2
    status=1
  fi
}

spec() { # file name, MARKETING_VERSION line(s), CURRENT_PROJECT_VERSION line(s)
  local file="$work/$1.yml"
  {
    echo 'name: LiveCaptions'
    echo 'settings:'
    echo '  base:'
    printf '%s\n' "$2"
    printf '%s\n' "$3"
  } >"$file"
  echo "$file"
}

good="$(spec good '    MARKETING_VERSION: "0.1.0"' '    CURRENT_PROJECT_VERSION: "2"')"
unquoted="$(spec unquoted '    MARKETING_VERSION: 0.1.0 # comment' '    CURRENT_PROJECT_VERSION: 2')"
twice="$(spec twice $'    MARKETING_VERSION: "0.1.0"\n    MARKETING_VERSION: "0.2.0"' '    CURRENT_PROJECT_VERSION: "2"')"
missing="$(spec missing '' '    CURRENT_PROJECT_VERSION: "2"')"
badbuild="$(spec badbuild '    MARKETING_VERSION: "0.1.0"' '    CURRENT_PROJECT_VERSION: "0"')"
nobuild="$(spec nobuild '    MARKETING_VERSION: "0.1.0"' '')"
shortver="$(spec shortver '    MARKETING_VERSION: "0.1"' '    CURRENT_PROJECT_VERSION: "2"')"

# The real project.yml must parse (whatever its version is).
real="$(sed -nE 's/^[[:space:]]+MARKETING_VERSION:[[:space:]]*"?([0-9.]+)"?.*$/\1/p' project.yml)"
expect_pass real-project "$real" "$version_sh" "v$real"

expect_pass good "0.1.0" env PROJECT_YML="$good" "$version_sh" v0.1.0
expect_pass unquoted "0.1.0" env PROJECT_YML="$unquoted" "$version_sh" v0.1.0
expect_fail mismatch "does not match MARKETING_VERSION 0.1.0" env PROJECT_YML="$good" "$version_sh" v0.2.0
expect_fail no-v "does not start with v" env PROJECT_YML="$good" "$version_sh" 0.1.0
expect_fail prerelease "is not v<major>.<minor>.<patch>" env PROJECT_YML="$good" "$version_sh" v0.1.0-rc1
expect_fail two-parts "is not v<major>.<minor>.<patch>" env PROJECT_YML="$good" "$version_sh" v0.1
expect_fail empty-tag "usage" env PROJECT_YML="$good" "$version_sh" ""
expect_fail twice "expected exactly one MARKETING_VERSION" env PROJECT_YML="$twice" "$version_sh" v0.1.0
expect_fail missing "expected exactly one MARKETING_VERSION" env PROJECT_YML="$missing" "$version_sh" v0.1.0
expect_fail bad-build "is not a positive integer" env PROJECT_YML="$badbuild" "$version_sh" v0.1.0
expect_fail no-build "expected exactly one CURRENT_PROJECT_VERSION" env PROJECT_YML="$nobuild" "$version_sh" v0.1.0
expect_fail short-marketing "MARKETING_VERSION '0.1' is not" env PROJECT_YML="$shortver" "$version_sh" v0.1.0
expect_fail no-spec "missing" env PROJECT_YML="$work/nope.yml" "$version_sh" v0.1.0

# Built-app cases: CFBundleShortVersionString and CFBundleVersion.
fake_app() { # name, short version, bundle version
  local app="$work/$1/LiveCaptions.app"
  mkdir -p "$app/Contents"
  cat >"$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleShortVersionString</key><string>$2</string>
<key>CFBundleVersion</key><string>$3</string>
</dict></plist>
EOF
  echo "$app"
}
if command -v plutil >/dev/null 2>&1; then
  expect_pass app-good "0.1.0" env PROJECT_YML="$good" "$version_sh" v0.1.0 "$(fake_app good 0.1.0 2)"
  expect_fail app-old-version "CFBundleShortVersionString '0.0.1', expected 0.1.0" \
    env PROJECT_YML="$good" "$version_sh" v0.1.0 "$(fake_app old 0.0.1 2)"
  expect_fail app-build "CFBundleVersion '1', expected 2" \
    env PROJECT_YML="$good" "$version_sh" v0.1.0 "$(fake_app build 0.1.0 1)"
  expect_fail app-missing "missing" env PROJECT_YML="$good" "$version_sh" v0.1.0 "$work/none/LiveCaptions.app"
elif [[ "$(uname -s)" == Darwin ]]; then
  echo "selftest: plutil is missing on macOS" >&2
  status=1
else
  echo "selftest: skipping built-app cases (no plutil on $(uname -s))"
fi

# Checksum files (scripts/release-checksum.sh): one "<hash>  <name>" line
# with exactly the release name, and the hash of the file when it is there.
zip="LiveCaptions-0.1.0.zip"
dmg="LiveCaptions-0.1.0-mac-arm64.dmg"
sum="$(printf 'a%.0s' $(seq 1 64))"
dsum="$(printf 'd%.0s' $(seq 1 64))"
checksum() { # file name, content
  printf '%s\n' "$2" >"$work/$1"
  echo "$work/$1"
}
good_zip="$(checksum good.zip.sha256 "$sum  $zip")"
good_dmg="$(checksum good.dmg.sha256 "$dsum  $dmg")"
two="$(checksum two.sha256 "$sum  $zip"$'\n'"$sum  other.zip")"
nothex="$(checksum nothex.sha256 "nothex  $zip")"
upper="$(checksum upper.sha256 "$(tr a-f A-F <<<"$dsum")  $dmg")"
one_space="$(checksum one-space.sha256 "$dsum $dmg")"
wrong_zip="$(checksum wrong-zip.sha256 "$sum  LiveCaptions-0.2.0.zip")"
dmg_old="$(checksum dmg-old.sha256 "$dsum  LiveCaptions-0.2.0-mac-arm64.dmg")"
dmg_x64="$(checksum dmg-x64.sha256 "$dsum  LiveCaptions-0.1.0-mac-x64.dmg")"
dmg_noarch="$(checksum dmg-noarch.sha256 "$dsum  LiveCaptions-0.1.0.dmg")"
dmg_path="$(checksum dmg-path.sha256 "$dsum  dist/$dmg")"
checksum_sh="$PWD/scripts/release-checksum.sh"

expect_pass checksum-dmg "$dsum" "$checksum_sh" "$good_dmg" "$dmg"
expect_pass checksum-zip "$sum" "$checksum_sh" "$good_zip" "$zip"
expect_fail checksum-dmg-as-zip "expected '$zip'" "$checksum_sh" "$good_dmg" "$zip"
expect_fail checksum-dmg-version "expected '$dmg'" "$checksum_sh" "$dmg_old" "$dmg"
expect_fail checksum-dmg-arch "expected '$dmg'" "$checksum_sh" "$dmg_x64" "$dmg"
expect_fail checksum-dmg-no-arch "expected '$dmg'" "$checksum_sh" "$dmg_noarch" "$dmg"
expect_fail checksum-dmg-path "expected '$dmg'" "$checksum_sh" "$dmg_path" "$dmg"
expect_fail checksum-uppercase "is not '<SHA-256 hash>  <file name>'" "$checksum_sh" "$upper" "$dmg"
expect_fail checksum-one-space "is not '<SHA-256 hash>  <file name>'" "$checksum_sh" "$one_space" "$dmg"
expect_fail checksum-two-lines "exactly one line" "$checksum_sh" "$two" "$zip"
expect_fail checksum-missing "missing" "$checksum_sh" "$work/none.sha256" "$dmg"
expect_fail checksum-no-name "usage" "$checksum_sh" "$good_dmg" ""

# With the DMG next to its checksum file, the hash must be the DMG's.
mkdir "$work/dist"
printf 'not really a disk image\n' >"$work/dist/$dmg"
if command -v shasum >/dev/null 2>&1; then
  real_dsum="$(shasum -a 256 "$work/dist/$dmg")"
else
  real_dsum="$(sha256sum "$work/dist/$dmg")"
fi
real_dsum="${real_dsum%% *}"
printf '%s  %s\n' "$real_dsum" "$dmg" >"$work/dist/$dmg.sha256"
expect_pass checksum-file-matches "$real_dsum" "$checksum_sh" "$work/dist/$dmg.sha256" "$dmg"
printf 'tampered\n' >>"$work/dist/$dmg"
expect_fail checksum-file-tampered "does not match" "$checksum_sh" "$work/dist/$dmg.sha256" "$dmg"

# Release notes.

cat >"$work/CHANGELOG.md" <<'EOF'
# Changelog

## [0.2.0]

Newer things.

## [0.1.0]

First release line.

### Known limitations

- A limitation.

## [0.0.9]

Older things.
EOF
cat >"$work/empty.md" <<'EOF'
# Changelog

## [0.1.0]


## [0.0.9]

Older.
EOF
cat >"$work/dup.md" <<'EOF'
## [0.1.0]

One.

## [0.1.0]

Two.
EOF
cat >"$work/last.md" <<'EOF'
## [0.1.0]

Only section.

[0.1.0]: https://example.invalid/v0.1.0
EOF

notes() { "$notes_sh" "$@"; }
expect_pass notes-good "First release line." notes 0.1.0 "$good_zip" "$good_dmg" "$work/CHANGELOG.md"
if out="$(notes 0.1.0 "$good_zip" "$good_dmg" "$work/CHANGELOG.md" 2>&1)"; then
  [[ "$out" == *"- A limitation."* ]] || { echo "selftest: notes lost a subsection: $out" >&2; status=1; }
  [[ "$out" != *"Newer things."* && "$out" != *"Older things."* ]] \
    || { echo "selftest: notes include another version: $out" >&2; status=1; }
  [[ "$out" == *"SHA-256 (\`$zip\`): \`$sum\`"* ]] || { echo "selftest: notes lack the zip checksum: $out" >&2; status=1; }
  [[ "$out" == *"SHA-256 (\`$dmg\`): \`$dsum\`"* ]] || { echo "selftest: notes lack the DMG checksum: $out" >&2; status=1; }
  [[ "$out" == *"open $dmg"* ]] || { echo "selftest: notes lack the DMG install step: $out" >&2; status=1; }
  # The one-line installer comes first, pinned to this version.
  oneliner="scripts/install.sh | bash -s -- 0.1.0"
  [[ "$out" == *"$oneliner"* ]] || { echo "selftest: notes lack the one-line installer: $out" >&2; status=1; }
  [[ "${out%%"$oneliner"*}" != *"open $dmg"* ]] \
    || { echo "selftest: notes do not lead with the one-line installer: $out" >&2; status=1; }
  [[ "$out" != *"## [0.1.0]"* ]] || { echo "selftest: notes repeat the heading: $out" >&2; status=1; }
  [[ "$out" == *"xattr -dr com.apple.quarantine"* ]] \
    || { echo "selftest: ad-hoc notes lack the legacy install step" >&2; status=1; }
fi
if out="$(RELEASE_SIGNED=1 notes 0.1.0 "$good_zip" "$good_dmg" "$work/CHANGELOG.md")"; then
  [[ "$out" == *"Developer ID signed and notarized by Apple"* && "$out" != *"quarantine"* ]] \
    || { echo "selftest: notarized notes contain incorrect installation steps" >&2; status=1; }
else
  status=1
fi
expect_pass notes-last-section "Only section." notes 0.1.0 "$good_zip" "$good_dmg" "$work/last.md"
if out="$(notes 0.1.0 "$good_zip" "$good_dmg" "$work/last.md" 2>&1)"; then
  [[ "$out" != *"example.invalid"* ]] || { echo "selftest: notes include link references: $out" >&2; status=1; }
fi
expect_fail notes-no-section "found 0" notes 0.3.0 "$good_zip" "$good_dmg" "$work/CHANGELOG.md"
expect_fail notes-empty "is empty" notes 0.1.0 "$good_zip" "$good_dmg" "$work/empty.md"
expect_fail notes-duplicate "found 2" notes 0.1.0 "$good_zip" "$good_dmg" "$work/dup.md"
expect_fail notes-two-lines "exactly one line" notes 0.1.0 "$two" "$good_dmg" "$work/CHANGELOG.md"
expect_fail notes-not-hex "SHA-256 hash" notes 0.1.0 "$nothex" "$good_dmg" "$work/CHANGELOG.md"
expect_fail notes-wrong-zip "expected '$zip'" notes 0.1.0 "$wrong_zip" "$good_dmg" "$work/CHANGELOG.md"
expect_fail notes-swapped "expected '$zip'" notes 0.1.0 "$good_dmg" "$good_zip" "$work/CHANGELOG.md"
expect_fail notes-dmg-x64 "expected '$dmg'" notes 0.1.0 "$good_zip" "$dmg_x64" "$work/CHANGELOG.md"
expect_fail notes-dmg-version "expected '$dmg'" notes 0.1.0 "$good_zip" "$dmg_old" "$work/CHANGELOG.md"
expect_fail notes-no-checksum "missing" notes 0.1.0 "$work/none.sha256" "$good_dmg" "$work/CHANGELOG.md"
expect_fail notes-no-dmg-checksum "missing" notes 0.1.0 "$good_zip" "$work/none.sha256" "$work/CHANGELOG.md"
expect_fail notes-no-changelog "missing" notes 0.1.0 "$good_zip" "$good_dmg" "$work/none.md"
expect_fail notes-only-zip "usage" notes 0.1.0 "$good_zip"

# The real CHANGELOG.md must have a section for the version in project.yml,
# so a version bump without release notes fails on the PR, not at tag time.
printf '%s  LiveCaptions-%s.zip\n' "$sum" "$real" >"$work/real.zip.sha256"
printf '%s  LiveCaptions-%s-mac-arm64.dmg\n' "$dsum" "$real" >"$work/real.dmg.sha256"
expect_pass real-changelog "" notes "$real" "$work/real.zip.sha256" "$work/real.dmg.sha256"

[[ $status -eq 0 ]] && echo "release selftest: OK"
exit $status
