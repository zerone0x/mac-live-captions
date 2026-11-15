#!/bin/bash
# One-line installer for LiveCaptions (docs/DECISIONS.md 0027):
#
#   curl -fsSL https://raw.githubusercontent.com/zerone0x/mac-live-captions/main/scripts/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/zerone0x/mac-live-captions/main/scripts/install.sh | bash -s -- 0.1.2
#
# It does what README, Install describes by hand for the zip:
#   1. checks for an Apple Silicon Mac with macOS 26 or later;
#   2. finds the latest release with the GitHub API (no token), unless a
#      version is given;
#   3. downloads LiveCaptions-<version>.zip and its .sha256 file into a
#      temporary folder (removed on exit) and refuses unless
#      `shasum -a 256 -c` passes;
#   4. unpacks the app into a staging folder inside /Applications and checks
#      the bundle;
#   5. quits a running LiveCaptions and waits for it to exit;
#   6. moves the old app aside, moves the new one in, and puts the old one
#      back if that fails, so a failure never leaves you without an app;
#   7. clears the quarantine flag and opens the app.
#
# It never uses sudo, sends nothing anywhere except the downloads from
# GitHub, and stops at the first error (fail closed). It runs with macOS's
# /bin/bash 3.2.
#
# Overrides, used by scripts/install-selftest.sh (not needed to install):
#   LIVECAPTIONS_RELEASE_BASE   releases URL; files come from
#                               <base>/download/v<version>/
#   LIVECAPTIONS_API_URL        URL of the "latest release" JSON
#   LIVECAPTIONS_APPS_DIR       folder to install into (default /Applications)
#   LIVECAPTIONS_QUIT_TIMEOUT   seconds to wait for the app to quit (20)

set -euo pipefail

# The folders cleanup removes. Unset first, so a value exported by the
# caller (and its export flag) is gone; each is set only right after the
# script made that folder.
unset WORK STAGE KEEP_STAGE
WORK=""
STAGE=""
KEEP_STAGE=""

