#!/usr/bin/env bash
# Self-test for scripts/install.sh, the one-line installer
# (docs/DECISIONS.md 0027). Runs the real script against a fake release
# served over http on 127.0.0.1 (python3) and installs into a temporary
# folder instead of /Applications. Each case checks the exit status, the
# message, that the previous app is untouched when the install fails, and
# that no staging or temporary folder is left behind.
#
#   scripts/install-selftest.sh                       fake releases only
#   scripts/install-selftest.sh <version> <dist-dir>  also install the real
#                                                     LiveCaptions-<version>.zip
#                                                     from <dist-dir> (macOS)
#
# On macOS the script runs with /bin/bash (3.2, what users have), with the
# real uname, sw_vers, ditto and xattr; osascript, open and pgrep are stubs,
# so no app is opened or quit. On Linux, uname, sw_vers, sysctl, ditto and
# xattr are stubs too. The wrong-platform cases stub uname, sw_vers and
# sysctl on both.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
install_sh="$PWD/scripts/install.sh"
real_version="${1:-}"
real_dist="${2:-}"

if [[ "$(id -u)" -eq 0 ]]; then
  echo "install-selftest: run as a normal user; the installer refuses root and the read-only case needs permissions" >&2
  exit 1
fi
command -v python3 >/dev/null || { echo "install-selftest: python3 is required" >&2; exit 1; }
command -v shasum >/dev/null || { echo "install-selftest: shasum is required" >&2; exit 1; }

if [[ "$(uname -s)" == Darwin ]]; then
  on_mac=1
  run_bash=/bin/bash # macOS's bash 3.2, as `curl ... | bash` uses
else
  on_mac=0
  run_bash="$(command -v bash)"
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/install-selftest.XXXXXX")"
server_pid=""
# shellcheck disable=SC2329 # run by the EXIT trap
cleanup() {
  if [[ -n "$server_pid" ]]; then kill "$server_pid" 2>/dev/null; fi
  chmod -R u+w "$work" 2>/dev/null
  rm -rf "$work"
}
trap cleanup EXIT
status=0
fail() {
  echo "selftest: $*" >&2
  status=1
}

# --- Stub commands -----------------------------------------------------------

stubs="$work/stubs"   # always first on PATH
plat="$work/platform" # Linux only, or a wrong-platform case
mkdir -p "$stubs" "$plat"
log="$work/calls.log"
state="$work/state" # stub state: running, stubborn
mkdir -p "$state"

# pgrep -x LiveCaptions: running while $state/running exists.
cat >"$stubs/pgrep" <<EOF
#!/bin/sh
echo "pgrep \$*" >>"$log"
[ -e "$state/running" ]
EOF
# osascript ... quit: the app exits unless $state/stubborn exists.
cat >"$stubs/osascript" <<EOF
#!/bin/sh
echo "osascript \$*" >>"$log"
[ -e "$state/stubborn" ] || rm -f "$state/running"
EOF
cat >"$stubs/open" <<EOF
#!/bin/sh
echo "open \$*" >>"$log"
EOF
# The installer must never ask for a password.
cat >"$stubs/sudo" <<EOF
#!/bin/sh
echo "sudo \$*" >>"$log"
exit 1
EOF

write_platform() { # dir, uname -s, uname -m, sw_vers, sysctl hw.optional.arm64 (empty: fails)
  mkdir -p "$1"
  cat >"$1/uname" <<EOF
#!/bin/sh
case "\$1" in -s) echo "$2" ;; -m) echo "$3" ;; *) echo "$2" ;; esac
EOF
  cat >"$1/sw_vers" <<EOF
