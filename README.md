# LiveCaptions

Live English captions for any audio on your Mac, shown near the notch.
Speech recognition runs on device with Apple's `SpeechAnalyzer`, so captions
are fast and nothing leaves your Mac.

Status: v0.1.0, the first release ([CHANGELOG.md](CHANGELOG.md); to install
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

Needs an Apple Silicon Mac with macOS 26 or later.

1. Download `LiveCaptions-<version>.zip` and `LiveCaptions-<version>.zip.sha256`
   from the [latest release](https://github.com/zerone0x/mac-live-captions/releases/latest).
   The release notes are the matching section of [CHANGELOG.md](CHANGELOG.md).
2. In Terminal, in the folder with the two files, check the zip. It must print
   `LiveCaptions-<version>.zip: OK`; if it does not, delete the zip and do not
   open it.

   ```sh
   shasum -a 256 -c LiveCaptions-0.1.0.zip.sha256
   ```

3. Unzip it (or double-click it in Finder) and move the app to Applications:

   ```sh
   ditto -x -k LiveCaptions-0.1.0.zip .
   mv LiveCaptions.app /Applications/
   ```

4. The app is ad-hoc signed and not notarized (there is no Apple Developer ID
   yet), so Gatekeeper blocks it as downloaded ("cannot be opened" or "is
   damaged"). Clear the quarantine flag, then open it:

   ```sh
   xattr -dr com.apple.quarantine /Applications/LiveCaptions.app
   open /Applications/LiveCaptions.app
   ```

5. First run. The app has no Dock icon: look for the captions icon in the menu
   bar. The welcome window (also in the menu as **Welcome and Setup…**) walks
   through two things:
   - **English speech model.** Click **Download English Speech Model**. macOS
     downloads it once from Apple; this is the only time LiveCaptions uses the
     network. The menu shows the progress.
   - **Screen & System Audio Recording.** Click **Ask for Permission** and allow
     LiveCaptions in System Settings → Privacy & Security → Screen & System
     Audio Recording, then click **Relaunch**: macOS applies the permission
     only to a new process.

   Then **Start Captions** (or ⌃⌥C from any app) and play something with
   English speech. The microphone permission is asked for only if you run
   **Debug: Audio Capture** with the microphone; captions never use it.
6. Updating: quit LiveCaptions, replace the app in /Applications with the new
   one and clear the quarantine flag again. Each release has a new ad-hoc
   signature, so macOS may ask for the permissions again.

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
   verifies the Release app, zips it, writes the `.sha256` file and creates
   the GitHub Release with the changelog section as its notes.

Run it by hand (Actions → Release → Run workflow, or
`gh workflow run release.yml --ref <branch>`) for a dry run: it builds and
packages, uploads the files as a workflow artifact and publishes nothing.
Details: [docs/DECISIONS.md](docs/DECISIONS.md) 0023.

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
