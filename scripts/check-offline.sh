#!/usr/bin/env bash
# The caption path must stay on device (docs/DECISIONS.md, 0003 and 0012).
# Fails if package or App sources use networking APIs, a server-capable
# recognizer, remote URLs, raw sockets or child processes. If a future feature
# really needs the network, it gets its own module and a decision entry, not an
# exception here.
#
# Sanctioned exception: the en-US speech model is downloaded by the system
# through `AssetInventory` (Speech framework). That traffic is OS-managed, so
# `AssetInventory`, `SpeechAnalyzer` and `SpeechTranscriber` are allowed.
#
# Whole-line `//` comments are ignored, so docs can name a banned API or link a
# source. Trailing comments on code lines are still scanned.
#
# Remote package dependencies are checked by scripts/check-dependencies.sh, and
# the frameworks the built binary links by scripts/check-linked-frameworks.sh.
#
# Deliberate evasion (a URL or API name built by concatenation or string
# interpolation) is out of reach of a grep; reviews still matter.
#
# Usage: check-offline.sh [PATH...]   (default: all package and App sources)
# Exit: 0 clean, 1 networking API found, 2 internal error (bad path, unreadable
# file); an error never counts as OK.
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ $# -gt 0 ]]; then
  paths=("$@")
else
  paths=(Packages/*/Sources App/Sources)
fi

for p in "${paths[@]}"; do
  [[ -e "$p" ]] || { echo "check-offline: no such path: $p" >&2; exit 2; }
done

# Portable ERE (works with BSD grep on macOS and GNU grep, no \b).
nonword='(^|[^A-Za-z0-9_])'
wordend='([^A-Za-z0-9_]|$)'
attrs='(@[A-Za-z_]+(\([^)]*\))?[[:space:]]+)*'
kind='((typealias|struct|class|enum|protocol|func|var|let)[[:space:]]+)?'
modules='Network|NetworkExtension|FoundationNetworking|CFNetwork|WebKit|MultipeerConnectivity|CloudKit'

rules=(
  # Foundation URL loading (URLSession, NSURLSession, NSURLConnection, ...).
  'URLSession|URLRequest|URLConnection|URLDownload|WebSocket'
  # Network framework: Swift types and the nw_* C API.
  "${nonword}NW[A-Z]"
  "${nonword}nw_[a-z]"
  # CFNetwork and CF streams/sockets.
  'CFNetwork|CFSocket|CFHTTP|CFFTP|CFHost|CFNetService|CFStreamCreatePair|CF(Read|Write)StreamCreateWithFTPURL|getStreamsToHost'
  "${nonword}(NS)?NetService"
  # Networking modules, in any import form.
  "^[[:space:]]*${attrs}import[[:space:]]+${kind}(${modules})([^A-Za-z0-9_]|\$)"
  # SFSpeechRecognizer can fall back to Apple's servers; the app uses
  # SpeechAnalyzer/SpeechTranscriber only (DECISIONS 0003).
  "${nonword}SFSpeech"
  # Remote URL string literals, any case (also catches Data(contentsOf: URL(string: "https://...")).
  # Other schemes such as x-apple.systempreferences: and file: stay allowed.
  '"([Hh][Tt][Tt][Pp][Ss]?|[Ww][Ss][Ss]?|[Ff][Tt][Pp])://'
  # BSD sockets and resolver.
  "${nonword}(socket|getaddrinfo|gethostbyname2?|getnameinfo|res_query)[[:space:]]*\\("
  "${nonword}(AF_INET6?|SOCK_STREAM|SOCK_DGRAM|sockaddr_in6?)${wordend}"
  # Child processes (curl and friends) and dynamic loading (bypasses the linked-frameworks check).
  "${nonword}(Process|NSTask)[[:space:]]*\\("
  "${nonword}Process\\.(run|launchedProcess)"
  'posix_spawn|NSUserUnixTask|NSAppleScript|dlopen'
)

pattern="$(IFS='|'; echo "${rules[*]}")"

error() { echo "check-offline: error: $*" >&2; exit 2; }

# grep exits 1 for "no match" and 2 for an error (unreadable file, bad
# pattern); only 0 and 1 are results.
rc=0
matches="$(grep -RHInE "$pattern" --include='*.swift' "${paths[@]}")" || rc=$?
[[ $rc -le 1 ]] || error "grep failed (exit $rc); the scan is incomplete"

hits=""
if [[ -n "$matches" ]]; then
  rc=0
  hits="$(printf '%s\n' "$matches" | grep -vE '^[^:]*:[0-9]+:[[:space:]]*//')" || rc=$?
  [[ $rc -le 1 ]] || error "comment filter failed (exit $rc)"
fi

if [[ -n "$hits" ]]; then
  echo "$hits"
  echo "check-offline: networking API found in the caption path (see above)" >&2
  exit 1
fi

echo "check-offline: OK"
