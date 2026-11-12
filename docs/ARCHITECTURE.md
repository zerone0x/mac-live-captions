# Architecture

LiveCaptions is a menu-bar app for macOS 26+ on Apple Silicon. It shows live
English captions of the audio your Mac plays. Speech recognition runs on
device (Apple `SpeechAnalyzer` + `SpeechTranscriber`, en-US). No network calls
in the caption path.

Background: [PRD.md](../PRD.md), [docs/research/](research/). Decisions and
their reasons: [DECISIONS.md](DECISIONS.md).

## Pipeline

```
AudioSource ──AudioChunk──▶ Transcriber ──TranscriptEvent──▶ CaptionStore ──CaptionSnapshot──▶ Overlay
 (system audio,                (SpeechAnalyzer,               (volatile vs final,               (notch overlay,
  later mic)                    en-US, on device)              transcript, idle hide)            CaptionPresenter)
```

| Stage | Contract (Core) | Real implementation | Lives in | Wave |
|---|---|---|---|---|
| AudioSource | `protocol AudioSource` → `AsyncThrowingStream<AudioChunk, Error>`; `AudioCaptureStatus` state machine, `AudioChunkAssembler`, `SilenceMonitor` | `SystemAudioSource` (ScreenCaptureKit), `MicrophoneAudioSource` (opt-in, off by default) | App (`Sources/Audio/`), Core (logic) | #7 |
| Transcriber | `protocol Transcriber` → `AsyncThrowingStream<TranscriptEvent, Error>`; `SegmentTracker` (stable IDs), `AudioTimeline` | `SpeechAnalyzerTranscriber` (`SpeechAnalyzer` + `SpeechTranscriber`, en-US) | SpeechAdapter package (adapter), Core (logic) | #8 |
| Speech model | `protocol SpeechAssetProvider`, `SpeechAssetState` | `SystemSpeechAssets` (`AssetInventory`) | SpeechAdapter package, Core | #8 |
| CaptionStore | `struct CaptionStore`, pure logic | n/a (no platform code) | Core | #8 |
| Overlay | `protocol CaptionPresenter` (`@MainActor`) | notch overlay window | App | #9 |
| Session / menu bar | `SessionPhase` state machine | `MenuBarExtra` | Core + App | #6, #11 |

Value types shared by the stages (all `Sendable`, all in Core):

- `AudioChunk`: mono Float32 samples, sample rate, `AudioOrigin` (`system` or
  `microphone`), start time in session seconds. No AVFoundation types, so fakes
  are trivial; adapters convert to and from `AVAudioPCMBuffer`. Real sources
  emit contiguous 100 ms chunks at 16 kHz (`CaptureFormat`, DECISIONS 0006).
- `AudioCaptureStatus` / `AudioCaptureError`: capture health (permission
  denied, no audio, reconnecting, failed) as explicit states.
- `TranscriptSegment`: stable `SegmentID`, text, time range, origin.
- `TranscriptEvent`: `.volatile(segment)` (may still change, drives the live
  line only) or `.final(segment)` (stable, goes into the transcript).
- `CaptionSnapshot` / `CaptionLine`: what the overlay shows now; empty means hide.
- `SpeechAssetState`: the en-US model is checking, not installed, downloading,
  ready, unsupported or failed. `TranscriptionError` says why a transcriber
  cannot run.

`CaptionStore` rules (DECISIONS 0008): volatile text is replaced in place under
its `SegmentID`; a final result keeps that ID and is then immutable; the
transcript keeps the newest `historyLimit` segments; the snapshot is the last
`visibleFinalLines` finals plus the volatile lines.

Contracts are a starting point. The wave that first implements a stage may
reshape its protocol; record the change in DECISIONS.md.

## Module boundaries

```
App/                      thin platform glue (SwiftUI/AppKit, ScreenCaptureKit)
  Sources/                @main app, menu, adapters that conform to Core protocols
    Audio/                system audio + microphone sources, debug capture menu
  Info.plist              LSUIElement, usage strings
  LiveCaptions.entitlements
Packages/Core/            local Swift package "Core", product LiveCaptionsCore
  Sources/LiveCaptionsCore/   pure logic + protocols, no UI, no hardware
  Tests/LiveCaptionsCoreTests/  Swift Testing; fakes for every protocol
Packages/SpeechAdapter/   local Swift package, product LiveCaptionsSpeech (DECISIONS 0007)
  Sources/LiveCaptionsSpeech/   SpeechAnalyzer/SpeechTranscriber/AssetInventory adapter
  Tests/LiveCaptionsSpeechTests/  converter tests, real-audio test (skips without the model)
project.yml               XcodeGen spec (the .xcodeproj is generated, not committed)
Makefile                  the commands CI runs
scripts/                  CI helpers (offline check, bundle verification)
```

Rules:

1. **Logic goes in Core.** Anything that can be tested without a Mac's audio
   hardware, permissions or screen (state machines, caption buffering,
   timing, text handling) belongs in `LiveCaptionsCore` with tests.
2. **App is glue.** App code adapts Apple frameworks to Core protocols and
   renders state. Keep it small; it is only compiled in CI, not unit-tested.
3. **Core imports Foundation only** (plus Observation/Synchronization if
   needed). No SwiftUI, AppKit, AVFoundation, ScreenCaptureKit or Speech.
4. **No networking** in the packages or App. `make check-offline` fails the build if
   `URLSession`, any `import Network` form, `NW*` types and similar appear;
   `scripts/check-offline-selftest.sh` checks the check against fixtures in CI.
5. **Swift 6 language mode**, complete strict concurrency. Cross-stage data is
   `Sendable`; UI-facing types are `@MainActor`.

## Testing

- `make test` runs the Core and SpeechAdapter package tests with Swift Testing
  (`import Testing`).
- Every protocol has a fake in `Tests/LiveCaptionsCoreTests/Fakes.swift`
  (`FakeAudioSource`, `ScriptedTranscriber`, `ReplayTranscriber`,
  `RecordingPresenter`, `ScriptedSpeechAssets`). New stages add their fake
  there. If App tests ever need them, move them to a test-support target.
- The SpeechAdapter real-audio test speaks a sentence with `say`, runs it
  through `SpeechAnalyzer` and checks the final captions. It installs the en-US
  model if it can and otherwise skips, printing a `[real-audio]` reason.
- Things CI cannot check (real audio, permission prompts, the notch, focus
  behaviour) go into the PR description as a manual checklist for the owner.

## Build and CI

- `make build` generates the project with XcodeGen and builds an ad-hoc signed
  arm64 app with hardened runtime.
- `make package` also runs `scripts/verify-app.sh` (LSUIElement, usage strings,
  arm64, signature, entitlements) and zips the app.
- `.github/workflows/ci.yml` runs `check-offline`, `test` (both packages) and `package` on a
  `macos-26` runner for every PR and push to `main`, and uploads the zip as a
  workflow artifact.
