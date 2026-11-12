#!/usr/bin/env bash
# The caption path must stay on device (docs/DECISIONS.md, 0003).
# Fails if Core or App sources use networking APIs. If a future feature really
# needs the network, it gets its own module and a decision entry, not an
# exception here.
#
# Usage: check-offline.sh [PATH...]   (default: Core and App sources)
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ $# -gt 0 ]]; then
  paths=("$@")
else
  paths=(Packages/Core/Sources App/Sources)
fi

# Portable ERE (works with BSD grep on macOS and GNU grep, no \b).
nonword='(^|[^A-Za-z0-9_])'
attrs='(@[A-Za-z_]+(\([^)]*\))?[[:space:]]+)*'
kind='((typealias|struct|class|enum|protocol|func|var|let)[[:space:]]+)?'
imports="^[[:space:]]*${attrs}import[[:space:]]+${kind}(Network|FoundationNetworking)([^A-Za-z0-9_]|\$)"
pattern="URLSession|URLRequest|WebSocket|${nonword}NW[A-Z]|${imports}"

if grep -RInE "$pattern" --include='*.swift' "${paths[@]}"; then
  echo "check-offline: networking API found in the caption path (see above)" >&2
  exit 1
fi

echo "check-offline: OK"
