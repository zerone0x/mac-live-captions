# Architecture

LiveCaptions is a menu-bar app for macOS 26+ on Apple Silicon. It shows live
English captions of the audio your Mac plays. Speech recognition runs on
device (Apple `SpeechAnalyzer` + `SpeechTranscriber`, en-US). No network calls
in the caption path.

What the product does and does not do is [SCOPE.md](SCOPE.md), the source of
truth for the current scope. Decisions and their reasons:
[DECISIONS.md](DECISIONS.md). Background only: [research/](research/) and the
original long-term vision in [PRD.md](../PRD.md) (Chinese), whose summaries,
translation and microphone labelling are not part of the current scope.

## Pipeline

```
AudioSource ──AudioChunk──▶ Transcriber ──TranscriptEvent──▶ CaptionStore ──CaptionSnapshot──▶ Overlay
 (system audio;                (SpeechAnalyzer,               (volatile vs final,               (CaptionComposer: 2×42 layout,
  mic only in the               en-US, on device)              transcript)                       idle collapse; notch panel)
  debug capture test)
```

| Stage | Contract (Core) | Real implementation | Lives in | Wave |
|---|---|---|---|---|
| AudioSource | `protocol AudioSource` → `AsyncThrowingStream<AudioChunk, Error>`; `AudioCaptureStatus` state machine, `AudioChunkAssembler`, `SilenceMonitor` | `SystemAudioSource` (ScreenCaptureKit); `MicrophoneAudioSource` (used only by the debug capture test) | App (`Sources/Audio/`), Core (logic) | #7 |
| Transcriber | `protocol Transcriber` → `AsyncThrowingStream<TranscriptEvent, Error>`; `SegmentTracker` (stable IDs), `AudioTimeline` | `SpeechAnalyzerTranscriber` (`SpeechAnalyzer` + `SpeechTranscriber`, en-US) | SpeechAdapter package (adapter), Core (logic) | #8 |
| Speech model | `protocol SpeechAssetProvider`, `SpeechAssetState` | `SystemSpeechAssets` (`AssetInventory`) | SpeechAdapter package, Core | #8 |
| CaptionStore | `struct CaptionStore`, pure logic | n/a (no platform code) | Core | #8 |
| Overlay | `protocol CaptionPresenter` (`@MainActor`); `CaptionComposer` (layout, idle collapse), `OverlayPlacement` (notch maths) | `NotchOverlayController` + `OverlayPanel` (click-through `NSPanel`) | Core (logic), App (window) | #9 |
| Session / menu bar | `SessionPhase` state machine with `SessionEffect`s, `SessionStatus` (menu line and icon), `CaptionPipeline` (runs one session), `CaptionUpdateThrottle`, `CaptionSettings` | `AppModel` (effects), `MenuBarExtra`, Settings and welcome windows, `GlobalHotKey` (⌃⌥C) | Core + App | #6, #11 |

Value types shared by the stages (all `Sendable`, all in Core):

- `AudioChunk`: mono Float32 samples, sample rate, `AudioOrigin` (`system` or
  `microphone`), start time in session seconds. No AVFoundation types, so fakes
  are trivial; adapters convert to and from `AVAudioPCMBuffer`. Real sources
  emit contiguous 100 ms chunks at 16 kHz (`CaptureFormat`, DECISIONS 0006).
- `AudioCaptureStatus` / `AudioCaptureError`: capture health (permission
  denied, no audio, reconnecting, failed) as explicit states. Sources report
  it through `CaptureStatusReporter`, in order and only for the current run
  (`CaptureToken`, DECISIONS 0013).
- `TranscriptSegment`: stable `SegmentID`, text, time range, origin.
- `TranscriptEvent`: `.volatile(segment)` (may still change, drives the live
  line only) or `.final(segment)` (stable, goes into the transcript).
- `CaptionSnapshot` / `CaptionLine`: what the overlay shows now; empty means hide.
- `SpeechAssetState`: the en-US model is checking, not installed, downloading,
  ready, unsupported or failed. `TranscriptionError` says why a transcriber
  cannot run.
- `CaptionFrame` / `CaptionDisplayLine`: a snapshot laid out by
  `CaptionComposer` (at most two lines of 42 characters, final text plus a
  lighter volatile tail).

`CaptionStore` rules (DECISIONS 0011): volatile text is replaced in place under
its `SegmentID`; a final result keeps that ID and is then immutable; the
transcript keeps the newest `historyLimit` segments; the snapshot is the last
`visibleFinalLines` finals plus the volatile lines.

## Session

`AppModel` sends `SessionEvent`s to `SessionPhase` and performs the
`SessionEffect`s it returns (DECISIONS 0014):

```
idle ──Start──▶ checkingModel ──ready──▶ startingCapture ──capturing──▶ listening(hearing | noAudio | reconnecting)
                    │                         │                              │
                    └─not ready─▶ waitingForModel ──ready──▶ (startingCapture) │ Stop
                                                                              ▼
 permissionDenied / failed ◀── capture or pipeline error            stopping ──pipeline ended──▶ idle
```

- Start: stop the demo and the capture test, check the model (no download).
- `startPipeline`: a `SystemAudioSource` reports its `AudioCaptureStatus`
  as `captureStatusChanged`; a `CaptionPipeline` runs
  source → `SpeechAnalyzerTranscriber` → `CaptionStore` → throttle →
  `NotchOverlayController`, and its end is `pipelineEnded`. Status updates
  and the end travel through one ordered stream per pipeline with a single
  main-actor consumer.
- The menu icon is filled only in `listening`; `startingCapture` is busy.
- The menu shows `SessionStatus(phase:model:captureTest:)`. The model is
  downloaded only on an explicit click (welcome window or menu).
