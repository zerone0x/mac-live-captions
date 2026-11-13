#!/usr/bin/env bash
# Self-test for the checks in scripts/live-screenshots.sh (#38):
#
# - scripts/with-timeout.sh passes the exit status through, stops a command
#   at the limit with 124, also when it ignores SIGTERM or a child keeps the
#   output pipe open, and returns at once when the command is done.
# - `screen-info.swift overlay-check` (macOS) passes a screenshot that shows
#   the overlay, at scale 1 and 2, finds a screenshot that shows only the
#   desktop where the overlay is (Screen Recording denied), and is an error
#   when the desktop around the overlay is too busy to tell.
#
# The with-timeout cases also run on Linux.
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
timeout_sh="$root/scripts/with-timeout.sh"
work="$(mktemp -d)" || exit 2
trap 'rm -rf "$work"' EXIT
status=0

# expect <exit> <max seconds> <label> <command...>: the command's exit status
# and that it took at most <max seconds>. Output goes to $work/out.txt.
expect() {
  local want="$1" max="$2" label="$3"
  shift 3
  local start=$SECONDS rc=0
  "$@" >"$work/out.txt" 2>&1 || rc=$?
  local took=$((SECONDS - start))
  if [[ "$rc" -ne "$want" ]]; then
    echo "FAIL $label: exit $rc, expected $want" >&2
    cat "$work/out.txt" >&2
    status=1
  elif (( took > max )); then
    echo "FAIL $label: took ${took}s, expected at most ${max}s" >&2
    status=1
  else
    echo "ok   $label (exit $rc, ${took}s)"
  fi
}

# Runs with-timeout inside a command substitution, as a caller that reads
# its output does: a leftover child holding the pipe would block here.
captured() {
  local out
  out="$("$timeout_sh" "$@")"
  local rc=$?
  printf '%s\n' "$out"
  return "$rc"
}

expect 0 5 "with-timeout: a quick command passes" "$timeout_sh" 10 true
expect 3 5 "with-timeout: the exit status passes through" "$timeout_sh" 10 sh -c 'exit 3'
expect 124 5 "with-timeout: a slow command times out" "$timeout_sh" 1 sleep 60
expect 124 10 "with-timeout: a command that ignores SIGTERM is killed" \
  "$timeout_sh" 1 sh -c 'trap "" TERM; sleep 60; sleep 60'
expect 124 5 "with-timeout: a child holding the output pipe is killed" \
  captured 1 sh -c 'sleep 60 & echo started; wait'
expect 0 5 "with-timeout: a finished command's leftover child does not block" \
  captured 30 sh -c '(trap "" TERM; sleep 60) & echo started'
expect 2 5 "with-timeout: a zero limit is a usage error" "$timeout_sh" 0 true
expect 2 5 "with-timeout: a missing command is a usage error" "$timeout_sh" 10

if [[ "$(uname)" != Darwin ]]; then
  echo "selftest: not macOS, skipping the overlay-check cases (they need CoreGraphics)"
else
  shots="$work/shots"
  if ! python3 "$root/scripts/png-fixtures.py" overlay "$shots"; then
    echo "FAIL cannot write the test images" >&2
    exit 2
  fi
  check() {
    "$timeout_sh" 300 swift "$root/scripts/screen-info.swift" overlay-check "$@"
  }
  # A 300-point-wide screen, the overlay at x=60 y=40, 180 x 50 points.
  frame=(60 40 180 50)
  expect 0 300 "overlay-check: the overlay is in the capture" check "$shots/shown.png" 300 "${frame[@]}"
  expect 0 300 "overlay-check: the overlay is in a Retina (2x) capture" check "$shots/shown-2x.png" 300 "${frame[@]}"
  expect 1 300 "overlay-check: only the desktop (Screen Recording denied)" \
    check "$shots/desktop-only.png" 300 "${frame[@]}"
  expect 1 300 "overlay-check: only the desktop in a Retina capture" \
    check "$shots/desktop-only-2x.png" 300 "${frame[@]}"
  expect 1 300 "overlay-check: a black overlay on a black desktop can't be told apart" \
    check "$shots/black-desktop.png" 300 "${frame[@]}"
  expect 2 300 "overlay-check: a busy desktop picture is an error" check "$shots/busy-desktop.png" 300 "${frame[@]}"
  expect 1 300 "overlay-check: the overlay is looked for at the given frame" \
    check "$shots/shown.png" 300 60 95 180 50
  expect 2 300 "overlay-check: a frame off the screen is an error" check "$shots/shown.png" 300 400 40 180 50
  expect 2 300 "overlay-check: an unreadable PNG is an error" check "$work/nope.png" 300 "${frame[@]}"
  expect 2 300 "overlay-check: missing arguments are an error" check "$shots/shown.png" 300 60 40
fi

if [[ $status -ne 0 ]]; then
  echo "live-screenshots self-test FAILED" >&2
  exit 1
fi
echo "live-screenshots self-test passed"
