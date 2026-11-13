# LiveCaptions

Live English captions for any audio on your Mac, shown near the notch.
Speech recognition runs on device with Apple's `SpeechAnalyzer`, so captions
are fast and nothing leaves your Mac.

Status: MVP in progress (see #13). The current scope, what the app does and
what it does not do yet, is [docs/SCOPE.md](docs/SCOPE.md): English live
captions of system audio, on device, no translation and no summaries.

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
and in the bottom position (`overlay-bottom-*.png`).

Each build has a new ad-hoc signature, so macOS may ask for audio permissions
again after you install a newer build.

Artifacts are kept for 14 days. To list the runs for a branch and download
only the screenshots of one run:

```sh
gh run list --repo zerone0x/mac-live-captions --workflow ci.yml --branch <branch>
gh run download <run-id> --repo zerone0x/mac-live-captions --pattern 'overlay-screenshots-*'
```

The manual test checklist for a real Mac is [docs/TESTING.md](docs/TESTING.md).

## Build locally

Needs Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

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
| `make build` | `generate`, then build the ad-hoc signed app into `build/DerivedData`. |
| `make verify` | Check the built bundle with `scripts/verify-app.sh`: menu-bar only, usage strings, arm64, signature with hardened runtime and exactly the expected entitlements, stripped binary. |
| `make package` | `build` and `verify`, then zip the app to `build/LiveCaptions.zip`. |
| `make screenshots` | After a build: render the overlay states to PNG files in `build/screenshots` (the app's `--render-overlay-snapshots` mode). CI uploads them as `overlay-screenshots-<sha>`. |
| `make check-offline` | Fail if networking APIs appear in the sources or remote dependencies in the package manifests (`scripts/check-offline.sh`, `scripts/check-dependencies.sh`). |
| `make check-linked-frameworks` | After a build: fail if the binary links a framework outside the allow-list or imports networking symbols (`scripts/check-linked-frameworks.sh`). |
| `make open` | `generate`, then open the project in Xcode. |
| `make clean` | Remove `build/` and the generated project. |

`CONFIG=Debug make build` builds the Debug configuration instead of Release.
`make verify` and `make package` are meant for Release builds.

The checks themselves have self-tests that CI also runs:
`scripts/check-offline-selftest.sh` and `scripts/verify-app-selftest.sh`.

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
