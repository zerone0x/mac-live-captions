#!/usr/bin/env bash
# Runs a command with a time limit (#38); macOS has no `timeout`.
#
# Usage: scripts/with-timeout.sh <seconds> <command> [args...]
#
# The command runs in its own process group. When the limit is up, the whole
# group gets SIGTERM and, 5 seconds later, SIGKILL, so children that ignore
# SIGTERM or keep the output pipe open (swift's compiler, for example) end
# too. Exit status: the command's, or 124 when it timed out, 2 on bad usage.
#
# No `set -e`: the kills below may find the processes gone, which is fine.
set -uo pipefail

if [[ $# -lt 2 || ! "$1" =~ ^[0-9]+$ || "$1" -eq 0 ]]; then
  echo "usage: $0 <seconds> <command> [args...]" >&2
  exit 2
fi
limit="$1"
shift
marker="$(mktemp)" || exit 2
rm -f "$marker"

# Job control gives the background job its own process group (pgid = pid).
set -m
"$@" &
pid=$!
set +m
# Interrupted (Ctrl-C reaches only the foreground group): take the command along.
trap 'kill -TERM -- "-$pid" 2>/dev/null; exit 130' INT TERM

# The watchdog's own output goes nowhere, so a leftover `sleep` can't hold
# the caller's pipe open. It stops its sleep when it is cancelled.
(
  nap=""
  trap 'kill $nap 2>/dev/null; exit 0' TERM
  sleep "$limit" &
  nap=$!
  wait "$nap"
  : >"$marker"
  kill -TERM -- "-$pid" 2>/dev/null
  sleep 5 &
  nap=$!
  wait "$nap"
  kill -KILL -- "-$pid" 2>/dev/null
) </dev/null >/dev/null 2>&1 &
watchdog=$!

wait "$pid"
rc=$?
# The command is done; cancel the delayed kill, then end what is left of
# its group (background children that would hold the pipe).
kill -TERM "$watchdog" 2>/dev/null
wait "$watchdog" 2>/dev/null
kill -KILL -- "-$pid" 2>/dev/null

if [[ -e "$marker" ]]; then
  rm -f "$marker"
  echo "error: timed out after ${limit}s: $*" >&2
  exit 124
fi
exit "$rc"
