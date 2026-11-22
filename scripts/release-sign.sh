#!/usr/bin/env bash
# Sign and notarize the verified app ZIP from the build job. The output
# directory receives the final, stapled ZIP and DMG and their checksums.
set -euo pipefail
umask 077

usage="usage: release-sign.sh <version> <unsigned-dir> <out-dir>"
version="${1:?$usage}"
unsigned="${2:?$usage}"
out="${3:?$usage}"
scripts="$(cd "$(dirname "$0")" && pwd)"
zip="LiveCaptions-$version.zip"
dmg="LiveCaptions-$version-mac-arm64.dmg"

fail() { echo "release-sign: $*" >&2; exit 1; }

for secret in APPLE_SIGNING_P12_BASE64 APPLE_SIGNING_P12_PASSWORD APPLE_NOTARY_APPLE_ID APPLE_NOTARY_PASSWORD APPLE_TEAM_ID; do
  [[ -n "${!secret:-}" ]] || fail "$secret must be set in the macos-release environment"
done
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "expected a version like 0.1.2"
[[ "$APPLE_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || fail "invalid Apple Team ID"
[[ -s "$unsigned/$zip" && -s "$unsigned/$zip.sha256" ]] || fail "missing verified build artifact"
"$scripts/release-checksum.sh" "$unsigned/$zip.sha256" "$zip" >/dev/null
(cd "$unsigned" && shasum -a 256 -c "$zip.sha256")

work="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/livecaptions-sign.XXXXXXXX")"
keychain="$work/signing.keychain-db"
original_keychains=()
keychain_created=false
cleanup() {
  if $keychain_created; then
    security list-keychains -d user -s ${original_keychains[@]+"${original_keychains[@]}"} || true
    security delete-keychain "$keychain" || true
  fi
  rm -rf -- "$work"
}
trap cleanup EXIT

notary=(--apple-id "$APPLE_NOTARY_APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_NOTARY_PASSWORD")
unset APPLE_NOTARY_APPLE_ID APPLE_NOTARY_PASSWORD

wait_for_existing_app() {
  local ids submission status pending first_poll=true response="$work/existing-notary.json"
  local deadline=$((SECONDS + 4 * 60 * 60))
  IFS=, read -r -a ids <<<"$RESUME_APP_SUBMISSIONS"
  echo "release-sign: checking existing App submissions ($RESUME_APP_SUBMISSIONS)"
  while ((SECONDS < deadline)); do
    pending=false
    for submission in "${ids[@]}"; do
      if ! "$scripts/with-timeout.sh" 45 xcrun notarytool info "$submission" "${notary[@]}" --output-format json >"$response"; then
        echo "release-sign: could not check App submission $submission; will retry" >&2
        pending=true
        continue
      fi
      status="$(plutil -extract status raw "$response")"
      if $first_poll; then
        echo "release-sign: existing App submission $submission is $status"
      fi
      case "$status" in
        Accepted)
          echo "release-sign: Accepted existing App submission ($submission)"
          return 0
          ;;
        'In Progress') pending=true ;;
      esac
    done
    if ! $pending; then
      for submission in "${ids[@]}"; do
        xcrun notarytool log "$submission" "${notary[@]}" >&2 || true
      done
      fail 'none of the existing App submissions was accepted'
    fi
    first_poll=false
    sleep 60
  done
  fail "existing App submissions still pending ($RESUME_APP_SUBMISSIONS)"
}

resume_app="${RESUME_APP_SUBMISSIONS:-}"
if [[ -n "$resume_app" ]]; then
  uuid='[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
  [[ "$resume_app" =~ ^$uuid(,$uuid)*$ ]] || fail 'invalid existing App submission IDs'
  [[ "${RESUME_APP_CDHASH:-}" =~ ^[0-9a-f]{40}$ ]] || fail 'expected the existing App CDHash'
  wait_for_existing_app
fi

# The runner needs the Apple G2 intermediate when embedding the certificate
# chain in a signature. Keep it and the private key in the temporary keychain.
ca="$work/DeveloperIDG2CA.cer"
curl --fail --silent --show-error --proto '=https' --max-time 30 --retry 3 \
  https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer -o "$ca"
ca_digest='f16cd3c54c7f83cea4bf1a3e6a0819c8aaa8e4a1528fd144715f350643d2df3a'
printf '%s  %s\n' "$ca_digest" "$ca" | shasum -a 256 -c
printf '%s' "$APPLE_SIGNING_P12_BASE64" | base64 --decode -o "$work/identity.p12"
keychain_password="$(openssl rand -hex 32)"
keychains="$(security list-keychains -d user)"
while IFS= read -r entry; do
  [[ -n "$entry" ]] || continue
  entry="${entry#*\"}"
  original_keychains+=("${entry%\"}")
