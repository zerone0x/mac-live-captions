#!/usr/bin/env bash
# Checks a built (Release) LiveCaptions.app: menu-bar only, usage strings
# present, arm64 binary, valid (ad-hoc) signature with hardened runtime and
# exactly the expected entitlements (no get-task-allow), stripped binary, and
# the compiled app icon (docs/DECISIONS.md 0025).
# Debug builds fail on purpose: they keep get-task-allow and debug symbols.
# scripts/verify-app-selftest.sh checks that each rule actually fails.
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

# App icon (docs/DECISIONS.md 0025): actool compiles the AppIcon set into
# Assets.car and AppIcon.icns and names both in Info.plist. Without them
# Finder, the Dock and System Settings show the blank placeholder icon.
icon_name="$(plutil -extract CFBundleIconName raw "$plist" 2>/dev/null || true)"
[[ "$icon_name" == "AppIcon" ]] || fail "CFBundleIconName is not AppIcon (got: '$icon_name')"
icon_file="$(plutil -extract CFBundleIconFile raw "$plist" 2>/dev/null || true)"
[[ "$icon_file" == "AppIcon" || "$icon_file" == "AppIcon.icns" ]] \
  || fail "CFBundleIconFile is not AppIcon (got: '$icon_file')"
icns="$app/Contents/Resources/AppIcon.icns"
[[ -s "$icns" ]] || fail "missing app icon: $icns"
[[ "$(head -c 4 "$icns")" == "icns" ]] || fail "AppIcon.icns is not an icns file"
[[ -s "$app/Contents/Resources/Assets.car" ]] || fail "missing compiled asset catalog: Contents/Resources/Assets.car"

archs="$(lipo -archs "$binary")"
[[ "$archs" == "arm64" ]] || fail "expected arm64 only, got: $archs"

codesign --verify --deep --strict "$app" || fail "signature does not verify"

# Tool output is captured first and then searched, never piped into
# `grep -q`: grep exits at the first match, the producer dies of SIGPIPE and
# with pipefail the pipeline reports failure, so a match would read as "no
# match" (and a failing tool would read as "clean").

# Hardened runtime must be on: "CodeDirectory ... flags=0x10000(runtime)".
signature="$(codesign -d --verbose=2 "$app" 2>&1)" || fail "cannot read signature details"
grep -Eq '^CodeDirectory .*flags=0x[0-9a-f]+\([^)]*runtime' <<<"$signature" \
  || fail "hardened runtime is not enabled in the signature"

# The signed entitlements must be exactly the expected set. In particular
# com.apple.security.get-task-allow (injected when Xcode signs "to run
# locally") lets any same-user process attach a debugger and read memory, and
# notarization rejects it (docs/DECISIONS.md 0004).
expected_entitlements='{"com.apple.security.device.audio-input":true}'
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
codesign -d --entitlements - --xml "$app" >"$tmpdir/entitlements.plist" 2>/dev/null \
  || fail "cannot read entitlements from signature"
[[ -s "$tmpdir/entitlements.plist" ]] || fail "signature carries no entitlements"
entitlements="$(plutil -convert json -o - "$tmpdir/entitlements.plist")" \
  || fail "entitlements are not a valid plist"
echo "verify-app: signed entitlements: $entitlements"
if [[ "$entitlements" == *"get-task-allow"* ]]; then
  fail "signature carries com.apple.security.get-task-allow (debuggable build; Release needs CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO)"
fi
[[ "$entitlements" == "$expected_entitlements" ]] \
  || fail "unexpected entitlements: $entitlements (expected $expected_entitlements)"

# The shipped binary must be stripped: no debug map (N_OSO/N_SO stabs) that
# points at build-machine object files such as /Users/runner/work/....
symbols="$(nm -a "$binary")" || fail "cannot list symbols of $binary"
stab_re=' (OSO|SO) '
if [[ "$symbols" =~ $stab_re ]]; then
  fail "binary is not stripped (debug map with build paths present)"
fi
text="$(strings -a "$binary")" || fail "cannot list strings of $binary"
if [[ "$text" == *"/Users/runner/"* ]]; then
  fail "binary contains /Users/runner/ build paths"
fi

echo "verify-app: OK ($app, $archs, hardened runtime, no get-task-allow, stripped, app icon)"
