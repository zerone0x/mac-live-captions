#!/usr/bin/env bash
# Self-test for the release checks (scripts/release-version.sh and
# scripts/release-notes.sh): the good inputs pass and each bad input fails
# for the expected reason, so a loosened check cannot let a v0.2.0 tag ship
# a 0.1.0 app, or publish a Release with empty notes.
#
# The built-app cases need plutil and run on macOS (CI). On another OS they
# are skipped with a message; on macOS a missing plutil fails.
set -uo pipefail

cd "$(dirname "$0")/.."
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

# Release notes.
sum="$(printf 'a%.0s' $(seq 1 64))"
printf '%s  LiveCaptions-0.1.0.zip\n' "$sum" >"$work/good.sha256"
printf '%s  LiveCaptions-0.1.0.zip\n%s  other.zip\n' "$sum" "$sum" >"$work/two.sha256"
printf 'nothex  LiveCaptions-0.1.0.zip\n' >"$work/nothex.sha256"
printf '%s  LiveCaptions-0.2.0.zip\n' "$sum" >"$work/wrongname.sha256"

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

expect_pass notes-good "First release line." "$notes_sh" 0.1.0 "$work/good.sha256" "$work/CHANGELOG.md"
if out="$("$notes_sh" 0.1.0 "$work/good.sha256" "$work/CHANGELOG.md" 2>&1)"; then
  [[ "$out" == *"- A limitation."* ]] || { echo "selftest: notes lost a subsection: $out" >&2; status=1; }
  [[ "$out" != *"Newer things."* && "$out" != *"Older things."* ]] \
    || { echo "selftest: notes include another version: $out" >&2; status=1; }
  [[ "$out" == *"$sum"* ]] || { echo "selftest: notes lack the checksum: $out" >&2; status=1; }
  [[ "$out" != *"## [0.1.0]"* ]] || { echo "selftest: notes repeat the heading: $out" >&2; status=1; }
fi
expect_pass notes-last-section "Only section." "$notes_sh" 0.1.0 "$work/good.sha256" "$work/last.md"
if out="$("$notes_sh" 0.1.0 "$work/good.sha256" "$work/last.md" 2>&1)"; then
  [[ "$out" != *"example.invalid"* ]] || { echo "selftest: notes include link references: $out" >&2; status=1; }
fi
expect_fail notes-no-section "found 0" "$notes_sh" 0.3.0 "$work/good.sha256" "$work/CHANGELOG.md"
expect_fail notes-empty "is empty" "$notes_sh" 0.1.0 "$work/good.sha256" "$work/empty.md"
expect_fail notes-duplicate "found 2" "$notes_sh" 0.1.0 "$work/good.sha256" "$work/dup.md"
expect_fail notes-two-lines "exactly one line" "$notes_sh" 0.1.0 "$work/two.sha256" "$work/CHANGELOG.md"
expect_fail notes-not-hex "SHA-256 hash" "$notes_sh" 0.1.0 "$work/nothex.sha256" "$work/CHANGELOG.md"
expect_fail notes-wrong-zip "expected a zip for 0.1.0" "$notes_sh" 0.1.0 "$work/wrongname.sha256" "$work/CHANGELOG.md"
expect_fail notes-no-checksum "missing" "$notes_sh" 0.1.0 "$work/none.sha256" "$work/CHANGELOG.md"
expect_fail notes-no-changelog "missing" "$notes_sh" 0.1.0 "$work/good.sha256" "$work/none.md"

# The real CHANGELOG.md must have a section for the version in project.yml,
# so a version bump without release notes fails on the PR, not at tag time.
printf '%s  LiveCaptions-%s.zip\n' "$sum" "$real" >"$work/real.sha256"
expect_pass real-changelog "" "$notes_sh" "$real" "$work/real.sha256"

[[ $status -eq 0 ]] && echo "release selftest: OK"
exit $status
