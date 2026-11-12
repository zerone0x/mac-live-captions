# Decisions

Numbered, append-only. Add a new entry instead of rewriting an old one; mark
superseded entries with "Superseded by NNNN".

Format: number, title, date, context, decision, consequences.

## 0001: XcodeGen project, Core logic in a local Swift package

2026-11-12 · #6

**Context.** Agents work without a Mac, so every change is reviewed as text and
compiled only in CI. Hand-edited `.pbxproj` files create noisy diffs and merge
conflicts. A pure SwiftPM executable cannot cleanly produce an app bundle with
Info.plist, entitlements and signing.

**Decision.** `project.yml` (XcodeGen) describes the app target; the generated
`LiveCaptions.xcodeproj` is git-ignored. All testable logic lives in the local
package `Packages/Core` (product and module `LiveCaptionsCore`; the module is
not called `Core` to avoid a vague, collision-prone import name). Tests use
Swift Testing.

**Consequences.** Contributors need `brew install xcodegen`. The App target
stays thin and has no unit tests of its own.

## 0002: Platform: macOS 26+, Apple Silicon only, Swift 6

2026-11-12 · #6

**Context.** On-device recognition with `SpeechAnalyzer`/`SpeechTranscriber`
needs macOS 26. Murmo-like latency depends on Apple Silicon.

**Decision.** Deployment target macOS 26.0, `ARCHS = arm64`, Swift 6 language
mode with complete strict concurrency. CI runs on GitHub's `macos-26` runner
with Xcode 26.

**Consequences.** Intel Macs and older macOS versions are unsupported.

## 0003: Captions are English only and fully on device

2026-11-12 · #6, #13

**Context.** The owner's goal is a Murmo-like MVP: low latency comes from
on-device processing; cloud services add too much delay. Scope for the MVP is
English live captions with no translation.

**Decision.** Recognition uses `SpeechTranscriber` with the en-US locale. The
pipeline is AudioSource → Transcriber → CaptionStore → Overlay; there is no
translation stage. Core and App sources must not use networking APIs;
`scripts/check-offline.sh` enforces this in CI.

**Consequences.** Other languages and translation need a new decision. Any
future network feature must live outside the caption path and be opt-in.

## 0004: Unsandboxed, hardened runtime, ad-hoc signed builds

2026-11-12 · #6

**Context.** There is no Apple Developer team in CI yet, and the app is not
headed for the Mac App Store. System audio capture and the microphone need
TCC permissions either way.

**Decision.** The app is not sandboxed. Hardened runtime is on (ready for
notarization later) with the `com.apple.security.device.audio-input`
entitlement. CI builds are ad-hoc signed (`CODE_SIGN_IDENTITY = -`).
Info.plist carries `LSUIElement` (menu bar only) and usage strings for audio
capture, microphone and speech recognition.

**Consequences.** Downloaded CI builds are quarantined by Gatekeeper and must be
cleared with `xattr` (see README). Because each ad-hoc build has a new code
signature, macOS may ask for permissions again after every update. Real
signing and notarization come with release packaging (#12).

## 0005: Speech adapter in its own local package

2026-11-12 · #8

**Context.** The `Transcriber` implementation needs the Speech, AVFoundation
and CoreMedia frameworks, which Core must not import (ARCHITECTURE rule 3).
ARCHITECTURE put platform adapters in the App target, but the App target has
no tests, and #8 asks for a test that runs real audio through
`SpeechAnalyzer`.

**Decision.** The speech adapter lives in a second local package,
`Packages/SpeechAdapter` (product and module `LiveCaptionsSpeech`), which
depends on Core. It holds `SpeechAnalyzerTranscriber` (the `Transcriber`),
`SystemSpeechAssets` (the `SpeechAssetProvider` over `AssetInventory`) and the
audio converter, plus their tests. The app target links it (`project.yml`).
Everything that does not need the Speech framework (segment IDs, the caption
store, the audio timeline, asset states) stays in Core. `make test` runs both
packages; `check-offline.sh` scans every package.

**Consequences.** The speech code is compiled and tested with `swift test` on
CI like Core. App stays glue: it only creates these types and wires them
(#11). Other platform adapters (audio capture, overlay) can stay in App, or
follow this pattern if they need tests.

## 0006: Transcription session, segment IDs and caption store rules

2026-11-12 · #8

**Context.** `SpeechTranscriber` delivers each phrase as one or more volatile
results and then a final one, in order, each with an audio time range; final
results are never replaced. The overlay needs lines that update in place, and
the transcript must stay stable. The en-US model is downloaded by the system
and may be missing.

**Decision.**

- One locale, en-US. No language picker, no parallel recognizers.
- Reporting options `volatileResults` and `fastResults` (latency over
  accuracy, for live captions); no attribute options, since the result's
  `range` gives the phrase's time range. Revisit `fastResults` after
  real-world testing.
- Audio is resampled with `AVAudioConverter` to
  `SpeechAnalyzer.bestAvailableAudioFormat` (`AnalyzerInputConverter` needs
  macOS 27). Each input carries an explicit start time from `AudioTimeline`,
  so result ranges are session seconds; gaps re-anchor the timeline.
- `SegmentTracker` (Core) gives the volatile results of the open phrase one
  `SegmentID`; the final result that overlaps it keeps that ID and closes it.
- `CaptionStore` (Core): volatile text is replaced in place, one volatile line
  per origin; finals are appended and immutable (late events for a final ID
  are ignored); history is bounded (`historyLimit`, default 500), and dropped
  IDs are remembered for another `historyLimit` finals. The snapshot shows the
  last `visibleFinalLines` (default 2) finals plus the volatile lines. Hiding
  idle captions is left to the overlay and session waves (#9, #11).
- Assets have explicit states (`SpeechAssetState`: checking, not installed,
  downloading, ready, unsupported, failed). The transcriber never downloads:
  it throws `TranscriptionError.assetsNotReady`, and the app calls
  `SystemSpeechAssets.install`, an explicit download done by the system.

**Consequences.** #11 wires `SystemSpeechAssets` into the menu states and
feeds `SpeechAnalyzerTranscriber` events into a `CaptionStore`. Latency still
needs measuring on a real Mac.