- System audio only; the microphone stays in the debug capture test.

Contracts are a starting point. The wave that first implements a stage may
reshape its protocol; record the change in DECISIONS.md.

## Module boundaries

```
App/                      thin platform glue (SwiftUI/AppKit, ScreenCaptureKit)
  Sources/                @main app, menu, settings and welcome windows, AppModel
                          (session effects), global shortcut
    Audio/                system audio + microphone sources, debug capture menu
    Overlay/              notch overlay panel, view, CI screenshot renderer
  Info.plist              LSUIElement, usage strings
  LiveCaptions.entitlements
Packages/Core/            local Swift package "Core", product LiveCaptionsCore
  Sources/LiveCaptionsCore/   pure logic + protocols, no UI, no hardware
  Tests/LiveCaptionsCoreTests/  Swift Testing; fakes for every protocol
Packages/SpeechAdapter/   local Swift package, product LiveCaptionsSpeech (DECISIONS 0010)
  Sources/LiveCaptionsSpeech/   SpeechAnalyzer/SpeechTranscriber/AssetInventory adapter
  Tests/LiveCaptionsSpeechTests/  converter tests, real-audio test (skips without the model)
Packages/AudioAdapter/    local Swift package, product LiveCaptionsAudio (DECISIONS 0013)
  Sources/LiveCaptionsAudio/    PCM buffer conversion for the capture sources (AVFoundation)
  Tests/LiveCaptionsAudioTests/   converter tests
project.yml               XcodeGen spec (the .xcodeproj is generated, not committed)
Makefile                  the commands CI runs
scripts/                  CI checks (offline sources, dependencies, linked frameworks,
                          bundle verification) and their self-tests and fixtures
```

Rules:

1. **Logic goes in Core.** Anything that can be tested without a Mac's audio
   hardware, permissions or screen (state machines, caption buffering,
   timing, text handling) belongs in `LiveCaptionsCore` with tests.
2. **App is glue.** App code adapts Apple frameworks to Core protocols and
   renders state. Keep it small; it is only compiled in CI, not unit-tested.
3. **Core imports Foundation only** (plus Observation/Synchronization if
   needed). No SwiftUI, AppKit, AVFoundation, ScreenCaptureKit or Speech.
4. **No networking** in the packages or App (DECISIONS 0003, 0012).
   `make check-offline` fails the build if networking APIs (`URLSession`,
   `import Network`/`WebKit`, `nw_*`, sockets, `SFSpeechRecognizer`, remote URL
   literals, `Process` and similar) or remote package dependencies appear;
   `make check-linked-frameworks` checks the built binary's linked frameworks
   and imported symbols. `scripts/check-offline-selftest.sh` checks all three
   against fixtures. The only sanctioned network use is the system's speech
   model download through `AssetInventory`, only when the user clicks
   "Download English Speech Model".
5. **Swift 6 language mode**, complete strict concurrency. Cross-stage data is
   `Sendable`; UI-facing types are `@MainActor`.

## Testing

- `make test` runs the Core, AudioAdapter and SpeechAdapter package tests with Swift Testing
  (`import Testing`).
- Every protocol has a fake in `Tests/LiveCaptionsCoreTests/Fakes.swift`
  (`FakeAudioSource`, `ScriptedTranscriber`, `ReplayTranscriber`,
  `RecordingPresenter`, `ScriptedSpeechAssets`). New stages add their fake
  there. If App tests ever need them, move them to a test-support target.
- The SpeechAdapter real-audio test speaks a sentence with `say`, runs it
  through `SpeechAnalyzer` and checks the final captions. It installs the en-US
  model if it can and otherwise skips, printing a `[real-audio]` reason.
- Things CI cannot check (real audio, permission prompts, the notch, focus
  behaviour) go into the PR description as a manual checklist for the owner;
  the standing checklist is [TESTING.md](TESTING.md).

## Build and CI

- `make build` generates the project with XcodeGen and builds an ad-hoc signed
  arm64 app with hardened runtime.
- `make package` also runs `scripts/verify-app.sh` (LSUIElement, usage strings,
  arm64, signature with hardened runtime, exactly the expected entitlements so
  no `get-task-allow`, stripped binary) and zips the app. It is meant for
  Release builds; `scripts/verify-app-selftest.sh` checks that it rejects bad
  bundles.
- `make screenshots` runs the built app with `--render-overlay-snapshots` and
  writes PNG renders of fixed overlay states, the menu states, Settings and
  the welcome window to `build/screenshots` (`OverlaySnapshotRenderer` in
  `App/Sources/Overlay/`, `AppSnapshotRenderer` in `App/Sources/Screenshots/`).
  `make compare-screenshots` checks the overlay renders against
  `scripts/fixtures/screenshots/`. `make live-screenshots` screenshots the
  running app with `--demo-captions` (docs/TESTING.md, "Screenshots from CI").
- `.github/workflows/ci.yml` runs on a `macos-26` runner for every PR and push
  to `main`, in this order: `make check-offline`,
  `scripts/check-offline-selftest.sh`, `make test` (all packages),
  `scripts/verify-app-selftest.sh`, `make package`,
  `make check-linked-frameworks`, `make screenshots`,
  `scripts/compare-screenshots-selftest.sh`, `make compare-screenshots`, then
  `make live-screenshots`. It uploads three artifacts, kept for 14 days:
  `LiveCaptions-<sha>` (the zipped app), `overlay-screenshots-<sha>` (the
  rendered PNGs) and `live-screenshots-<sha>`. `<sha>` is the PR head commit, or
  the pushed commit on `main`. The README ("Try a CI build") says how to
  download them.
