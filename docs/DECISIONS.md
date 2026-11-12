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
