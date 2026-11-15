# Changelog

All notable changes to LiveCaptions. Each version's section is also the text
of its GitHub Release (`scripts/release-notes.sh`, `docs/DECISIONS.md` 0023).
Versions follow [Semantic Versioning](https://semver.org); the version in
`project.yml` (`MARKETING_VERSION`) must match the release tag.

## [Unreleased]

### Added

- **A one-line installer** (#60):
  `curl -fsSL https://raw.githubusercontent.com/zerone0x/mac-live-captions/main/scripts/install.sh | bash`
  downloads the latest release zip, checks its SHA-256, quits a running
  LiveCaptions, replaces the app in /Applications (keeping the old one if
  anything fails), clears the quarantine flag and opens it. No sudo. Add
  `-s -- <version>` after `bash` for a given version. Releases attach the
  script as `install.sh`; README, Install and the release notes lead with
  it, and the manual DMG and zip steps stay.

## [0.1.2]

An app icon and a DMG to install from.

### Added

- **An app icon** (#53): two caption lines (white finished text, a fading
  grey tail) on a dark panel over a warm peach-to-coral gradient, shown in
  the Dock, Finder and the welcome window. On macOS 26 large sizes appear
  inside the system's frame for icons not made with Icon Composer (#56).

- **A DMG to install from** (#55): each release also ships
  `LiveCaptions-<version>-mac-arm64.dmg` and its `.sha256` file. Opening it
  shows LiveCaptions next to an Applications folder; drag it across, then
  clear the quarantine flag as before (README, Install). The zip stays.

## [0.1.1]

A fix for the first real-Mac report.

### Fixed

- **Captions no longer stop with "Error: Audio input timestamp overlaps or
  precedes prior audio input"** after running for a while (#48). Audio time
  sent to the speech recognizer is now counted in whole samples, and every
  input is checked so it never starts before the previous one ends. If the
  recognizer still fails, a new one continues on the same audio, at most 3
  times per 5 minutes of audio; after that captions stop with a clear message.

### Changed

- The README install steps are now one copy-paste block that downloads the
  release first (#47).

## [0.1.0]

The first release: live English captions of the audio your Mac plays, shown
at the notch, with speech recognition on device. The full scope is
[docs/SCOPE.md](https://github.com/zerone0x/mac-live-captions/blob/v0.1.0/docs/SCOPE.md).

### What it does

- **Captions system audio**: what your Mac plays (calls, videos, browser
  tabs), captured with ScreenCaptureKit.
- **English only, on device.** Apple's `SpeechAnalyzer` with the en-US model.
  Audio and transcripts stay in memory; nothing is recorded, saved or sent.
  The only network use is Apple's one-time English speech model download,
  which you start yourself.
- **Captions at the notch**, in a click-through panel that never takes focus,
  or in a pill under the menu bar on displays without a notch. At most two
  lines; the live tail is lighter and may still change; the overlay collapses
  after 6 seconds without new text.
- **An honest status line** in the menu bar: checking or downloading the
  speech model, waiting for permission, starting, listening, no audio
  playing, reconnecting, stopping, or the error.
- **Start and stop** from the menu bar, the welcome window, or **⌃⌥C** from
  any app (no Accessibility permission needed).
- **Settings**: text size, top (notch) or bottom position, and "Hide overlay
  from screen sharing" (best effort).
- **A welcome window** that walks through the speech model and the Screen &
  System Audio Recording permission. If the app relaunches while macOS is
  still downloading the speech model, captions start by themselves once the
  download finishes (#40); such a download shows no percentage.
- **Debug items**: a scripted demo feed for the overlay and an audio capture
  test.

### Known limitations

- **Ad-hoc signed, not notarized.** Gatekeeper blocks the downloaded app
  until you clear the quarantine flag (README, Install). Each build has a new
  signature, so macOS may ask for permissions again after an update.
- **Apple Silicon and macOS 26 or later only.**
- **English only.** No translation (#10), no other languages.
- **The microphone is not captioned.** It is used only by the
  "Debug: Audio Capture" test.
- **Not yet checked on real hardware in every case.** CI runs in virtual
  machines, which cannot run on-device speech recognition or grant audio
  permissions. The open hardware checks are on
  [#29](https://github.com/zerone0x/mac-live-captions/issues/29).
