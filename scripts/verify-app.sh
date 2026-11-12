#!/usr/bin/env bash
# Checks a built LiveCaptions.app: menu-bar only, usage strings present,
# arm64 binary, valid (ad-hoc) signature with the expected entitlements.
set -euo pipefail

app="${1:?usage: verify-app.sh path/to/LiveCaptions.app}"
plist="$app/Contents/Info.plist"
binary="$app/Contents/MacOS/LiveCaptions"

fail() { echo "verify-app: $*" >&2; exit 1; }

[[ -d "$app" ]] || fail "missing app bundle: $app"
[[ -x "$binary" ]] || fail "missing executable: $binary"

[[ "$(plutil -extract LSUIElement raw "$plist")" == "true" ]] || fail "LSUIElement is not true"
[[ "$(plutil -extract CFBundleIdentifier raw "$plist")" == "dev.trine.LiveCaptions" ]] || fail "unexpected bundle id"
[[ "$(plutil -extract LSMinimumSystemVersion raw "$plist")" == 26.* ]] || fail "minimum macOS is not 26"

for key in NSAudioCaptureUsageDescription NSMicrophoneUsageDescription NSSpeechRecognitionUsageDescription; do
  value="$(plutil -extract "$key" raw "$plist" 2>/dev/null || true)"
  [[ -n "$value" ]] || fail "missing usage string $key"
done

archs="$(lipo -archs "$binary")"
[[ "$archs" == "arm64" ]] || fail "expected arm64 only, got: $archs"

codesign --verify --deep --strict "$app" || fail "signature does not verify"
codesign -d --entitlements - "$app" 2>/dev/null | grep -q "com.apple.security.device.audio-input" \
  || fail "audio-input entitlement missing from signature"

echo "verify-app: OK ($app, $archs)"
