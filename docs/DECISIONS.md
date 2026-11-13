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
Enforcement and the one sanctioned exception are in 0012.

## 0004: Unsandboxed, hardened runtime, ad-hoc signed builds

2026-11-12 · #6

**Context.** There is no Apple Developer team in CI yet, and the app is not
headed for the Mac App Store. System audio capture and the microphone need
TCC permissions either way.

**Decision.** The app is not sandboxed. Hardened runtime is on (ready for
notarization later) with the `com.apple.security.device.audio-input`
entitlement. CI builds are ad-hoc signed (`CODE_SIGN_IDENTITY = -`).
Ad-hoc signing makes Xcode sign "to run locally" and inject
`com.apple.security.get-task-allow`, which lets any same-user process attach
a debugger and which notarization rejects, so the Release configuration sets
`CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO` and strips the binary (dSYM kept
beside it); Debug keeps both for local debugging. `scripts/verify-app.sh`
fails unless the signature has hardened runtime and exactly the audio-input
entitlement, and the binary has no debug map (#24).
Info.plist carries `LSUIElement` (menu bar only) and usage strings for audio
capture, microphone and speech recognition.

**Consequences.** Downloaded CI builds are quarantined by Gatekeeper and must be
cleared with `xattr` (see README). Because each ad-hoc build has a new code
signature, macOS may ask for permissions again after every update. Real
signing and notarization come with release packaging (#12).

## 0005: System audio is captured with ScreenCaptureKit

2026-11-12 · #7

**Context.** macOS has two official ways to capture what other apps play
without a virtual audio device: ScreenCaptureKit audio
(`SCStreamConfiguration.capturesAudio`) and Core Audio process taps
(`AudioHardwareCreateProcessTap`, macOS 14.2+). The research
([technical-feasibility.md](research/technical-feasibility.md) §1–2) found
that a denied ScreenCaptureKit permission is a clear error (`userDeclined`)
and `CGPreflightScreenCaptureAccess()` can check it, while a denied tap has no
query API and silently delivers zeros. Audicap reports crackling playback with
taps on macOS 26.4, and no lost words with ScreenCaptureKit across output
device changes. The cost of ScreenCaptureKit is the heavier "Screen & System
Audio Recording" permission, the purple capture indicator, a relaunch after
the grant, and periodic re-confirmation.

**Decision.** `SystemAudioSource` (App target) captures with ScreenCaptureKit,
adapted from Audicap's `SCKCapture` (MIT, notice in
[THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md)): a display filter with
only an audio output, `excludesCurrentProcessAudio`, 16 kHz mono requested,
and the buffer's real stream description used to read samples. A denied
permission is reported as `permissionDenied(.system)` and never retried
(retrying only re-prompts, and the grant needs a relaunch). Other stream stops
reconnect with exponential backoff (2–30 s, 6 attempts). After a default output
device change the stream is rebuilt only if no buffers arrive for 4 s. The
optional microphone source uses `AVAudioEngine` bound to the built-in
microphone, so Bluetooth headphones are not switched to the HFP call profile.

**Consequences.** Users grant Screen & System Audio Recording and relaunch
once; the error text says so. The purple indicator shows while capturing. A
process tap remains a possible later replacement if it works without
crackling on macOS 26.x; it would sit behind the same `AudioSource` protocol.

## 0006: Audio capture contract: 16 kHz mono chunks, explicit status

2026-11-12 · #7

**Context.** The transcriber (#8) and the pipeline wiring (#11) are built in
parallel with capture. Core must stay Foundation-only, and capture problems
(permission, nothing playing, interruptions) must be explicit states.

**Decision.** The `AudioSource` protocol is unchanged. Sources convert every
buffer to mono Float32 at 16 kHz (`CaptureFormat.sampleRate`) with
`AVAudioConverter` (downmix on) and emit contiguous 100 ms `AudioChunk`s whose
`startTime` counts captured frames (`AudioChunkAssembler`). The chunk stream
is bounded (the newest 60 s are kept) so the capture callback never blocks.
Capture health is a separate Core state machine, `AudioCaptureStatus` (idle,
starting, capturing, noAudio, reconnecting, permissionDenied, failed),
reported through an `onStatus` callback on the concrete sources. It does not
change `SessionPhase`; #11 maps one to the other. "No audio" means 5 s of
samples at or below -80 dBFS (`SilenceMonitor`). Fatal problems also end the
chunk stream with an `AudioCaptureError`. Pure parts live in Core
(`AudioCaptureStatus.swift`, `AudioProcessing.swift`); everything that touches
AVFoundation, Core Audio or ScreenCaptureKit lives in `App/Sources/Audio/`.

**Consequences.** Transcriber adapters receive 16 kHz mono Float32 and only
convert the sample type if the recogniser wants something else. Chunk times
do not include gaps while reconnecting. Until #11 wires the pipeline, a
"Debug: Audio Capture" submenu runs a source on its own and shows the level
and captured seconds.

## 0007: Caption overlay is a click-through panel at the notch of the menu-bar screen

2026-11-12 · #9

**Context.** Captions must stay visible over every app, including full-screen
ones, without taking focus or blocking clicks (meeting tools put buttons at
the top of the window). Existing notch apps (DynamicNotchKit, boring.notch,
NotchDrop) agree on the window setup; see docs/research/ux-and-privacy.md, 1.1–1.3.

**Decision.** The overlay is a borderless `NSPanel` with `.nonactivatingPanel`,
`canBecomeKey`/`canBecomeMain` = `false` and `ignoresMouseEvents = true`.
Collection behaviour `.canJoinAllSpaces`, `.fullScreenAuxiliary`, `.stationary`,
`.ignoresCycle`; level `.mainMenu + 3` (as boring.notch) so it can draw over
the menu bar beside the notch. No private SkyLight APIs. It goes on the screen
with the menu bar (`NSScreen.screens.first`), not `NSScreen.main`, which
follows keyboard focus. If that screen has a notch (`auxiliaryTopLeftArea`
and `auxiliaryTopRightArea` both set, `safeAreaInsets.top > 0`) the panel hangs
from the notch as a black shape; otherwise it is a pill centred under the menu
bar. The placement maths is `OverlayPlacement` in Core; it is recomputed on
`didChangeScreenParametersNotification` and every time the overlay opens.

**Consequences.** Whether level `.mainMenu + 3` stays above full-screen video,
Keynote and Zoom on macOS 26 is not verified in CI; it is on the owner's manual
checklist. A captions window that needs clicks (a transcript panel) will be a
separate window. A screen choice setting can come later (#11).

## 0008: Caption layout: two lines, 42 characters, finalized text is append-only

2026-11-12 · #9

**Context.** English subtitle guidelines allow two lines of about 42
characters. Live captions that rewrap or flicker as the recogniser revises
its guess measurably increase reading load (ux-and-privacy.md, 2.1–2.3).

**Decision.** `CaptionComposer` (Core) turns `CaptionSnapshot`s into
`CaptionFrame`s: greedy left-aligned word wrap at 42 characters, at most two
lines, scrolling up. Final segments are appended once (by segment ID) and
never change; only the volatile tail at the end is replaced. Greedy wrapping
is prefix-stable, so appended text cannot move earlier words. The view does
not scroll back down when a revision gets shorter. The overlay collapses
after 6 s without new text; text after that starts on a fresh line. The view
draws final text white and the volatile tail at half opacity, one `Text` per
line with `lineLimit(1)` so SwiftUI never rewraps on its own. The composer
takes the time as a parameter, so all of this is unit-tested without a clock.

**Consequences.** Character counts approximate pixel width; lines of wide
characters shrink slightly (`minimumScaleFactor`) instead of wrapping.
Throttling volatile updates (200–300 ms) is not done yet; add it if the real
recogniser updates faster than is comfortable to read.

## 0009: "Hide from screen sharing" is best effort only

2026-11-12 · #9

**Context.** Apple documents `NSWindow.SharingType.none` as a legacy constant
that should not be used to exclude content from capture, and ScreenCaptureKit
based capture may ignore it, depending on the app and macOS version
(ux-and-privacy.md, 1.4).

**Decision.** The menu has "Hide Overlay from Screen Sharing (Best Effort)",
off by default, which sets `sharingType = .none` on the overlay panel. We do
not promise that it works. The reliable advice for users is to share a single
window instead of the whole screen.

**Consequences.** Settings copy and docs must keep the "best effort" wording.
Re-test with Zoom, Meet and Teams after each major macOS update.

## 0010: Speech adapter in its own local package

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

## 0011: Transcription session, segment IDs and caption store rules

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

## 0012: Offline rule is enforced on sources, dependencies and the binary

2026-11-12 · #25

**Context.** An audit found that `check-offline.sh` (0003) only matched
`URLSession`, `URLRequest`, `WebSocket`, `NW*` and `import Network`.
`SFSpeechRecognizer` with server recognition, `NSURLConnection`, the `nw_*` C
API, remote URL literals, `import WebKit`, BSD sockets, `Process` running
`curl` and CFNetwork streams all passed. Remote packages and the built
binary were not checked at all.

**Decision.** Three checks, each with bad/good fixtures run by
`scripts/check-offline-selftest.sh` on Linux and in CI:

- `scripts/check-offline.sh` (sources): also bans `SFSpeech*` outright (the
  app uses `SpeechAnalyzer`/`SpeechTranscriber`), `NSURLConnection`, `nw_*`,
  CFNetwork/CFSocket/CFStream/CFHTTP/CFHost, `NetService`, imports of WebKit,
  CFNetwork, MultipeerConnectivity, CloudKit and NetworkExtension, `http`,
  `https`, `ws`, `wss` and `ftp` URL string literals (any case), sockets and the
  resolver, `Process`/`NSTask`/`posix_spawn`/`NSAppleScript`, and `dlopen`.
  Whole-line `//` comments are ignored. Other URL schemes
  (`x-apple.systempreferences:`, `file:`) stay allowed.
- `scripts/check-dependencies.sh`: no `url:`/`id:` package or binary target
  in any `Package.swift` or `Package@swift-*.swift`, no pins in a
  `Package.resolved`, no `url:`/`github:` (bare or quoted)
  package in `project.yml`, no CocoaPods or Carthage. The remote allow-list in
  the script is empty.
- `scripts/check-linked-frameworks.sh` (after the build, macOS): every library
  in `otool -L` must be on an allow-list of system frameworks and
  `libSystem`/`libobjc`/`libswift*`; Network, CFNetwork, WebKit and the Swift
  Network overlay are always rejected; `nm -u` must not show sockets, the
  resolver, `nw_*`, CFNetwork streams, `NSURLSession`/`NSURLConnection`,
  `SFSpeechRecognizer` or `dlsym`.

The one sanctioned network use is the en-US speech model download through
`AssetInventory` (Speech framework). The system performs it, the app never
opens a connection, and only when the app asks for a missing model
(0011). `AssetInventory`, `SpeechAnalyzer` and `SpeechTranscriber` are
therefore allowed.

**Consequences.** `make check-offline` runs the source and dependency checks;
`make check-linked-frameworks` runs after `make package` in CI. Linking a new
system framework means adding it to the allow-list in the same PR, with a
reason in the PR. Test targets are not scanned (the real-audio test runs
`say` through `Process`). Indirect traffic inside allowed system frameworks
(for example AVFoundation loading a remote URL passed as a variable) is out
of reach of these checks; reviews still matter. So is deliberate evasion in
source, such as a URL or API name built by concatenation or interpolation.

Each check exits 1 for a finding and 2 for an internal error (missing path,
unreadable file or directory, failing `grep`/`find`), so a broken scan never
reports OK. The self-test requires exit 1 for every bad fixture and exit 2 for
unreadable inputs.

## 0013: Capture runs have tokens; retries reset after a healthy period; "no audio" runs on a clock

2026-11-12 · #22

**Context.** Verifying #19 found start/stop races in both capture sources:
`stop()` during `start()` left the output-device listener installed; a
microphone configuration change or a permission prompt racing `stop()` could
start the engine after stop; a pending reconnect was never cancelled, so stop
then start on one source could open a second stream; and status callbacks
could reach the menu out of order ("Capturing audio" after stop). The retry
counter reset whenever a stream started, so a stream that died right after
starting retried every 2 s forever. "No audio" and the device-change check
assumed ScreenCaptureKit keeps sending silent buffers while nothing plays,
which nobody has confirmed. `MonoPCMConverter` had no tests because the App
target has none.

**Decision.**

- Every run of a source, from `start()` to `stop()` or a final error, gets a
  `CaptureToken` from `CaptureGenerations` (Core), kept under the source's
  lock with the state it guards. Every path that resumes later (after an
  `await` in `start()`, a reconnect delay, a device-change check, a
  configuration change, a sample or tap callback, the silence timer) checks
  its token in the same critical section as the change it makes, and undoes
  what it built if the run ended. `stop()` also cancels the stored reconnect
  task. If `stop()` runs while `start()` is starting, `start()` returns the
  chunk stream `stop()` already finished; the `AudioSource` protocol is
  unchanged.
- Status goes through `CaptureStatusReporter` (Core): it applies events and
  calls `onStatus` under one lock, so delivery order is apply order, and it
  drops events of any run but the open one, including everything after the
  run's `.stopped`. `onStatus` keeps its signature but must return quickly and
  not call back into the source. A source opens the run in the reporter in
  the same critical section as `runs.begin()`, and the reporter refuses to
  open a run that already ended, so a `stop()` racing `start()` cannot leave
  "Starting" behind. `.started` also clears "No audio": a rebuilt stream
  starts its silence monitor afresh. A source reports `.stopped` before it
  finishes the chunk stream. Consumers keep the order with one `AsyncStream`
  and one consumer (the debug probe does), not a `Task` per update.
- `CaptureRetryTracker` (Core) resets the attempt count only when the stream
  that failed had been up for at least 10 s (wall clock, monotonic). Measuring
  uptime instead of buffers makes the reset independent of whether silent
  buffers arrive.
- `SilenceMonitor` runs on a monotonic clock: blocks update it, and the
  system source also checks it from a 0.5 s timer, so "no audio" appears
  after 5 s whether or not any buffers arrive. The device-change check still
  rebuilds the stream when no buffer at all arrives within 4 s; if that only
  means nothing is playing, the rebuild costs a short reconnect, loses no
  audio and is not counted as a failure.
- `MonoPCMConverter` and `makePCMBuffer` move to a third local package,
  `Packages/AudioAdapter` (module `LiveCaptionsAudio`), following 0010, so the
  converter is tested with Swift Testing on CI. The capture sources stay in
  App.

**Consequences.** #11 can keep one source per session and restart it safely,
and can drive menu state from `onStatus` as long as it consumes updates in
order. Whether ScreenCaptureKit delivers silent buffers is no longer load
bearing; it is still worth noting on the first real-Mac test. The races
themselves need a real Mac to reproduce; the PR for #22 lists the steps.
