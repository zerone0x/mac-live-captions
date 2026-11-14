#!/usr/bin/env bash
# Runs a command with a time limit (#38); macOS has no `timeout`.
#
# Usage: scripts/with-timeout.sh <seconds> <command> [args...]
#
# The command runs in its own process group. When the limit is up, the whole
# group gets SIGTERM and, 5 seconds later, SIGKILL, so children that ignore
# SIGTERM or keep the output pipe open (swift's compiler, for example) end
# too. When the command is done, what is left of its group is killed, so a
# leftover background child can't hold the caller's pipe open. Exit status:
# the command's, 124 when it timed out, 2 on bad usage or when the command
# could not be put in a process group of its own (or that group not ended).
#
# The process group does not rely on bash job control (`set -m`), which did
# not reliably give the command its own group on CI (#51): a small perl
# launcher calls setpgrp(), checks that it leads the new group, reports its
# pid through a file and execs the command, which keeps that pid and group.
#
# No `set -e`: the kills below may find the processes gone, which is fine.
set -uo pipefail

if [[ $# -lt 2 || ! "$1" =~ ^[0-9]+$ || "$1" -eq 0 ]]; then
  echo "usage: $0 <seconds> <command> [args...]" >&2
  exit 2
fi
limit="$1"
shift
if ! command -v perl >/dev/null 2>&1; then
  echo "error: with-timeout needs perl to start the command in its own process group" >&2
  exit 2
fi
state="$(mktemp -d)" || exit 2
marker="$state/timed-out"
ready="$state/pgid"

# Lists the live (not zombie) processes in group $1; fails when ps does.
group_members() {
  local out
  out="$(ps -A -o pgid= -o stat=)" || return 1
  awk -v g="$1" '$1 == g && $2 !~ /^Z/' <<<"$out"
}

# The launcher: make a new process group, check that it leads it, report the
# group id, then become the command. Exits 2 without running the command when
# any of that fails.
launcher='
  my $ready = shift @ARGV;
  setpgrp(0, 0) or exit 2;
  getpgrp() == $$ or exit 2;
  open(my $fh, ">", "$ready.tmp") or exit 2;
  print $fh "$$\n" or exit 2;
  close($fh) or exit 2;
  rename("$ready.tmp", $ready) or exit 2;
  exec { $ARGV[0] } @ARGV;
  print STDERR "with-timeout: cannot run $ARGV[0]: $!\n";
  exit 127;
'
# `0<&0`: a background command would otherwise get /dev/null as its input.
perl -e "$launcher" "$ready" "$@" 0<&0 &
pid=$!
# Interrupted (Ctrl-C reaches only the foreground group): take the command along.
trap 'kill -TERM -- "-$pid" 2>/dev/null; kill -TERM "$pid" 2>/dev/null; rm -rf "$state"; exit 130' INT TERM

# Wait (at most 10 s) until the launcher reports its group, or is gone.
tries=0
while [[ ! -e "$ready" ]] && kill -0 "$pid" 2>/dev/null && ((tries < 200)); do
  sleep 0.05
  tries=$((tries + 1))
done
pgid=""
[[ -e "$ready" ]] && pgid="$(cat "$ready")"
if [[ "$pgid" != "$pid" ]]; then
  # Fail closed: without a group of its own the command can't be stopped
  # reliably, so it must not run on.
  kill -KILL "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  rm -rf "$state"
  echo "error: could not start the command in its own process group (group '${pgid}', pid ${pid}): $*" >&2
  exit 2
fi

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
# Fail closed: the group must be gone (give the kernel up to 5 s).
tries=0
while :; do
  if ! left="$(group_members "$pid")"; then
    echo "error: cannot list processes to check that group $pid ended: $*" >&2
    rm -rf "$state"
    exit 2
  fi
  [[ -z "$left" ]] && break
  if ((tries >= 100)); then
    echo "error: process group $pid did not end: $*" >&2
    rm -rf "$state"
    exit 2
  fi
  kill -KILL -- "-$pid" 2>/dev/null
  sleep 0.05
  tries=$((tries + 1))
done

if [[ -e "$marker" ]]; then
  rm -rf "$state"
  echo "error: timed out after ${limit}s: $*" >&2
  exit 124
fi
rm -rf "$state"
exit "$rc"
