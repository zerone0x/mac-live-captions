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

### Invariants and tests

Core invariants the rest of the app relies on, and the test that fails when
one breaks. Each row was checked by mutation testing (#26): breaking the
invariant in the source makes the named test fail. Tests are in
`Packages/Core/Tests/LiveCaptionsCoreTests/`; names are the `@Test` titles.

| Invariant | Test (suite: title) |
|---|---|
| Composer drops finalized text that scrolled out of view, so memory and per-update work stay bounded in a long session | Caption composer: "a long session keeps composer state bounded: scrolled-out text and old IDs are dropped" |
| Composer forgets segment IDs the store no longer reports | Caption composer: same test as above |
| Lines never scroll back down when a volatile revision gets shorter | Caption composer: "finalizing replaces the volatile tail without moving earlier text" and other `layoutViolations` checks |
| Text arriving at or after the collapse deadline starts on a fresh line | Caption composer: "text after an idle collapse starts on a fresh line", "text arriving exactly at the collapse deadline also starts on a fresh line" |
| An unexpected pipeline end while starting or listening is `failed` and stops the pipeline (`[.stopPipeline]`) | SessionPhase: "an unexpected pipeline end while starting or listening fails and stops the pipeline" |
| The pipeline end after Stop returns to idle with no effects | SessionPhase: "the pipeline end after Stop returns to idle with nothing left to do" |
| The transcriber finding the model missing stops capture | SessionPhase: "the transcriber finding the model missing returns to waiting and stops capture" |
| A stream that dies in any active status (also "no audio") shows "reconnecting" | AudioCaptureStatus: "a stream that dies while capturing shows 'reconnecting', even when nothing was playing" |
| A restarted stream clears "no audio" | AudioCaptureStatus: "a restarted stream clears 'No audio' (its silence monitor starts afresh)" |
| Chunk times stay contiguous, also after a flushed short chunk | Audio processing: "chunks are contiguous: each starts where the previous ended", "after a flush, the next chunk starts where the short flushed chunk ended" |
| The level meter stays within 0...1, also above full scale | Audio processing: "samples above full scale still fill the meter only to the top" |
| Silence is reported on time despite rounding drift in summed block times | Audio processing: "silence is reported on time when block times are summed with rounding drift" |
| Reconnect delays back off exponentially, are capped, and stop after `maxAttempts` | Audio processing: "retry backs off exponentially, capped, then gives up" |
| The notch overlay is at least the notch plus a 24-point shoulder on each side | Overlay placement: "is never narrower than the notch plus its shoulders" (literal 252) |
| Zero-width auxiliary areas are not a notch | Overlay placement: "detects the notch from the auxiliary areas and safe-area inset" |
| The status reporter never reopens a run older than the newest run seen; a late `end` of an older run cannot lower it | Capture lifecycle: "an older run cannot be reopened after a newer one began", "a late end of an older run does not lower the newest run seen" |
| A stale token cannot end a newer run | Capture lifecycle: "a stale reconnect or error path cannot end a newer run" |
| The retry count resets only after a stream stayed up for the healthy period | Capture lifecycle: "a stream that dies right after starting does not reset the count, so retries end", "a stream that stayed up for the healthy period starts counting from 1 again" |
| Store transcript and final-ID memory are bounded; finals are immutable | CaptionStore: "history is bounded: the oldest finalized segments are dropped", "remembered final IDs are bounded too", "finalized segments are immutable: later finals and volatiles are ignored" |
| The open phrase's start only moves back; the fallback start (`lastEnd`) only grows | SegmentTracker: "the open phrase's start follows the earliest volatile result", "a later volatile result with a later start does not move the open phrase's start forward", "a late final for an earlier phrase does not move the fallback start back" |
| A volatile update one full interval after the last one is shown at once | CaptionUpdateThrottle: "a volatile update exactly one interval after the last one is shown at once" |
| A timeline mismatch up to the tolerance is contiguous; output times never decrease | AudioTimeline: "a mismatch of exactly the tolerance is still contiguous", "output start times never decrease, whatever the input times" |

Run the mutation check again when you change one of these types: mutate the
line, wipe `.build` (incremental Linux builds can keep a stale object file),
run `swift test --package-path Packages/Core`, and expect a failure.

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
