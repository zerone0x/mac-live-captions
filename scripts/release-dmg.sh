#!/usr/bin/env bash
# Builds the drag-to-Applications DMG of a verified Release build, writes its
# SHA-256 checksum file, then mounts the DMG read-only and re-verifies what a
# user gets (docs/DECISIONS.md 0026).
#
#   scripts/release-dmg.sh <version> path/to/LiveCaptions.app <out-dir>
#
# Writes <out-dir>/LiveCaptions-<version>-mac-arm64.dmg and its .sha256 file
# (electron-builder's "<App>-mac-<arch>.<ext>" naming, with the version). The
# image holds LiveCaptions.app and an "Applications" link to /Applications,
# volume "LiveCaptions <version>", compressed UDZO, with a fixed Finder
# window layout (scripts/release-dmg-layout.py). dmgbuild comes from a
# throw-away venv, pinned with hashes in scripts/release-dmg-requirements.txt.
#
# macOS only (hdiutil, diskutil, ditto, shasum, codesign) and needs Python
# 3.10 or later (PYTHON overrides python3). Fails if anything is off,
# including an existing DMG. Every hdiutil call runs under
# scripts/with-timeout.sh and the image is always detached on exit.
set -euo pipefail

fail() { echo "release-dmg: $*" >&2; exit 1; }

usage="usage: release-dmg.sh <version> path/to/LiveCaptions.app <out-dir>"
version="${1:?$usage}"
app="${2:?$usage}"
out="${3:?$usage}"
scripts="$(cd "$(dirname "$0")" && pwd)"
timeout="$scripts/with-timeout.sh"
python="${PYTHON:-python3}"

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version '$version' is not <major>.<minor>.<patch>"
[[ -d "$app" ]] || fail "missing app bundle: $app"
[[ "$(basename "$app")" == "LiveCaptions.app" ]] || fail "expected LiveCaptions.app, got $(basename "$app")"
app="$(cd "$app" && pwd)"

name="LiveCaptions-$version-mac-arm64.dmg"
volume_name="LiveCaptions $version"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
dmg="$out/$name"
[[ ! -e "$dmg" ]] || fail "$dmg already exists"
[[ ! -e "$dmg.sha256" ]] || fail "$dmg.sha256 already exists"

work="$(mktemp -d)"
mnt="$work/mnt"
mounted=0
cleanup() {
  local rc=$?
  if ((mounted)); then
    if ! "$timeout" 60 hdiutil detach -quiet "$mnt" && ! "$timeout" 60 hdiutil detach -force -quiet "$mnt"; then
      # Never rm -rf a directory that still has the image mounted in it.
      echo "release-dmg: could not detach $mnt; left $work in place" >&2
      exit 1
    fi
  fi
  rm -rf "$work"
  exit "$rc"
}
trap cleanup EXIT

# dmgbuild in a throw-away venv: exact versions, hashes required, wheels only.
"$python" -I -c 'import sys; sys.exit(sys.version_info < (3, 10))' \
  || fail "$python is older than 3.10 (dmgbuild needs 3.10+): $("$python" --version 2>&1)"
"$python" -I -m venv "$work/venv" || fail "cannot make a venv with $python"
"$timeout" 300 "$work/venv/bin/python" -I -m pip install --quiet --disable-pip-version-check \
  --require-hashes --only-binary=:all: -r "$scripts/release-dmg-requirements.txt" \
  || fail "cannot install dmgbuild from scripts/release-dmg-requirements.txt"
layout=("$work/venv/bin/python" -I "$scripts/release-dmg-layout.py")

"$timeout" 600 "${layout[@]}" build "$volume_name" "$app" "$dmg" || fail "dmgbuild failed"
[[ -s "$dmg" ]] || fail "no DMG at $dmg"
# A UDIF disk image ends with a 512-byte trailer that starts with "koly".
[[ "$(tail -c 512 "$dmg" | head -c 4)" == koly ]] || fail "$dmg is not a UDIF disk image"

# The image itself: its internal checksums verify and it is compressed UDZO.
"$timeout" 300 hdiutil verify -quiet "$dmg" || fail "hdiutil verify failed for $dmg"
"$timeout" 120 hdiutil imageinfo -plist "$dmg" >"$work/imageinfo.plist" || fail "hdiutil imageinfo failed"
format="$(plutil -extract Format raw "$work/imageinfo.plist")" || fail "no Format in hdiutil imageinfo"
[[ "$format" == "UDZO" ]] || fail "image format is $format, expected UDZO"

(cd "$out" && shasum -a 256 "$name" >"$name.sha256")
"$scripts/release-checksum.sh" "$dmg.sha256" "$name" >/dev/null || fail "checksum does not verify"

# Check what a user mounts, not only what we put in.
mkdir "$mnt"
mounted=1
"$timeout" 120 hdiutil attach -readonly -nobrowse -noautoopen -noverify -mountpoint "$mnt" "$dmg" >/dev/null \
  || fail "cannot attach $dmg read-only"
diskutil info -plist "$mnt" >"$work/volume.plist" || fail "diskutil info failed for $mnt"
[[ "$(plutil -extract VolumeName raw "$work/volume.plist")" == "$volume_name" ]] \
  || fail "volume name is not '$volume_name'"
[[ "$(plutil -extract WritableVolume raw "$work/volume.plist")" == "false" ]] \
  || fail "the volume is mounted writable"

entries="$(cd "$mnt" && ls)"
[[ "$entries" == $'Applications\nLiveCaptions.app' ]] \
  || fail "DMG must show only Applications and LiveCaptions.app, has: $(tr '\n' ' ' <<<"$entries")"
[[ -L "$mnt/Applications" ]] || fail "Applications is not a symlink"
link="$(readlink "$mnt/Applications")"
[[ "$link" == "/Applications" ]] || fail "Applications points to '$link', expected /Applications"
[[ -d "$mnt/LiveCaptions.app" && ! -L "$mnt/LiveCaptions.app" ]] || fail "LiveCaptions.app is not a directory"
cmp -s "$mnt/.VolumeIcon.icns" "$app/Contents/Resources/AppIcon.icns" \
  || fail "volume icon is missing or is not the app's AppIcon.icns"
"${layout[@]}" check "$mnt" || fail "Finder layout is wrong"

dmg_app="$mnt/LiveCaptions.app"
"$scripts/verify-app.sh" "$dmg_app" || fail "app in the DMG does not verify"
"$scripts/check-linked-frameworks.sh" "$dmg_app" || fail "app in the DMG links unexpected frameworks"
PROJECT_YML="$scripts/../project.yml" "$scripts/release-version.sh" "v$version" "$dmg_app" >/dev/null \
  || fail "app in the DMG has the wrong version"
# Same signed code as the app we verified before packaging.
cdhash() { codesign -d --verbose=4 "$1" 2>&1 | sed -n 's/^CDHash=//p'; }
want="$(cdhash "$app")"
got="$(cdhash "$dmg_app")"
[[ -n "$want" && "$want" == "$got" ]] || fail "app in the DMG has CDHash '$got', expected '$want'"

"$timeout" 60 hdiutil detach -quiet "$mnt" || fail "cannot detach $mnt"
mounted=0

echo "release-dmg: OK $dmg ($(cut -d' ' -f1 <"$dmg.sha256"))"
