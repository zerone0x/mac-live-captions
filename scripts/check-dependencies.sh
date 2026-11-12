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

# Drops whole-line comments (`//` in Swift, `#` in YAML).
code_lines() { grep -nvE '^[[:space:]]*(//|#)' "$1" || true; }

allowed() {
  local line="$1" url
  for url in ${allowed_remote[@]+"${allowed_remote[@]}"}; do
    [[ "$line" == *"$url"* ]] && return 0
  done
  return 1
}

check_lines() {
  local file="$1" pattern="$2" what="$3" line
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    allowed "$line" && continue
    report "$file:$line"
    echo "check-dependencies: $what in $file" >&2
  done < <(code_lines "$file" | grep -E "$pattern" || true)
}

# Lines of the top-level `packages:` section of an XcodeGen spec, numbered.
yaml_packages() {
  awk '
    /^[^[:space:]#]/ { in_packages = ($0 ~ /^packages:/) ; next }
    in_packages && $0 !~ /^[[:space:]]*#/ { print NR ":" $0 }
  ' "$1"
}

for root in "${roots[@]}"; do
  [[ -e "$root" ]] || { echo "check-dependencies: no such path: $root" >&2; exit 2; }
  while IFS= read -r file; do
    case "$(basename "$file")" in
      Package.swift)
        # .package(url:), .package(id:) (registry) and .binaryTarget(url:).
        check_lines "$file" '(^|[^A-Za-z0-9_])(url|id)[[:space:]]*:' "remote package or binary target"
        ;;
      Package.resolved)
        # Local packages are never pinned, so any pin is a remote package.
        check_lines "$file" '"(location|repositoryURL)"[[:space:]]*:' "pinned remote package"
        ;;
      project.yml | project.yaml)
        while IFS= read -r line; do
          [[ -z "$line" ]] && continue
          allowed "$line" && continue
          report "$file:$line"
          echo "check-dependencies: remote package in $file" >&2
        done < <(yaml_packages "$file" | grep -E '[[:space:]{,](url|github)[[:space:]]*:' || true)
        ;;
      Podfile | Podfile.lock | Cartfile | Cartfile.resolved)
        report "$file"
        echo "check-dependencies: $(basename "$file") is not allowed" >&2
        ;;
    esac
  done < <(
    # The default scan skips build output and this script's own fixtures.
    if [[ "$root" == "." ]]; then
      find . \( -path ./.git -o -path ./build -o -path ./scripts/fixtures -o -name .build -o -name DerivedData \) -prune \
        -o -type f \( -name Package.swift -o -name Package.resolved -o -name project.yml -o -name project.yaml \
        -o -name 'Podfile*' -o -name 'Cartfile*' \) -print
    else
      find "$root" \( -name .build -o -name DerivedData \) -prune \
        -o -type f \( -name Package.swift -o -name Package.resolved -o -name project.yml -o -name project.yaml \
        -o -name 'Podfile*' -o -name 'Cartfile*' \) -print
    fi | sort
  )
done

if [[ $status -ne 0 ]]; then
  echo "check-dependencies: remote dependency found (see above)" >&2
  exit 1
fi

echo "check-dependencies: OK"
