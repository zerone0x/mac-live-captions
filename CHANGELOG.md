# Changelog

All notable changes to LiveCaptions. Each version's section is also the text
of its GitHub Release (`scripts/release-notes.sh`, `docs/DECISIONS.md` 0023).
Versions follow [Semantic Versioning](https://semver.org); the version in
`project.yml` (`MARKETING_VERSION`) must match the release tag.

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
  after 6 seconds of silence.
- **An honest status line** in the menu bar: checking or downloading the
  speech model, waiting for permission, starting, listening, no audio
  playing, reconnecting, stopping, or the error.
- **Start and stop** from the menu bar, the welcome window, or **⌃⌥C** from
  any app (no Accessibility permission needed).
- **Settings**: text size, top (notch) or bottom position, and "Hide overlay
  from screen sharing" (best effort).
- **A welcome window** that walks through the speech model and the Screen &
  System Audio Recording permission.
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
