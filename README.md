# LiveCaptions

Live English captions for any audio on your Mac, shown near the notch.
Speech recognition runs on device with Apple's `SpeechAnalyzer`, so captions
are fast and nothing leaves your Mac.

Status: early scaffold. The menu-bar app runs, but Start/Stop are
placeholders until transcription lands and the pipeline is wired (see #13).
System audio capture works on its own: use **Debug: Audio Capture** in the
menu to see a live level meter. It needs the Screen & System Audio Recording
permission; after granting it, quit and reopen LiveCaptions.

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
finalized text plus a volatile tail, a two-line wrap, two finalized lines).

Each build has a new ad-hoc signature, so macOS may ask for audio permissions
again after you install a newer build.

## Build locally

Needs Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
make test       # Core package tests (Swift Testing)
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
project.yml       XcodeGen spec
Makefile          build/test commands, shared with CI
scripts/          CI checks
docs/             architecture, decisions, research
```
