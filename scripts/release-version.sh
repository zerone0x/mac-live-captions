#!/usr/bin/env bash
# Checks that a release tag, project.yml and (optionally) a built app agree on
# the version, and prints the version (without the "v") on success.
#
#   scripts/release-version.sh <tag> [path/to/LiveCaptions.app]
#
# - <tag> must look like v<major>.<minor>.<patch> (for example v0.1.0).
# - project.yml must set MARKETING_VERSION exactly once, to the tag's version,
#   and CURRENT_PROJECT_VERSION exactly once, to a positive integer.
# - With an app: its CFBundleShortVersionString must equal the version and its
#   CFBundleVersion must equal CURRENT_PROJECT_VERSION (needs plutil, macOS).
#
# Every check fails closed: a missing or duplicated setting is an error, not a
# skip. scripts/release-selftest.sh checks that each rule fails.
# PROJECT_YML overrides the spec path (the self-test uses it).
set -euo pipefail

fail() { echo "release-version: $*" >&2; exit 1; }

tag="${1:?usage: release-version.sh <tag> [path/to/LiveCaptions.app]}"
app="${2:-}"
spec="${PROJECT_YML:-$(dirname "$0")/../project.yml}"

[[ -f "$spec" ]] || fail "missing $spec"

semver_re='^[0-9]+\.[0-9]+\.[0-9]+$'
[[ "$tag" == v* ]] || fail "tag '$tag' does not start with v"
version="${tag#v}"
[[ "$version" =~ $semver_re ]] || fail "tag '$tag' is not v<major>.<minor>.<patch>"

# One setting per key, value optionally quoted. Read into an array so that
# zero or two definitions fail instead of picking one.
setting() { # key
  local key="$1" line values=()
  while IFS= read -r line; do
    values+=("$line")
  done < <(sed -nE "s/^[[:space:]]+$key:[[:space:]]*\"?([^\"[:space:]#]*)\"?[[:space:]]*(#.*)?\$/\\1/p" "$spec")
  [[ ${#values[@]} -eq 1 ]] || fail "expected exactly one $key in $spec, found ${#values[@]}"
  [[ -n "${values[0]}" ]] || fail "$key in $spec is empty"
  printf '%s\n' "${values[0]}"
}

marketing="$(setting MARKETING_VERSION)"
build="$(setting CURRENT_PROJECT_VERSION)"

[[ "$marketing" =~ $semver_re ]] || fail "MARKETING_VERSION '$marketing' is not <major>.<minor>.<patch>"
[[ "$marketing" == "$version" ]] \
  || fail "tag $tag does not match MARKETING_VERSION $marketing in $spec (bump project.yml, or tag v$marketing)"
[[ "$build" =~ ^[1-9][0-9]*$ ]] || fail "CURRENT_PROJECT_VERSION '$build' is not a positive integer"

if [[ -n "$app" ]]; then
  plist="$app/Contents/Info.plist"
  [[ -f "$plist" ]] || fail "missing $plist"
  short="$(plutil -extract CFBundleShortVersionString raw "$plist")" \
    || fail "cannot read CFBundleShortVersionString from $plist"
  bundle="$(plutil -extract CFBundleVersion raw "$plist")" \
    || fail "cannot read CFBundleVersion from $plist"
  [[ "$short" == "$version" ]] || fail "built app has CFBundleShortVersionString '$short', expected $version"
  [[ "$bundle" == "$build" ]] || fail "built app has CFBundleVersion '$bundle', expected $build"
fi

echo "release-version: OK (tag $tag, version $version, build $build${app:+, app $app})" >&2
printf '%s\n' "$version"