# Everything is inside main, called on the last line, so a download cut off
# half-way through (curl ... | bash) runs nothing.
main() {
  local repo_url="https://github.com/zerone0x/mac-live-captions"
  local base="${LIVECAPTIONS_RELEASE_BASE:-$repo_url/releases}"
  local api_url="${LIVECAPTIONS_API_URL:-https://api.github.com/repos/zerone0x/mac-live-captions/releases/latest}"
  local apps_dir="${LIVECAPTIONS_APPS_DIR:-/Applications}"
  local quit_timeout="${LIVECAPTIONS_QUIT_TIMEOUT:-20}"
  local app_name="LiveCaptions"
  local bundle_id="dev.trine.LiveCaptions"

  case "${1:-}" in
    -h | --help)
      echo "usage: install.sh [<version>]   (for example 0.1.2; default: the latest release)"
      return 0
      ;;
  esac
  [[ $# -le 1 ]] || die "expected at most one argument (a version such as 0.1.2), got $#"
  [[ "$quit_timeout" =~ ^[0-9]+$ ]] || die "LIVECAPTIONS_QUIT_TIMEOUT must be a number of seconds"

  if [[ "$(id -u)" -eq 0 ]]; then
    die "do not run this with sudo or as root; run it as yourself"
  fi

  check_platform

  # Version: the argument, or the latest release.
  local version version_re='^[0-9]+[.][0-9]+[.][0-9]+$'
  if [[ $# -eq 1 ]]; then
    version="${1#v}"
    [[ "$version" =~ $version_re ]] \
      || die "'$1' is not a version like 0.1.2"
    say "Version $version (asked for)"
  else
    version="$(latest_version "$api_url")" || exit 1
    say "Version $version (latest release)"
  fi

  # Where it goes. No sudo: the folder must be writable by you.
  [[ -d "$apps_dir" ]] || die "$apps_dir does not exist"
  if [[ ! -w "$apps_dir" ]]; then
    die "$apps_dir is not writable by $(id -un). This installer never uses sudo.
       Ask an administrator to install LiveCaptions, or follow the manual steps in
       $repo_url#install"
  fi
  local target="$apps_dir/$app_name.app"

  # Temporary folder for the downloads, and a staging folder next to the
  # target (same volume, so the final move is a rename). Both go on exit.
  trap cleanup EXIT
  local made
  made="$(mktemp -d "${TMPDIR:-/tmp}/livecaptions-install.XXXXXX")" || die "cannot create a temporary folder"
  WORK="$made"
  made="$(mktemp -d "$apps_dir/.$app_name-install.XXXXXX")" \
    || die "cannot create a staging folder in $apps_dir"
  STAGE="$made"

  # Download and check.
  local zip="$app_name-$version.zip"
  local url="$base/download/v$version"
  say "Downloading $url/$zip"
  download "$url/$zip.sha256" "$WORK/$zip.sha256"
  download "$url/$zip" "$WORK/$zip"

  # Regexes live in variables: bash 3.2 and later read them the same way.
  local lines line sum_re='^[0-9a-f]{64}  [^ ]+$'
  lines="$(wc -l <"$WORK/$zip.sha256" | tr -d ' ')"
  line="$(cat "$WORK/$zip.sha256")"
  if [[ "$lines" != 1 ]] || ! [[ "$line" =~ $sum_re ]] || [[ "${line#*  }" != "$zip" ]]; then
    die "$zip.sha256 is not one '<SHA-256>  $zip' line; refusing to install"
  fi
  local check
  if ! check="$(cd "$WORK" && shasum -a 256 -c "$zip.sha256" 2>&1)"; then
    die "checksum mismatch for $zip; refusing to install. shasum said:
$check"
  fi
  say "Checksum OK (SHA-256 ${line%%  *})"

  # Unpack into the staging folder and check the bundle.
  ditto -x -k "$WORK/$zip" "$STAGE" </dev/null || die "cannot unpack $zip"
  local new_app="$STAGE/$app_name.app"
  [[ -f "$new_app/Contents/Info.plist" && -f "$new_app/Contents/MacOS/$app_name" ]] \
    || die "$zip does not contain $app_name.app; refusing to install"
  clear_quarantine "$new_app"

  # Quit the running app, then swap.
  quit_app "$app_name" "$bundle_id" "$quit_timeout"

  if [[ -e "$target" || -L "$target" ]]; then
    mv "$target" "$STAGE/previous.app" || die "cannot move the old $target aside; nothing changed"
    if ! mv "$new_app" "$target"; then
      if mv "$STAGE/previous.app" "$target"; then
        die "cannot move the new app to $target; the old app is back in place"
      fi
      KEEP_STAGE=1
      die "cannot move the new app to $target, and putting the old one back failed too.
       The old app is at $STAGE/previous.app; move it to $apps_dir yourself"
    fi
    say "Replaced $target"
  else
    mv "$new_app" "$target" || die "cannot move the new app to $target"
    say "Installed $target"
  fi

  open "$target" </dev/null || die "installed $target, but 'open' failed; open it from Finder"
  say "Opened $app_name $version. Look for its icon in the menu bar."
  say "Done: LiveCaptions $version is in $apps_dir. First run: $repo_url#install"
}

say() { printf '==> %s\n' "$*"; }
die() {
  printf 'install.sh: error: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  if [[ -n "$WORK" ]]; then rm -rf "$WORK"; fi
  if [[ -n "$STAGE" && -z "$KEEP_STAGE" ]]; then rm -rf "$STAGE"; fi
}

check_platform() {
  local os arch arm64 product major
  os="$(uname -s)" || die "uname failed"
  [[ "$os" == Darwin ]] || die "LiveCaptions is a macOS app; this is $os. It needs an Apple Silicon Mac with macOS 26 or later."
  arch="$(uname -m)" || die "uname failed"
  if [[ "$arch" != arm64 ]]; then
    # A shell under Rosetta reports x86_64 on Apple Silicon. Intel Macs have
    # no hw.optional.arm64, so sysctl fails there: that means "not arm64".
    arm64="$(sysctl -n hw.optional.arm64 2>/dev/null)" || arm64=0
    [[ "$arm64" == 1 ]] || die "LiveCaptions needs an Apple Silicon Mac (M1 or later); this Mac is $arch."
  fi
  product="$(sw_vers -productVersion)" || die "sw_vers failed"
  major="${product%%.*}"
  [[ "$major" =~ ^[0-9]+$ ]] || die "cannot read the macOS version from '$product'"
  [[ "$major" -ge 26 ]] || die "LiveCaptions needs macOS 26 or later; this Mac has macOS $product."
  say "Apple Silicon Mac with macOS $product"
}

# curl with time limits and retries. Prints nothing on success; fails with
# the URL and the HTTP status otherwise.
fetch() { # url, output file -> prints the HTTP status
  # Only https, also after redirects. The self-test serves a fake release
  # over plain http on 127.0.0.1: allowed only for a URL that starts there.
  local proto="=https"
  case "$1" in
    http://127.0.0.1:* | http://127.0.0.1/*) proto="=https,http" ;;
  esac
  curl --silent --show-error --location \
    --proto "$proto" --proto-redir "$proto" \
    --connect-timeout 15 --max-time 600 --max-filesize 500000000 \
    --retry 3 --retry-delay 2 \
    --output "$2" --write-out '%{http_code}' "$1" </dev/null
}

download() { # url, output file
  local code
  code="$(fetch "$1" "$2")" || die "download failed: $1"
  case "$code" in
    200) ;;
    404) die "not found (HTTP 404): $1
       Is this a published release? See https://github.com/zerone0x/mac-live-captions/releases" ;;
    *) die "download failed (HTTP $code): $1" ;;
  esac
  [[ -s "$2" ]] || die "downloaded an empty file: $1"
}

