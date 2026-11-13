#!/usr/bin/env bash
# Post-build half of the offline rule (docs/DECISIONS.md, 0003 and 0012):
# checks what the built binary actually links and calls, which a source grep
# cannot see (remote or binary dependencies, macros, generated code).
#
# 1. Every library in `otool -L` must be on the allow-list below. Network,
#    CFNetwork, WebKit and the Swift Network overlay are never allowed.
# 2. No undefined symbol from `nm -u` may name a networking API (sockets,
#    resolver, nw_*, CFNetwork streams, NSURLSession/NSURLConnection,
#    SFSpeechRecognizer, and dlsym, which would reach any of them by name).
#
# Speech is allowed: the app uses SpeechAnalyzer/SpeechTranscriber, and the
# en-US model download through AssetInventory is the one sanctioned,
# OS-managed network use.
#
# Usage:
#   check-linked-frameworks.sh path/to/LiveCaptions.app   (or a Mach-O binary; macOS)
#   check-linked-frameworks.sh --libs FILE [--symbols FILE]
#       checks saved `otool -L` / `nm -u` output (used by the self-test on Linux)
set -euo pipefail

usage() { echo "usage: check-linked-frameworks.sh APP|BINARY | --libs FILE [--symbols FILE]" >&2; exit 2; }

# Frameworks the app may link (system frameworks only). Carbon is here for
# the global shortcut's RegisterEventHotKey (DECISIONS 0015).
allowed_frameworks=(
  AppKit
  AudioToolbox
  AVFAudio
  AVFoundation
  Carbon
  Combine
  CoreAudio
  CoreFoundation
  CoreGraphics
  CoreImage
  CoreMedia
  CoreServices
  CoreText
  CoreVideo
  Foundation
  IOKit
  Observation
  QuartzCore
  ScreenCaptureKit
  Speech
  SwiftUI
  SwiftUICore
)

# Other libraries, as ERE on the install name.
allowed_dylibs=(
  '^/usr/lib/libSystem\.B\.dylib$'
  '^/usr/lib/libobjc\.A\.dylib$'
  '^/usr/lib/libc\+\+\.1\.dylib$'
  '^/usr/lib/swift/libswift[A-Za-z0-9_]+\.dylib$'
)

# Never allowed, even if an allow-list entry above would match.
denied_libs='/(Network|CFNetwork|WebKit|NetworkExtension|MultipeerConnectivity|CloudKit)\.framework/|libswift(Network|CFNetwork|WebKit|FoundationNetworking)\.dylib'

# Undefined symbols that mean the binary calls a networking API itself.
denied_symbols='^_(socket|connect|dlsym|getaddrinfo|gethostbyname2?|getnameinfo|res_query|nw_[a-z_]+|CFSocket[A-Za-z]*|CFStreamCreatePair[A-Za-z]*|CF(Read|Write)StreamCreateWithFTPURL|CFHTTP[A-Za-z]*|CFNetwork[A-Za-z]*|CFHost[A-Za-z]*)$|NSURLSession|NSURLConnection|NSURLDownload|SFSpeechRecognizer|SFSpeechURLRecognitionRequest|10Foundation10URLSession'

libs_file=""
symbols_file=""
tmp=""
cleanup() { [[ -n "$tmp" ]] && rm -rf "$tmp"; return 0; }
trap cleanup EXIT

if [[ "${1:-}" == "--libs" ]]; then
  libs_file="${2:-}"
  [[ -f "$libs_file" ]] || usage
  if [[ "${3:-}" == "--symbols" ]]; then
    symbols_file="${4:-}"
    [[ -f "$symbols_file" ]] || usage
  fi
else
  target="${1:-}"
  [[ -n "$target" ]] || usage
  if [[ -d "$target" ]]; then
    name="$(basename "$target" .app)"
    binary="$target/Contents/MacOS/$name"
  else
    binary="$target"
  fi
  [[ -f "$binary" ]] || { echo "check-linked-frameworks: missing binary: $binary" >&2; exit 2; }
  tmp="$(mktemp -d)"
  libs_file="$tmp/libs.txt"
  symbols_file="$tmp/symbols.txt"
  otool -L "$binary" >"$libs_file"
  nm -u "$binary" >"$symbols_file"
fi

status=0
fail() { echo "check-linked-frameworks: $*" >&2; status=1; }

lib_allowed() {
  local lib="$1" fw re
  if [[ "$lib" =~ ^/System/Library/Frameworks/([A-Za-z0-9_]+)\.framework/ ]]; then
    fw="${BASH_REMATCH[1]}"
    for re in "${allowed_frameworks[@]}"; do
      [[ "$fw" == "$re" ]] && return 0
    done
    return 1
  fi
  for re in "${allowed_dylibs[@]}"; do
    [[ "$lib" =~ $re ]] && return 0
  done
  return 1
}

count=0
while IFS= read -r line; do
  # otool prints "path:" and "path (architecture arm64):" headers; libraries are indented.
  [[ "$line" =~ ^[[:space:]]+([^[:space:]].*)[[:space:]]\(compatibility ]] || continue
  lib="${BASH_REMATCH[1]}"
  count=$((count + 1))
  echo "  $lib"
  if [[ "$lib" =~ $denied_libs ]]; then
    fail "links a networking library: $lib"
  elif ! lib_allowed "$lib"; then
    fail "links a library that is not on the allow-list: $lib"
  fi
done <"$libs_file"

[[ $count -gt 0 ]] || fail "no linked libraries found in otool output (wrong file?)"

if [[ -n "$symbols_file" ]]; then
  while IFS= read -r sym; do
    sym="${sym##* }"
    [[ -z "$sym" ]] && continue
    if [[ "$sym" =~ $denied_symbols ]]; then
      fail "calls a networking API: $sym"
    fi
  done <"$symbols_file"
fi

if [[ $status -ne 0 ]]; then
  echo "check-linked-frameworks: see above; update the allow-list only with a decision entry" >&2
  exit 1
fi

echo "check-linked-frameworks: OK ($count libraries)"