#!/bin/sh
echo "$4"
EOF
  if [[ -n "$5" ]]; then
    printf '#!/bin/sh\necho %s\n' "$5" >"$1/sysctl"
  else
    printf '#!/bin/sh\necho "sysctl: unknown oid" >&2\nexit 1\n' >"$1/sysctl"
  fi
  chmod +x "$1"/*
}

if [[ "$on_mac" -eq 0 ]]; then
  write_platform "$plat" Darwin arm64 26.1 1
  # ditto -x -k <zip> <dir>
  cat >"$plat/ditto" <<'EOF'
#!/bin/sh
[ "$1" = -x ] && [ "$2" = -k ] || { echo "ditto stub: unexpected $*" >&2; exit 2; }
exec python3 -I -m zipfile -e "$3" "$4"
EOF
  # xattr -r -l / -r -d: nothing on Linux carries a quarantine flag.
  cat >"$plat/xattr" <<EOF
#!/bin/sh
echo "xattr \$*" >>"$log"
EOF
fi
chmod +x "$stubs"/* "$plat"/* 2>/dev/null

# --- Fake releases -------------------------------------------------------------

root="$work/www"
mkdir -p "$root/api" "$root/download"

make_release() { # version [tamper|noapp|nozip|bad-checksum-name]
  local v="$1" how="${2:-}" dir="$root/download/v$1" src="$work/src-$1"
  mkdir -p "$dir" "$src/LiveCaptions.app/Contents/MacOS"
  if [[ "$how" == noapp ]]; then
    mkdir -p "$src/Other.app" && echo x >"$src/Other.app/file"
    (cd "$src" && python3 -I -m zipfile -c "$dir/LiveCaptions-$v.zip" Other.app)
  else
    echo "<plist><string>$v</string></plist>" >"$src/LiveCaptions.app/Contents/Info.plist"
    printf '#!/bin/sh\necho %s\n' "$v" >"$src/LiveCaptions.app/Contents/MacOS/LiveCaptions"
    chmod +x "$src/LiveCaptions.app/Contents/MacOS/LiveCaptions"
    (cd "$src" && python3 -I -m zipfile -c "$dir/LiveCaptions-$v.zip" LiveCaptions.app)
  fi
  (cd "$dir" && shasum -a 256 "LiveCaptions-$v.zip" >"LiveCaptions-$v.zip.sha256")
  case "$how" in
    tamper) printf 'tampered' >>"$dir/LiveCaptions-$v.zip" ;;
    nozip) rm "$dir/LiveCaptions-$v.zip" ;;
    bad-checksum-name) sed -i.bak 's/LiveCaptions-/Other-/' "$dir/LiveCaptions-$v.zip.sha256" && rm "$dir"/*.bak ;;
  esac
}

make_release 9.9.2
make_release 9.9.1
make_release 9.9.3 tamper
make_release 9.9.5 # its zip is served as HTTP 500 (see the server)
make_release 9.9.6 noapp
make_release 9.9.7 nozip
make_release 9.9.8 bad-checksum-name
cat >"$root/api/latest" <<'EOF'
{
  "url": "https://api.github.com/repos/zerone0x/mac-live-captions/releases/1",
  "tag_name": "v9.9.2",
  "name": "LiveCaptions 9.9.2",
  "assets": [
    { "name": "LiveCaptions-9.9.2.zip" }
  ]
}
EOF
echo '{"message": "API rate limit exceeded for 203.0.113.9. (But here'"'"'s the good news: Authenticated requests get a higher rate limit.)"}' >"$root/api/ratelimited"
echo '{"tag_name": "latest; rm -rf /"}' >"$root/api/badtag"

if [[ -n "$real_version" ]]; then
  [[ -n "$real_dist" ]] || { echo "usage: install-selftest.sh [<version> <dist-dir>]" >&2; exit 1; }
  mkdir -p "$root/download/v$real_version"
  cp "$real_dist/LiveCaptions-$real_version.zip" "$real_dist/LiveCaptions-$real_version.zip.sha256" \
    "$root/download/v$real_version/" || { echo "install-selftest: no release files in $real_dist" >&2; exit 1; }
fi

# A static server; /api/ratelimited answers 403 like GitHub, and the 9.9.5
# zip answers 500 (a failed download).
cat >"$work/server.py" <<'EOF'
import functools, http.server, sys
root, port_file = sys.argv[1], sys.argv[2]
class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/api/ratelimited":
            body = open(root + "/api/ratelimited", "rb").read()
            self.send_response(403)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif self.path.endswith("/LiveCaptions-9.9.5.zip"):
            self.send_error(500)
        else:
            super().do_GET()
    def log_message(self, *args):
        pass
server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(Handler, directory=root))
with open(port_file + ".tmp", "w") as f:
    f.write(str(server.server_address[1]))
import os
os.rename(port_file + ".tmp", port_file)
server.serve_forever()
EOF
python3 -I "$work/server.py" "$root" "$work/port" &
server_pid=$!
# Up to 60 s: python can be slow to start on a busy CI runner.
for _ in $(seq 1 600); do
  [[ -s "$work/port" ]] && break
  sleep 0.1
done
[[ -s "$work/port" ]] || { echo "install-selftest: the test server did not start within 60 s" >&2; exit 1; }
base="http://127.0.0.1:$(cat "$work/port")"

# --- Cases ---------------------------------------------------------------------

apps="$work/Applications"
mkdir -p "$apps"
app="$apps/LiveCaptions.app"

installed() { # prints the installed app's version, or "none"
  if [[ -f "$app/Contents/MacOS/LiveCaptions" ]]; then
    sed -n 's/^echo //p' "$app/Contents/MacOS/LiveCaptions"
  else
    echo none
  fi
}

# run <name> pass|fail <message substring> <expected installed version after>
#     [VAR=value ...] [-- installer args]
# <expected installed version after> may be "any" (a real app).
# With PIPE=1 in the assignments, feeds the script on stdin like curl | bash.
run() {
  local name="$1" expect="$2" want="$3" after="$4" out rc=0 path="$stubs:$PATH" pipe=0
  shift 4
  local -a envs=() args=()
  while [[ $# -gt 0 && "$1" != -- ]]; do
    case "$1" in
      PIPE=1) pipe=1 ;;
      PLATFORM=*) path="$stubs:${1#PLATFORM=}:$PATH" ;;
      *) envs+=("$1") ;;
    esac
    shift
  done
  [[ $# -gt 0 ]] && shift
  args=("$@")
  if [[ "$on_mac" -eq 0 && "$path" == "$stubs:$PATH" ]]; then path="$stubs:$plat:$PATH"; fi
  local tmp="$work/tmp-$name"
  mkdir -p "$tmp"
  : >"$log"
  local -a cmd=(env "PATH=$path" "TMPDIR=$tmp" "LIVECAPTIONS_RELEASE_BASE=$base"
    "LIVECAPTIONS_API_URL=$base/api/latest" "LIVECAPTIONS_APPS_DIR=$apps"
    "LIVECAPTIONS_QUIT_TIMEOUT=2" ${envs[@]+"${envs[@]}"})
  if [[ "$pipe" -eq 1 ]]; then
    out="$("${cmd[@]}" "$run_bash" -s -- ${args[@]+"${args[@]}"} <"$install_sh" 2>&1)" || rc=$?
  else
    out="$("${cmd[@]}" "$run_bash" "$install_sh" ${args[@]+"${args[@]}"} </dev/null 2>&1)" || rc=$?
  fi
  if [[ "$expect" == pass && "$rc" -ne 0 ]]; then
    fail "$name: expected success, got exit $rc: $out"
  elif [[ "$expect" == fail && "$rc" -eq 0 ]]; then
    fail "$name: expected failure, but it passed: $out"
  elif [[ "$out" != *"$want"* ]]; then
    fail "$name: output lacks '$want': $out"
  fi
  local got
  got="$(installed)"
  [[ "$after" == any || "$got" == "$after" ]] || fail "$name: installed version is '$got', expected '$after'"
  local left
  left="$(find "$apps" -mindepth 1 -maxdepth 1 ! -name LiveCaptions.app)"
  [[ -z "$left" ]] || fail "$name: left behind in the apps folder: $left"
  left="$(find "$tmp" -mindepth 1)"
  [[ -z "$left" ]] || fail "$name: left behind in TMPDIR: $left"
  if grep -q '^sudo' "$log"; then fail "$name: ran sudo"; fi
  LAST_OUT="$out"
  echo "ok: $name"
}
called() { grep -q "$1" "$log" || fail "$2: expected a call matching '$1'; calls: $(cat "$log")"; }
not_called() { if grep -q "$1" "$log"; then fail "$2: unexpected call matching '$1'"; fi; }

# Fresh install of the latest release (API lookup).
run happy-latest pass "Version 9.9.2 (latest release)" 9.9.2
[[ "$LAST_OUT" == *"Checksum OK"* && "$LAST_OUT" == *"Installed $app"* ]] \
  || fail "happy-latest: missing steps in output: $LAST_OUT"
called "open $app" happy-latest
not_called osascript happy-latest

# Replace the installed app with another version while it runs; fed on stdin
# like `curl ... | bash -s -- 9.9.1`.
touch "$state/running"
run replace-running-piped pass "Replaced $app" 9.9.1 PIPE=1 -- v9.9.1
called "osascript -e tell application id \"dev.trine.LiveCaptions\" to quit" replace-running-piped
called "open $app" replace-running-piped
[[ ! -e "$state/running" ]] || fail "replace-running-piped: the app was not quit"

# Everything below must fail and leave 9.9.1 in place.
run checksum-mismatch fail "checksum mismatch" 9.9.1 -- 9.9.3
not_called open checksum-mismatch
run missing-version fail "not found (HTTP 404)" 9.9.1 -- 9.9.4
run missing-zip fail "not found (HTTP 404)" 9.9.1 -- 9.9.7
run failed-download fail "download failed (HTTP 500)" 9.9.1 -- 9.9.5
run zip-without-app fail "does not contain LiveCaptions.app" 9.9.1 -- 9.9.6
run checksum-names-other-file fail "is not one '<SHA-256>  LiveCaptions-9.9.8.zip' line" 9.9.1 -- 9.9.8
run bad-version-argument fail "is not a version like 0.1.2" 9.9.1 -- '0.1;rm'
run two-arguments fail "at most one argument" 9.9.1 -- 9.9.2 9.9.1
run rate-limited fail "GitHub API rate limit reached" 9.9.1 "LIVECAPTIONS_API_URL=$base/api/ratelimited"
run latest-bad-tag fail "unexpected tag" 9.9.1 "LIVECAPTIONS_API_URL=$base/api/badtag"
run no-apps-dir fail "does not exist" 9.9.1 "LIVECAPTIONS_APPS_DIR=$work/nowhere" -- 9.9.2

touch "$state/running" "$state/stubborn"
run app-will-not-quit fail "still running after 2s" 9.9.1 -- 9.9.2
not_called open app-will-not-quit
rm -f "$state/running" "$state/stubborn"

chmod a-w "$apps"
run apps-dir-read-only fail "is not writable" 9.9.1 -- 9.9.2
[[ "$LAST_OUT" == *"never uses sudo"* ]] || fail "apps-dir-read-only: no word about sudo: $LAST_OUT"
chmod u+w "$apps"

# Wrong platforms (stubbed uname, sw_vers, sysctl on every OS).
write_platform "$work/p-linux" Linux x86_64 "" ""
write_platform "$work/p-intel" Darwin x86_64 26.1 ""
write_platform "$work/p-rosetta" Darwin x86_64 26.1 1
write_platform "$work/p-old" Darwin arm64 15.6.1 1
run wrong-os fail "LiveCaptions is a macOS app; this is Linux" 9.9.1 "PLATFORM=$work/p-linux" -- 9.9.2
run intel-mac fail "needs an Apple Silicon Mac" 9.9.1 "PLATFORM=$work/p-intel" -- 9.9.2
run old-macos fail "needs macOS 26 or later; this Mac has macOS 15.6.1" 9.9.1 "PLATFORM=$work/p-old" -- 9.9.2
if [[ "$on_mac" -eq 1 ]]; then
  # The real ditto and xattr; only the platform answers are stubbed.
  run rosetta-shell pass "Replaced $app" 9.9.2 "PLATFORM=$work/p-rosetta" -- 9.9.2
else
  cp "$plat/ditto" "$plat/xattr" "$work/p-rosetta/"
  run rosetta-shell pass "Replaced $app" 9.9.2 "PLATFORM=$work/p-rosetta" -- 9.9.2
fi

# On macOS: a quarantined download is cleared (real xattr).
if [[ "$on_mac" -eq 1 ]]; then
  zip="$root/download/v9.9.1/LiveCaptions-9.9.1.zip"
  # ditto carries the zip's quarantine flag onto what it unpacks only when
  # asked by LaunchServices, so set it on the zip's contents directly: make a
  # quarantined copy of the app and zip it with ditto, which keeps xattrs.
  q="$work/quarantined"
  mkdir -p "$q"
  ditto -x -k "$zip" "$q"
  xattr -w com.apple.quarantine "0081;00000000;Safari;" "$q/LiveCaptions.app/Contents/Info.plist"
  ditto -c -k --keepParent "$q/LiveCaptions.app" "$zip"
  (cd "$root/download/v9.9.1" && shasum -a 256 LiveCaptions-9.9.1.zip >LiveCaptions-9.9.1.zip.sha256)
  run quarantine-cleared pass "Cleared the quarantine flag" 9.9.1 -- 9.9.1
  attrs="$(xattr -r -l "$app")" || fail "quarantine-cleared: xattr failed"
  [[ "$attrs" != *com.apple.quarantine* ]] || fail "quarantine-cleared: flag still set: $attrs"
fi

# On macOS with a real release: install the real app and check its signature.
if [[ -n "$real_version" ]]; then
  if [[ "$on_mac" -eq 1 ]]; then
    run real-release pass "Version $real_version (asked for)" any -- "$real_version"
    codesign --verify --deep --strict "$app" || fail "real-release: codesign --verify failed on the installed app"
    v="$(defaults read "$app/Contents/Info.plist" CFBundleShortVersionString)" || fail "real-release: no version"
    [[ "${v:-}" == "$real_version" ]] || fail "real-release: installed version is '${v:-}', expected $real_version"
  else
    echo "skip: real-release needs macOS"
  fi
fi

if [[ "$status" -eq 0 ]]; then
  # shellcheck disable=SC2016 # expanded by the child bash
  echo "install-selftest: all cases passed ($("$run_bash" -c 'echo "bash $BASH_VERSION"'))"
fi
exit "$status"