latest_version() { # api url -> prints <major>.<minor>.<patch>
  local json code tag tag_re='^v[0-9]+[.][0-9]+[.][0-9]+$'
  json="$(mktemp "${TMPDIR:-/tmp}/livecaptions-latest.XXXXXX")"
  if ! code="$(fetch "$1" "$json")"; then
    rm -f "$json"
    die "cannot reach $1 to find the latest release"
  fi
  case "$code" in
    200) ;;
    403 | 429)
      if grep -qi 'rate limit' "$json"; then
        rm -f "$json"
        die "GitHub API rate limit reached (60 requests an hour without a token).
       Try again later, or name the version, e.g. ... | bash -s -- 0.1.2"
      fi
      rm -f "$json"
      die "GitHub API refused the latest-release lookup (HTTP $code); name the version instead, e.g. ... | bash -s -- 0.1.2"
      ;;
    404)
      rm -f "$json"
      die "no published release found at $1"
      ;;
    *)
      rm -f "$json"
      die "latest-release lookup failed (HTTP $code): $1"
      ;;
  esac
  # The first "tag_name" only (the API's JSON has one).
  tag="$(sed -n -e '/"tag_name"/{' -e 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' -e 'q' -e '}' "$json")"
  rm -f "$json"
  [[ "$tag" =~ $tag_re ]] || die "latest release has an unexpected tag '$tag'"
  printf '%s\n' "${tag#v}"
}

clear_quarantine() { # app path
  local attrs
  attrs="$(xattr -r -l "$1")" || die "cannot read extended attributes of $1"
  case "$attrs" in
    *com.apple.quarantine*)
      xattr -r -d com.apple.quarantine "$1" || die "cannot clear the quarantine flag on $1"
      attrs="$(xattr -r -l "$1")" || die "cannot read extended attributes of $1"
      case "$attrs" in *com.apple.quarantine*) die "the quarantine flag is still set on $1" ;; esac
      say "Cleared the quarantine flag (the app is ad-hoc signed, not notarized)"
      ;;
    *) say "No quarantine flag to clear" ;;
  esac
}

is_running() { # process name -> 0 running, 1 not
  local rc=0
  # Only this user's processes: another user's copy is not ours to quit.
  pgrep -u "$(id -u)" -x "$1" >/dev/null || rc=$?
  case "$rc" in
    0) return 0 ;;
    1) return 1 ;;
    *) die "pgrep failed (exit $rc); cannot tell whether $1 is running" ;;
  esac
}

quit_app() { # process name, bundle id, timeout seconds
  if ! is_running "$1"; then
    return 0
  fi
  say "Quitting the running $1"
  osascript -e "tell application id \"$2\" to quit" >/dev/null </dev/null \
    || die "could not ask $1 to quit. Quit it from its menu bar icon and run this again; nothing changed"
  local waited=0
  while is_running "$1"; do
    if [[ "$waited" -ge "$3" ]]; then
      die "$1 is still running after ${3}s. Quit it from its menu bar icon and run this again; nothing changed"
    fi
    sleep 1
    waited=$((waited + 1))
  done
}

main "$@"
