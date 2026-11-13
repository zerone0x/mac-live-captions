#!/usr/bin/env bash
# Screenshots of the running app (#23, #38).
#
# Starts the built app with --demo-captions (the scripted caption feed, no
# audio and no permissions), waits, and captures the whole screen and the top
# strip with `screencapture -x` at a few points of the demo. Also records which
# windows the app has on screen (windows.txt), so a missing window in a PNG
# can be told apart from a capture limit.
#
# Usage: scripts/live-screenshots.sh <LiveCaptions.app> <output dir>
#
# On GitHub's macOS runners the runner agent holds Screen Recording, and
# `screencapture` started from a step inherits it, so the PNGs show other
# apps' windows. Without that grant `screencapture` still succeeds but shows
# only the desktop and the menu bar, and the window list is the same, so the
# script checks the pixels where the overlay is (screen-info.swift
# overlay-check). That needs a one-colour desktop picture around the overlay.
#
# Every command has a time limit (scripts/with-timeout.sh), also outside CI.
# Exit status: 0 ok, 1 a finding (the app quit, no overlay, or the overlay
# is not in the capture), 2 usage or tool error (including a timeout).
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <LiveCaptions.app> <output dir>" >&2
  exit 2
fi
app="$1"
out="$2"
binary="$app/Contents/MacOS/LiveCaptions"
script_dir="$(cd "$(dirname "$0")" && pwd)"
limit="$script_dir/with-timeout.sh"
# `swift <script>` compiles first: allow for a cold compiler.
swift_limit=180

if [[ ! -x "$binary" ]]; then
  echo "error: $binary is missing or not executable" >&2
  exit 1
fi
mkdir -p "$out"

# Runs a tool under a time limit; any failure of a tool is exit 2.
tool() {
  local seconds="$1"
  shift
  local rc=0
  "$limit" "$seconds" "$@" || rc=$?
  if [[ "$rc" -ne 0 ]]; then
    echo "error: '$*' failed (exit $rc)" >&2
    exit 2
  fi
}

# Seconds after launch for each shot: the first lines of the demo, a later
# two-line state, and the next pass of the repeating demo.
shots=(3 7 12)

# The main screen's size in points, for the top strip. Read before the
# launch: compiling the helper takes a few seconds.
size="$(tool "$swift_limit" swift "$script_dir/screen-info.swift" size)"
if [[ ! "$size" =~ ^([0-9]+)\ ([0-9]+)$ ]]; then
  echo "error: unexpected screen size '$size'" >&2
  exit 2
fi
screen_width="${BASH_REMATCH[1]}"
echo "main screen: ${screen_width}x${BASH_REMATCH[2]} points"

# Started directly (not with `open`), so the app is a child of this step.
"$binary" --demo-captions >"$out/app.log" 2>&1 &
app_pid=$!
launched=$SECONDS
cleanup() {
  if kill -0 "$app_pid" 2>/dev/null; then
    kill "$app_pid"
    # An app that ignores SIGTERM gets SIGKILL after 5 seconds.
    local waited=0
    while kill -0 "$app_pid" 2>/dev/null && ((waited < 50)); do
      sleep 0.1
      waited=$((waited + 1))
    done
    if kill -0 "$app_pid" 2>/dev/null; then
      echo "LiveCaptions ignored SIGTERM; killing it" >&2
      kill -KILL "$app_pid"
    fi
    # Reap it and log its status (143 = SIGTERM; bash also logs "Terminated").
    local app_status=0
    wait "$app_pid" 2>/dev/null || app_status=$?
    echo "LiveCaptions stopped (status $app_status)"
  fi
}
trap cleanup EXIT

for shot in "${shots[@]}"; do
  # Shots are timed from the launch; listing windows takes a moment too.
  wait_for=$((launched + shot - SECONDS))
  if ((wait_for > 0)); then
    sleep "$wait_for"
  fi
  if ! kill -0 "$app_pid" 2>/dev/null; then
    echo "error: LiveCaptions exited before the ${shot}s screenshot; app.log:" >&2
    cat "$out/app.log" >&2
    exit 1
  fi
  tool 30 screencapture -x "$out/live-full-${shot}s.png"
  tool 30 screencapture -x -R "0,0,${screen_width},240" "$out/live-top-${shot}s.png"
  tool "$swift_limit" swift "$script_dir/screen-info.swift" windows "$app_pid" >"$out/windows-${shot}s.txt"
  echo "captured live-full-${shot}s.png, live-top-${shot}s.png; windows:"
  cat "$out/windows-${shot}s.txt"
done

for file in "$out"/live-*.png; do
  if [[ ! -s "$file" ]]; then
    echo "error: $file is empty" >&2
    exit 1
  fi
done

# The app's windows in CGWindowList are the overlay panel (above the menu
# bar: layer > 0) and, until it is closed once, the welcome window (layer 0).
# The menu-bar icon is not in the list. So look for exactly one overlay and
# let the welcome window be there or not.
for shot in "${shots[@]}"; do
  overlays=0
  frame=()
  while IFS= read -r line; do
    if [[ ! "$line" =~ ^layer=(-?[0-9]+)\ alpha=[-0-9.]+\ x=(-?[0-9]+)\ y=(-?[0-9]+)\ width=([0-9]+)\ height=([0-9]+)$ ]]; then
      echo "error: unexpected line in windows-${shot}s.txt: $line" >&2
      exit 2
    fi
    if ((BASH_REMATCH[1] > 0)); then
      overlays=$((overlays + 1))
      frame=("${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" "${BASH_REMATCH[4]}" "${BASH_REMATCH[5]}")
    fi
  done <"$out/windows-${shot}s.txt"
  if ((overlays != 1)); then
    echo "error: LiveCaptions had $overlays overlay window(s) on screen at ${shot}s, expected 1 (windows-${shot}s.txt)" >&2
    exit 1
  fi

  # Without Screen Recording the capture shows the desktop where the
  # overlay is, although the window list has it.
  rc=0
  "$limit" "$swift_limit" swift "$script_dir/screen-info.swift" overlay-check \
    "$out/live-full-${shot}s.png" "$screen_width" "${frame[@]}" || rc=$?
  case "$rc" in
    0) ;;
    1)
      echo "error: the overlay is not in live-full-${shot}s.png. Does the terminal (or CI agent) have Screen Recording?" >&2
      exit 1
      ;;
    *)
      echo "error: overlay check of live-full-${shot}s.png failed (exit $rc)" >&2
      exit 2
      ;;
  esac
done
echo "live screenshots in $out"
