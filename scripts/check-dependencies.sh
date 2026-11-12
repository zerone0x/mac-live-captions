#!/usr/bin/env bash
# Remote dependencies would ship their own networking code past the source scan
# (docs/DECISIONS.md, 0012). Fails if a package manifest or the XcodeGen spec
# declares a remote package, if a Package.resolved pins one, or if CocoaPods or
# Carthage is set up. Local `path:` packages are fine.
#
# Allow-list: put a remote package URL in `allowed_remote` below, with a
# decision entry that says why. It is empty on purpose.
#
# Usage: check-dependencies.sh [ROOT...]   (default: the repository root)
# Exit: 0 clean, 1 remote dependency found, 2 internal error (bad path,
# unreadable file or directory); an error never counts as OK.
set -euo pipefail

cd "$(dirname "$0")/.."

allowed_remote=()

if [[ $# -gt 0 ]]; then
  roots=("$@")
else
  roots=(.)
fi

status=0
report() { echo "$1"; status=1; }
error() { echo "check-dependencies: error: $*" >&2; exit 2; }

# grep, but only "no match" (exit 1) is tolerated; an error returns 2.
grep_ok() {
  local rc=0
  grep "$@" || rc=$?
  [[ $rc -le 1 ]] || return 2
}

# Drops whole-line comments (`//` in Swift, `#` in YAML).
code_lines() { grep_ok -nvE '^[[:space:]]*(//|#)' "$1"; }

allowed() {
  local line="$1" url
  for url in ${allowed_remote[@]+"${allowed_remote[@]}"}; do
    [[ "$line" == *"$url"* ]] && return 0
  done
  return 1
}

# Reports each numbered line in $3 (from $1) that is not allow-listed.
report_lines() {
  local file="$1" what="$2" lines="$3" line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    allowed "$line" && continue
    report "$file:$line"
    echo "check-dependencies: $what in $file" >&2
  done <<<"$lines"
}

# Runs in the main shell so `error` stops the whole check.
check_lines() {
  local file="$1" pattern="$2" what="$3" lines hits
  lines="$(code_lines "$file")" || error "cannot read $file"
  hits="$(printf '%s\n' "$lines" | grep_ok -E "$pattern")" || error "grep failed on $file"
  report_lines "$file" "$what" "$hits"
}

# Lines of the top-level `packages:` section of an XcodeGen spec, numbered.
yaml_packages() {
  awk '
    /^[^[:space:]#]/ { in_packages = ($0 ~ /^packages:/) ; next }
    in_packages && $0 !~ /^[[:space:]]*#/ { print NR ":" $0 }
  ' "$1"
}

# `url:`/`github:` keys in the `packages:` section, bare or quoted.
yaml_remote="[[:space:]{,][\"']?(url|github)[\"']?[[:space:]]*:"

check_yaml() {
  local file="$1" lines hits
  lines="$(yaml_packages "$1")" || error "cannot read $file"
  hits="$(printf '%s\n' "$lines" | grep_ok -E "$yaml_remote")" || error "grep failed on $file"
  report_lines "$file" "remote package" "$hits"
}

# Manifest files under a root. The default scan (root ".") skips build output
# and the fixtures of this check. Fails if find fails (unreadable directory).
candidates() {
  local prune
  if [[ "$1" == "." ]]; then
    prune=(-path ./.git -o -path ./build -o -path ./scripts/fixtures -o -name .build -o -name DerivedData)
  else
    prune=(-name .build -o -name DerivedData)
  fi
  find "$1" \( "${prune[@]}" \) -prune -o -type f \( -name Package.swift -o -name 'Package@swift-*.swift' -o -name Package.resolved \
    -o -name project.yml -o -name project.yaml -o -name 'Podfile*' -o -name 'Cartfile*' \) -print | sort
}

for root in "${roots[@]}"; do
  [[ -e "$root" ]] || { echo "check-dependencies: no such path: $root" >&2; exit 2; }
  files="$(candidates "$root")" || error "find failed under $root; the scan is incomplete"
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    case "$(basename "$file")" in
      Package.swift | Package@swift-*.swift)
        # .package(url:), .package(id:) (registry) and .binaryTarget(url:).
        check_lines "$file" '(^|[^A-Za-z0-9_])(url|id)[[:space:]]*:' "remote package or binary target"
        ;;
      Package.resolved)
        # Local packages are never pinned, so any pin is a remote package.
        check_lines "$file" '"(location|repositoryURL)"[[:space:]]*:' "pinned remote package"
        ;;
      project.yml | project.yaml)
        check_yaml "$file"
        ;;
      Podfile | Podfile.lock | Cartfile | Cartfile.resolved)
        report "$file"
        echo "check-dependencies: $(basename "$file") is not allowed" >&2
        ;;
    esac
  done <<<"$files"
done

if [[ $status -ne 0 ]]; then
  echo "check-dependencies: remote dependency found (see above)" >&2
  exit 1
fi

echo "check-dependencies: OK"
