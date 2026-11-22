# LiveCaptions

Live English captions for any audio on your Mac, shown near the notch.
Speech recognition runs on device with Apple's `SpeechAnalyzer`, so captions
are fast and nothing leaves your Mac.

Status: v0.1.3 ([CHANGELOG.md](CHANGELOG.md); to install
it, see [Install](#install)). The current scope, what the app does and what
it does not do yet, is [docs/SCOPE.md](docs/SCOPE.md): English live captions
of system audio, on device, no translation and no summaries.

Start Captions in the menu bar (or ⌃⌥C
from any app) captions the audio your Mac plays, at the notch. The menu says
what is really happening: checking or downloading the speech model, waiting
for permission, listening, no audio playing, or the error.

What it needs:

- The **Screen & System Audio Recording** permission. After granting it,
  relaunch LiveCaptions (the menu and the welcome window have a button).
- Apple's **English speech model**. macOS downloads it once from Apple when
  you click "Download English Speech Model". That download is the only time
  LiveCaptions uses the network.

Nothing is saved: no audio, no transcripts. Only the settings (text size,
position, hide from screen sharing) are stored as preferences. The
microphone is not captioned yet; it is only in **Debug: Audio Capture**.

Requirements: Apple Silicon Mac, macOS 26 or later.

- Current product scope (source of truth): [docs/SCOPE.md](docs/SCOPE.md)
- Original long-term vision, background only (Chinese): [PRD.md](PRD.md)
- Architecture and module boundaries: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- Decisions log: [docs/DECISIONS.md](docs/DECISIONS.md)

## Install

**[Download LiveCaptions v0.1.3 (.dmg)](https://github.com/zerone0x/mac-live-captions/releases/download/v0.1.3/LiveCaptions-0.1.3-mac-arm64.dmg)** for Apple Silicon Macs running macOS 26 or later.

1. Open the DMG and drag **LiveCaptions** to **Applications**. Quit an older
   copy before replacing it.
2. Eject the DMG and open LiveCaptions from Applications. Starting with
   v0.1.3, the app and DMG are Developer ID signed and notarized by Apple.
3. Look for the captions icon in the menu bar and follow the first-run steps
   below.

The [release page](https://github.com/zerone0x/mac-live-captions/releases/tag/v0.1.3)
also has the ZIP and SHA-256 files. To check the DMG, put it and its
`.sha256` file in the same folder and run
`shasum -a 256 -c LiveCaptions-0.1.3-mac-arm64.dmg.sha256`.

### Install or update from Terminal

```sh
curl -fsSL https://raw.githubusercontent.com/zerone0x/mac-live-captions/main/scripts/install.sh | bash
```

The [installer](scripts/install.sh) downloads the latest release ZIP,
checks its SHA-256, quits LiveCaptions if it is running, and replaces the
app in Applications. An existing copy is restored if replacement fails.
To pin a release, replace `| bash` with `| bash -s -- 0.1.3`.

### First run

Open **Welcome and Setup…** from the menu bar icon.

1. Click **Download English Speech Model**. macOS downloads it once from
   Apple.
2. Click **Ask for Permission**, allow LiveCaptions in System Settings →
   Privacy & Security → Screen & System Audio Recording, then click
   **Relaunch**. macOS may ask again when you switch from an older ad-hoc
   signed build.
3. Click **Start Captions**, or press ⌃⌥C, and play something with English
   speech.

To uninstall, quit LiveCaptions and delete `/Applications/LiveCaptions.app`.
The settings are in `defaults read dev.trine.LiveCaptions` (`defaults delete
dev.trine.LiveCaptions` removes them).

### Report a problem

[Open an issue](https://github.com/zerone0x/mac-live-captions/issues/new) with:

- the app version (`defaults read /Applications/LiveCaptions.app/Contents/Info.plist CFBundleShortVersionString`),
  your Mac model and macOS version (Apple menu → About This Mac);
- the menu's status line and detail text (or a screenshot of the menu);
- what you did, what you expected and what happened instead (for example:
  which app was playing audio, built-in display or external, notch or not).

Known limitations are in [CHANGELOG.md](CHANGELOG.md); hardware checks still
open are on [#29](https://github.com/zerone0x/mac-live-captions/issues/29).
LiveCaptions saves no transcripts or audio, so there is nothing to attach
beyond what you describe; leave out anything private you saw in captions.

### Releasing (maintainers)

1. Bump `MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION`) in `project.yml`
   and add a `## [<version>]` section to `CHANGELOG.md` in a PR. CI fails if
   the version has no changelog section (`scripts/release-selftest.sh`).
2. After it merges, tag the merge commit on `main` and push the tag:
   `git tag v0.1.0 && git push origin v0.1.0`.
3. The [Release workflow](.github/workflows/release.yml) checks that the tag
   equals `MARKETING_VERSION` and is on `main`, runs the tests, builds and
   verifies the Release app. The signing job uses a temporary keychain to sign
   the app and DMG with Developer ID, notarizes both with Apple, and staples
   both tickets before computing the final checksums. The GitHub Release is
   created only after signed packaging and installer checks pass.

Run it by hand (Actions → Release → Run workflow, or
`gh workflow run release.yml --ref <branch>`) for a dry run: it builds and
packages, uploads the files as a workflow artifact and publishes nothing. To
exercise signing and notarization without publishing, use
`gh workflow run release.yml --ref main -f signed=true`.

The `macos-release` GitHub Actions environment allows the `main` branch and
`v*` tags. Configure these environment secrets for the Apple team used in the
workflow:

- `APPLE_SIGNING_P12_BASE64` and `APPLE_SIGNING_P12_PASSWORD`: the Developer ID
  Application identity exported as a password-protected PKCS#12 file, encoded
  in Base64, and its import password.
- `APPLE_NOTARY_APPLE_ID` and `APPLE_NOTARY_PASSWORD`: the Apple Account on that
  team and its [app-specific password](https://support.apple.com/102654).

## Try a CI build

Every PR and every push to `main` builds the app on GitHub Actions.

1. Open the [CI workflow](https://github.com/zerone0x/mac-live-captions/actions/workflows/ci.yml), pick a green run,
   and download the `LiveCaptions-<sha>` artifact from the run's summary page.
   With the GitHub CLI:
   `gh run download <run-id> --repo zerone0x/mac-live-captions`
2. Unzip it. GitHub wraps the artifact in a zip, so you get
   `LiveCaptions.zip`; unzip that too to get `LiveCaptions.app`.
3. The build is ad-hoc signed, not notarized, so Gatekeeper blocks it as
   downloaded. Clear the quarantine flag, then open it:

   ```sh
   xattr -dr com.apple.quarantine LiveCaptions.app
   open LiveCaptions.app
   ```

4. The app has no Dock icon. Look for the captions icon in the menu bar.
5. To see the caption overlay without audio, choose **Debug: Demo Captions** in
   the menu. It plays a short scripted English feed at the notch (or in a pill
   under the menu bar on displays without a notch).

   To start the demo on launch (it repeats until stopped), pass
   `--demo-captions`:
   `LiveCaptions.app/Contents/MacOS/LiveCaptions --demo-captions`.

Each CI run also uploads `overlay-screenshots-<sha>`: PNG renders of the
overlay in notch and pill style for fixed states (one finalized line,
finalized text plus a volatile tail, a two-line wrap, two finalized lines),
plus the two-line wrap at the extra large text size (`overlay-*-xl-*.png`)
and in the bottom position (`overlay-bottom-*.png`), the menu status states
(`menu-*.png`), Settings and the welcome window. `live-screenshots-<sha>`
has screenshots of the running app with the demo captions. What each file
shows and how to read them: [docs/TESTING.md](docs/TESTING.md#screenshots-from-ci).

Each build has a new ad-hoc signature, so macOS may ask for audio permissions
again after you install a newer build.

Artifacts are kept for 14 days. To list the runs for a branch and download
only the screenshots of one run:

```sh
gh run list --repo zerone0x/mac-live-captions --workflow ci.yml --branch <branch>
gh run download <run-id> --repo zerone0x/mac-live-captions --pattern '*-screenshots-*'
```

The manual test checklist for a real Mac is [docs/TESTING.md](docs/TESTING.md).

## Build locally

Needs Xcode 26 (CI pins 26.6, Swift 6.3) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
make            # check-offline, test and build (the default target, `all`)
make package    # build, verify the bundle, zip to build/LiveCaptions.zip
make open       # generate the project and open it in Xcode
```

The built app is at `build/DerivedData/Build/Products/Release/LiveCaptions.app`.
`LiveCaptions.xcodeproj` is generated from `project.yml`; edit `project.yml`, not
the project file. CI runs the same targets (`.github/workflows/ci.yml`).

| Target | What it does |
|---|---|
| `make all` (default) | `check-offline`, `test` and `build`. |
| `make generate` | Generate `LiveCaptions.xcodeproj` from `project.yml` with XcodeGen. |
| `make test` | All package tests (Swift Testing): `test-core`, `test-audio`, `test-speech`. |
| `make test-core` | Core logic tests. Pure Swift, no hardware. |
| `make test-audio` | AudioAdapter tests: PCM conversion with AVFoundation, no capture hardware. |
| `make test-speech` | SpeechAdapter tests. The real-audio test needs `say` and the en-US speech model; it skips with a printed reason when they are missing, and `LIVECAPTIONS_SKIP_REAL_AUDIO=1` skips it on purpose. |
| `make build` | `generate`, then build the ad-hoc signed app into `build/DerivedData`. Warnings are errors (`WARNINGS_AS_ERRORS=NO` turns that off locally); the log goes through `xcbeautify` when it is installed. |
| `make verify` | Check the built bundle with `scripts/verify-app.sh`: menu-bar only, usage strings, arm64, signature with hardened runtime and exactly the expected entitlements, stripped binary. |
| `make package` | `build` and `verify`, then zip the app to `build/LiveCaptions.zip`. |
| `make screenshots` | After a build: render the overlay states to PNG files in `build/screenshots` (the app's `--render-overlay-snapshots` mode). CI uploads them as `overlay-screenshots-<sha>`. |
| `make check-offline` | Fail if networking APIs appear in the sources or remote dependencies in the package manifests (`scripts/check-offline.sh`, `scripts/check-dependencies.sh`). |
| `make check-linked-frameworks` | After a build: fail if the binary links a framework outside the allow-list or imports networking symbols (`scripts/check-linked-frameworks.sh`). |
| `make format` | Reformat the Swift sources with swift-format (part of the Swift toolchain; config in `.swift-format`). |
| `make format-check` | Fail if a Swift source is not formatted (`swift format lint --strict`). CI runs it. |
| `make open` | `generate`, then open the project in Xcode. |
| `make clean` | Remove `build/` and the generated project. |

`CONFIG=Debug make build` builds the Debug configuration instead of Release.
`make verify` and `make package` are meant for Release builds.

The checks themselves have self-tests that CI also runs:
`scripts/check-offline-selftest.sh`, `scripts/verify-app-selftest.sh` and
`scripts/release-selftest.sh`.

## Layout

```
App/              menu-bar app target (thin SwiftUI/AppKit glue)
Packages/Core/    Swift package with the testable logic and pipeline protocols
Packages/SpeechAdapter/  on-device speech recognition (SpeechAnalyzer, en-US)
Packages/AudioAdapter/   PCM conversion for audio capture (AVFoundation)
project.yml       XcodeGen spec
Makefile          build/test commands, shared with CI
scripts/          offline, dependency, linked-framework and bundle checks (CI)
docs/             scope, architecture, decisions, manual testing, research
PRD.md            original long-term vision (Chinese), background only
```
