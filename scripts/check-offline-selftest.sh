#!/usr/bin/env bash
# Self-test for the offline checks: every fixture in a bad/ folder must fail its
# check, and good/ must pass, so a loosened pattern can't silently stop matching.
# Runs on Linux and macOS (no Xcode needed).
#
#   scripts/fixtures/offline/            check-offline.sh (one .swift file per case)
#   scripts/fixtures/dependencies/       check-dependencies.sh (one folder per case)
#   scripts/fixtures/linked-frameworks/  check-linked-frameworks.sh
#                                        (CASE.libs = `otool -L`, optional CASE.symbols = `nm -u`)
#
# The checks exit 1 for a finding and 2 for an internal error. A bad fixture
# must exit exactly 1, so a crash or parse error never counts as "caught";
# unreadable inputs must exit 2, never OK.
set -uo pipefail

cd "$(dirname "$0")/.."
status=0

# Package.resolved fixtures are stored as Package.resolved.fixture: GitHub's
# dependency graph parses a file named Package.resolved anywhere in the repo and
# raises Dependabot alerts for the old pins the bad fixtures contain. The
# self-test copies each fixture folder into a temp dir and strips the .fixture
# suffix before running the check. Any failure to copy or rename stops the run.
scratch="$(mktemp -d)" || {
  echo "selftest: cannot create a temp dir" >&2
  exit 2
}
cleanup() {
  chmod -R u+rwx "$scratch" ${tmp:+"$tmp"} 2>/dev/null
  rm -rf "$scratch" ${tmp:+"$tmp"}
}
trap cleanup EXIT

# materialize DIR: prints the path of a copy of DIR with *.fixture renamed.
materialize() {
  local src="$1" dst f
  dst="$(mktemp -d "$scratch/fx.XXXXXX")" || return 2
  cp -R "$src/." "$dst/" || return 2
  while IFS= read -r f; do
    mv "$f" "${f%.fixture}" || return 2
  done < <(find "$dst" -name '*.fixture' -type f) || return 2
  echo "$dst"
}

# Runs "$@" and checks its exit code is exactly $want.
expect_exit() {
  local want="$1" rc=0
  shift
  "$@" >/dev/null 2>&1 || rc=$?
  if [[ $rc -ne $want ]]; then
    echo "selftest: expected exit $want but got $rc: $*" >&2
    status=1
  fi
}

expect_fail() { expect_exit 1 "$@"; }
expect_error() { expect_exit 2 "$@"; }

expect_pass() {
  if ! "$@" >/dev/null 2>&1; then
    echo "selftest: expected pass but failed: $*" >&2
    "$@" >&2
    status=1
  fi
}

# The harness itself: expect_fail must not accept a crash (exit 2) or a pass,
# and expect_error must not accept a finding (exit 1).
exits() { return "$1"; }
harness_rejects() {
  if (status=0; "$@" 2>/dev/null; exit $status); then
    echo "selftest: harness accepted: $*" >&2
    status=1
  fi
}
harness_rejects expect_fail exits 2
harness_rejects expect_fail exits 0
harness_rejects expect_error exits 1

# Source scan.
fixtures=scripts/fixtures/offline
for f in "$fixtures"/bad/*.swift; do
  expect_fail scripts/check-offline.sh "$f"
done
expect_pass scripts/check-offline.sh "$fixtures/good"

# Remote dependencies.
fixtures=scripts/fixtures/dependencies
for d in "$fixtures"/bad/*/; do
  m="$(materialize "${d%/}")" || {
    echo "selftest: cannot materialize $d" >&2
    exit 2
  }
  expect_fail scripts/check-dependencies.sh "$m"
done
for d in "$fixtures"/good/*/; do
  m="$(materialize "${d%/}")" || {
    echo "selftest: cannot materialize $d" >&2
    exit 2
  }
  expect_pass scripts/check-dependencies.sh "$m"
done
# The renamed Package.resolved fixtures must really be exercised.
for d in bad/resolved bad/resolved-v1 good/local-packages; do
  m="$(materialize "$fixtures/$d")" || exit 2
  [[ -f "$m/Package.resolved" ]] || {
    echo "selftest: $d lost its Package.resolved" >&2
    exit 2
  }
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

# Internal errors: an unreadable file or directory must stop a check with
# exit 2 instead of reporting OK. Skipped as root, which can read anything.
tmp="$(mktemp -d)" || exit 2

mkdir -p "$tmp/offline" "$tmp/dep-file" "$tmp/dep-yaml" "$tmp/dep-dir/locked"
cp scripts/fixtures/offline/good/ok.swift "$tmp/offline/ok.swift"
echo 'let s = URLSession.shared' >"$tmp/offline/hidden.swift"
cp scripts/fixtures/dependencies/bad/package-url/Package.swift "$tmp/dep-file/Package.swift"
cp scripts/fixtures/dependencies/bad/xcodegen-url/project.yml "$tmp/dep-yaml/project.yml"
cp scripts/fixtures/dependencies/bad/package-url/Package.swift "$tmp/dep-dir/locked/Package.swift"
chmod 000 "$tmp/offline/hidden.swift" "$tmp/dep-file/Package.swift" "$tmp/dep-yaml/project.yml" "$tmp/dep-dir/locked"

if [[ -r "$tmp/offline/hidden.swift" ]]; then
  echo "selftest: running as root, skipping the unreadable-input cases" >&2
else
  expect_error scripts/check-offline.sh "$tmp/offline"
  expect_error scripts/check-dependencies.sh "$tmp/dep-file"
  expect_error scripts/check-dependencies.sh "$tmp/dep-yaml"
  # find cannot enter the directory.
  expect_error scripts/check-dependencies.sh "$tmp/dep-dir"
fi
expect_error scripts/check-offline.sh "$tmp/missing"
expect_error scripts/check-dependencies.sh "$tmp/missing"
expect_error scripts/check-linked-frameworks.sh --libs "$tmp/missing.libs"

# The real tree must pass the source checks too.
expect_pass scripts/check-offline.sh
expect_pass scripts/check-dependencies.sh

[[ $status -eq 0 ]] && echo "offline checks selftest: OK"
exit $status
