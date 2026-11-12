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
