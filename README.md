# LiveCaptions

Live English captions for any audio on your Mac, shown near the notch.
Speech recognition runs on device with Apple's `SpeechAnalyzer`, so captions
are fast and nothing leaves your Mac.

Status: MVP in progress (see #13). Start Captions in the menu bar (or ⌃⌥C
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

- Product requirements: [PRD.md](PRD.md)
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
plus the two-line wrap at the extra large text size (`overlay-*-xl-*.png`).

Each build has a new ad-hoc signature, so macOS may ask for audio permissions
again after you install a newer build.

The manual test checklist for a real Mac is [docs/TESTING.md](docs/TESTING.md).

## Build locally

Needs Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
make test       # Core and SpeechAdapter package tests (Swift Testing)
make build      # generate LiveCaptions.xcodeproj and build the app
make package    # build, verify the bundle, zip to build/LiveCaptions.zip
make open       # generate the project and open it in Xcode
```

The built app is at `build/DerivedData/Build/Products/Release/LiveCaptions.app`.
`LiveCaptions.xcodeproj` is generated from `project.yml`; edit `project.yml`, not
the project file.

## Layout

```
App/              menu-bar app target (thin SwiftUI/AppKit glue)
Packages/Core/    Swift package with the testable logic and pipeline protocols
Packages/SpeechAdapter/  on-device speech recognition (SpeechAnalyzer, en-US)
project.yml       XcodeGen spec
Makefile          build/test commands, shared with CI
scripts/          CI checks
docs/             architecture, decisions, research
```