done <<<"$keychains"
security create-keychain -p "$keychain_password" "$keychain"
keychain_created=true
# Keep the keychain unlocked through the app's notarization and DMG signing.
security set-keychain-settings -lut 7200 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$work/identity.p12" -k "$keychain" -f pkcs12 \
  -P "$APPLE_SIGNING_P12_PASSWORD" -T /usr/bin/codesign
unset APPLE_SIGNING_P12_BASE64 APPLE_SIGNING_P12_PASSWORD
rm -- "$work/identity.p12"
installed_ca="$(security find-certificate -a -c 'Developer ID Certification Authority' -Z "$keychain" 2>/dev/null || true)"
if ! grep -Fqi "SHA-256 hash: $ca_digest" <<<"$installed_ca"; then
  security add-certificates -k "$keychain" "$ca"
fi
security set-key-partition-list -S apple-tool:,apple: -s -k "$keychain_password" "$keychain" >/dev/null
unset keychain_password

security list-keychains -d user -s "$keychain" ${original_keychains[@]+"${original_keychains[@]}"}

identity="$(security find-identity -v -p codesigning "$keychain" |
  awk -v team="$APPLE_TEAM_ID" 'index($0, "\"Developer ID Application: ") && index($0, " (" team ")\"") { print $2 }')"
[[ "$identity" =~ ^[0-9A-F]{40}$ ]] || fail "expected one valid Developer ID Application identity for $APPLE_TEAM_ID"

notarize() {
  local submission status response="$work/notary.json" checkpoint="${2:-}"
  xcrun notarytool submit "$1" "${notary[@]}" --output-format json >"$response"
  submission="$(plutil -extract id raw "$response")"
  if [[ -n "$checkpoint" ]]; then
    printf '%s\n' "$submission" >"$checkpoint"
  fi
  echo "release-sign: awaiting notarization of $(basename "$1") ($submission)"
  if ! xcrun notarytool wait "$submission" "${notary[@]}" --timeout 90m --output-format json >"$response"; then
    xcrun notarytool info "$submission" "${notary[@]}" --output-format json >&2 || true
    fail "notarytool wait failed for $submission"
  fi
  status="$(plutil -extract status raw "$response")"
  if [[ "$status" != Accepted ]]; then
    xcrun notarytool log "$submission" "${notary[@]}" >&2 || true
    fail "notarization of $(basename "$1") returned $status"
  fi
  echo "release-sign: Accepted $(basename "$1") ($submission)"
}

app="$work/app/LiveCaptions.app"
ditto -x -k "$unsigned/$zip" "$work/app"
"$scripts/verify-app.sh" "$app"
codesign --force --sign "$identity" --keychain "$keychain" --timestamp --options runtime \
  --entitlements "$scripts/../App/LiveCaptions.entitlements" "$app"
signature="$(codesign -d --verbose=4 "$app" 2>&1)"
grep -Fxq "TeamIdentifier=$APPLE_TEAM_ID" <<<"$signature" || fail "unexpected App signature team"
grep -q '^Timestamp=' <<<"$signature" || fail "missing App signature timestamp"
"$scripts/verify-app.sh" "$app"

if [[ -n "$resume_app" ]]; then
  grep -Fxq "CDHash=$RESUME_APP_CDHASH" <<<"$signature" || fail 'App CDHash differs from the existing submission'
else
  # Apple accepts ZIP submissions but tickets are attached to the app inside.
  ditto -c -k --sequesterRsrc --keepParent "$app" "$work/notary.zip"
  notarize "$work/notary.zip"
fi
xcrun stapler staple "$app"
xcrun stapler validate "$app"

"$scripts/release-package.sh" "$version" "$app" "$out"
ditto -x -k "$out/$zip" "$work/final-zip"
xcrun stapler validate "$work/final-zip/LiveCaptions.app"

"$scripts/release-dmg.sh" "$version" "$app" "$out"
codesign --sign "$identity" --keychain "$keychain" --timestamp "$out/$dmg"
(cd "$out" && shasum -a 256 "$dmg" >"$dmg.sha256")
notarize "$out/$dmg" "$out/dmg-notary-id.txt"
xcrun stapler staple "$out/$dmg"
xcrun stapler validate "$out/$dmg"
codesign --verify --strict "$out/$dmg"
# Signing and stapling change the DMG bytes. Replace the packaging checksum.
(cd "$out" && shasum -a 256 "$dmg" >"$dmg.sha256" && shasum -a 256 -c "$dmg.sha256")
