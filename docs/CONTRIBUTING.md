# Contributing to LiveCaptions

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

## Project docs

- [Current scope](SCOPE.md)
- [Architecture](ARCHITECTURE.md)
- [Decisions](DECISIONS.md)
- [Testing](TESTING.md)
- [Original product brief (Chinese)](../PRD.md)

## Releasing (maintainers)

1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`.
   Add a `## [<version>]` section to `CHANGELOG.md` and update the README
   download link in the same PR.
2. After it merges, tag the merge commit on `main` and push the release tag.
3. The [Release workflow](../.github/workflows/release.yml) checks that the tag
   equals `MARKETING_VERSION` and is on `main`, runs the tests, builds and
   verifies the Release app. The signing job uses a temporary keychain to
   sign the app and DMG with Developer ID, notarizes both with Apple, and
   staples the tickets before computing the final checksums. The GitHub
   Release is created after signed packaging and installer checks pass.

Run it by hand (Actions → Release → Run workflow, or
`gh workflow run release.yml --ref <branch>`) for a dry run: it builds and
packages, uploads the files as a workflow artifact and publishes nothing.
To test signing and notarization without publishing, run
`gh workflow run release.yml --ref main -f signed=true`.

The `macos-release` GitHub Actions environment allows `main` and `v*` tags.
It needs these environment secrets for the Apple team used by the workflow.

- `APPLE_SIGNING_P12_BASE64` and `APPLE_SIGNING_P12_PASSWORD` contain the
  Base64-encoded Developer ID Application PKCS#12 file and its import password.
- `APPLE_NOTARY_APPLE_ID` and `APPLE_NOTARY_PASSWORD` contain the Apple Account
  on that team and its [app-specific password](https://support.apple.com/102654).
