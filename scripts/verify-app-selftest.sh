#!/usr/bin/env bash
# Self-test for verify-app.sh (macOS only: needs clang, codesign, plutil).
# Builds a tiny fake LiveCaptions.app, signs it ad-hoc in several ways and
# checks that only the release-shaped bundle passes and that every bad bundle
# fails for the expected reason, so a loosened check can't silently pass a
# debuggable (get-task-allow) or unstripped build.
set -uo pipefail

cd "$(dirname "$0")/.."
verify="$PWD/scripts/verify-app.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
status=0

cat >"$work/main.c" <<'EOF'
int main(void) { return 0; }
EOF
clang -arch arm64 -mmacosx-version-min=26.0 -O0 -o "$work/bin-stripped" "$work/main.c" || exit 1
strip "$work/bin-stripped" || exit 1
# Unstripped: compiled with -g and linked from the .o, so the binary keeps a
# debug map (N_OSO) with the object file's absolute path, as Xcode's was.
clang -arch arm64 -mmacosx-version-min=26.0 -g -c -o "$work/main.o" "$work/main.c" || exit 1
clang -arch arm64 -mmacosx-version-min=26.0 -o "$work/bin-unstripped" "$work/main.o" || exit 1

entitlements() { # name, then key=bool pairs
  local file="$work/$1.entitlements"
  shift
  {
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    echo '<plist version="1.0"><dict>'
    local pair
    for pair in "$@"; do echo "<key>${pair%%=*}</key><${pair#*=}/>"; done
    echo '</dict></plist>'
  } >"$file"
  echo "$file"
}

make_app() { # case name, binary, entitlements file, codesign options
  local app="$work/$1/LiveCaptions.app"
  mkdir -p "$app/Contents/MacOS"
  cp "$2" "$app/Contents/MacOS/LiveCaptions"
  cat >"$app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>LiveCaptions</string>
	<key>CFBundleIdentifier</key><string>dev.trine.LiveCaptions</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>LSMinimumSystemVersion</key><string>26.0</string>
	<key>LSUIElement</key><true/>
	<key>NSAudioCaptureUsageDescription</key><string>test</string>
	<key>NSMicrophoneUsageDescription</key><string>test</string>
	<key>NSSpeechRecognitionUsageDescription</key><string>test</string>
</dict>
</plist>
EOF
  codesign --force --sign - $4 --entitlements "$3" "$app" >/dev/null 2>&1 || {
    echo "selftest: cannot sign $1" >&2
    exit 1
  }
  echo "$app"
}

expect_pass() { # case name, app
  local out
  if ! out="$("$verify" "$2" 2>&1)"; then
    echo "selftest: $1: expected pass, got: $out" >&2
    status=1
  fi
}

expect_fail() { # case name, app, expected message substring
  local out
  if out="$("$verify" "$2" 2>&1)"; then
    echo "selftest: $1: expected failure but passed" >&2
    status=1
  elif [[ "$out" != *"$3"* ]]; then
    echo "selftest: $1: failed for the wrong reason: $out" >&2
    status=1
  fi
}

audio='com.apple.security.device.audio-input=true'
good_ent="$(entitlements good "$audio")"
gta_ent="$(entitlements gta "$audio" 'com.apple.security.get-task-allow=true')"
extra_ent="$(entitlements extra "$audio" 'com.apple.security.cs.disable-library-validation=true')"
none_ent="$(entitlements none 'com.apple.security.cs.allow-jit=false')"

expect_pass good "$(make_app good "$work/bin-stripped" "$good_ent" '--options runtime')"
expect_fail get-task-allow "$(make_app gta "$work/bin-stripped" "$gta_ent" '--options runtime')" \
  "get-task-allow"
expect_fail extra-entitlement "$(make_app extra "$work/bin-stripped" "$extra_ent" '--options runtime')" \
  "unexpected entitlements"
expect_fail missing-audio-input "$(make_app none "$work/bin-stripped" "$none_ent" '--options runtime')" \
  "unexpected entitlements"
expect_fail no-hardened-runtime "$(make_app noruntime "$work/bin-stripped" "$good_ent" '')" \
  "hardened runtime"
expect_fail unstripped "$(make_app unstripped "$work/bin-unstripped" "$good_ent" '--options runtime')" \
  "not stripped"

[[ $status -eq 0 ]] && echo "verify-app selftest: OK"
exit $status
