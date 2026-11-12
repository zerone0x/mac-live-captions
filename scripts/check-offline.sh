#!/usr/bin/env bash
# The caption path must stay on device (docs/DECISIONS.md, 0003).
# Fails if package or App sources use networking APIs. If a future feature really
# needs the network, it gets its own module and a decision entry, not an
# exception here.
set -euo pipefail

cd "$(dirname "$0")/.."

# Portable ERE (works with BSD grep on macOS and GNU grep).
pattern='URLSession|URLRequest|NWConnection|NWPathMonitor|WebSocket|^[[:space:]]*import[[:space:]]+(Network|FoundationNetworking)'

if grep -RInE "$pattern" --include='*.swift' Packages/*/Sources App/Sources; then
  echo "check-offline: networking API found in the caption path (see above)" >&2
  exit 1
fi

echo "check-offline: OK"
