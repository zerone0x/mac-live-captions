#!/usr/bin/env bash
# Screenshots of the running app (#23).
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
# apps' windows. On a Mac without that grant they show only the desktop.
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <LiveCaptions.app> <output dir>" >&2
  exit 2
fi
app="$1"
out="$2"
binary="$app/Contents/MacOS/LiveCaptions"
script_dir="$(cd "$(dirname "$0")" && pwd)"

if [[ ! -x "$binary" ]]; then
  echo "error: $binary is missing or not executable" >&2
  exit 1
fi
mkdir -p "$out"

# Seconds after launch for each shot: the first lines of the demo, a later
# two-line state, and the next pass of the repeating demo.
shots=(3 7 12)

# The main screen's size in points, for the top strip. Read before the
# launch: compiling the helper takes a few seconds.
read -r screen_width screen_height < <(swift "$script_dir/screen-info.swift" size)
echo "main screen: ${screen_width}x${screen_height} points"

# Started directly (not with `open`), so the app is a child of this step.
"$binary" --demo-captions >"$out/app.log" 2>&1 &
app_pid=$!
launched=$SECONDS
cleanup() {
  if kill -0 "$app_pid" 2>/dev/null; then
    kill "$app_pid"
    wait "$app_pid" 2>/dev/null || :
  fi
}
trap cleanup EXIT

for shot in "${shots[@]}"; do
  # Shots are timed from the launch; listing windows takes a moment too.
  wait_for=$((launched + shot - SECONDS))
  if (( wait_for > 0 )); then
    sleep "$wait_for"
  fi
  if ! kill -0 "$app_pid" 2>/dev/null; then
    echo "error: LiveCaptions exited before the ${shot}s screenshot; app.log:" >&2
    cat "$out/app.log" >&2
    exit 1
  fi
  screencapture -x "$out/live-full-${shot}s.png"
  screencapture -x -R "0,0,${screen_width},240" "$out/live-top-${shot}s.png"
  swift "$script_dir/screen-info.swift" windows "$app_pid" >"$out/windows-${shot}s.txt"
  echo "captured live-full-${shot}s.png, live-top-${shot}s.png; windows:"
  cat "$out/windows-${shot}s.txt"
done

for file in "$out"/live-*.png; do
  if [[ ! -s "$file" ]]; then
    echo "error: $file is empty" >&2
    exit 1
  fi
done

# While the demo plays the app has at least the status item and the overlay
# panel on screen (and the welcome window on a first launch).
windows="$(wc -l <"$out/windows-${shots[0]}s.txt")"
if (( windows < 2 )); then
  echo "error: LiveCaptions had $windows window(s) on screen at ${shots[0]}s, expected the status item and the overlay" >&2
  exit 1
fi
echo "live screenshots in $out"
