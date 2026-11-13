# Scope

This is the current product scope of LiveCaptions and the source of truth for
what the app does. If another document disagrees with it, this file wins and
the other document should be fixed.

[PRD.md](../PRD.md) (in Chinese) is the original long-term vision: a meeting
catch-up tool with summaries. It is kept as background only. Nothing in it is
planned unless this file says so.

## Goal

A Murmo-like menu-bar app: live **English** captions of the audio your Mac
plays, shown at the notch, with speech recognition **on device** so captions
are fast and nothing leaves the Mac.

The owner set this scope on 2026-11-12 in
[#13](https://github.com/zerone0x/mac-live-captions/issues/13#issuecomment-6837597297)
and [#11](https://github.com/zerone0x/mac-live-captions/issues/11#issuecomment-6837596481).
The decision is [DECISIONS 0003](DECISIONS.md#0003-captions-are-english-only-and-fully-on-device).

## What v0.1 does

- **Captions system audio** (what the Mac plays: calls, videos, browser
  tabs), captured with ScreenCaptureKit (DECISIONS 0005, 0006).
- **English only.** Recognition uses Apple's `SpeechAnalyzer` and
  `SpeechTranscriber` with the en-US locale, on Apple Silicon, macOS 26 or
  later (DECISIONS 0002, 0003).
- **Shows captions at the notch.** A click-through panel that never takes
  focus hangs from the notch, or is a pill under the menu bar on displays
  without one. At most two lines of 42 characters; finalized text does not
  change, the live (volatile) tail is lighter and may still change, and the
  overlay collapses after 6 seconds without new text (DECISIONS 0007, 0008).
- **Says what is really happening.** The menu-bar status line and icon show
  checking or downloading the speech model, waiting for the model, starting
  audio capture, listening, listening with no audio playing, reconnecting,
  waiting for permission, stopping, or the error. The icon is filled only
  while audio is really captured (DECISIONS 0014).
- **Start and stop** from the menu bar, the welcome window, or the global
  shortcut **⌃⌥C** (Control-Option-C) from any app. The shortcut needs no
  Accessibility permission (DECISIONS 0014, 0015).
- **Settings:** text size (Small, Medium, Large, Extra Large), position (top
  at the notch, or bottom of the screen), and "Hide overlay from screen
  sharing", which is best effort only (DECISIONS 0009, 0014).
- **Welcome window** that walks through the English speech model and the
  Screen & System Audio Recording permission.
- **Debug items** in the menu: a scripted demo feed for the overlay
  ("Debug: Demo Captions") and a capture test for system audio or the
  microphone ("Debug: Audio Capture").

## Privacy and network

- Audio and transcripts stay in memory. Nothing is recorded, saved or logged.
  Only the settings and the "welcome closed" flag are stored, as preferences
  (DECISIONS 0014).
- The only network use is Apple's English speech model download. macOS
  downloads it once from Apple, through `AssetInventory`, and only when you
  click "Download English Speech Model". The app makes no other network calls.
  CI enforces this on the sources, the dependencies and the built binary
  (`make check-offline`, `make check-linked-frameworks`; DECISIONS 0012).

## What v0.1 does not do

| Out of scope | Status |
|---|---|
| Translation | Deferred: [#10](https://github.com/zerone0x/mac-live-captions/issues/10). Needs a new decision (0003). |
| Languages other than English, or mixed Chinese/English | Not planned. Needs a new decision (0003). |
| Catch-up summaries, the review panel, citations to the transcript | Not planned yet. Background in PRD.md. |
| Captioning the microphone, "me" vs "them" labels | Not yet. The microphone is only in the debug capture test until a layout for two sources exists (0014). |
| Speaker identification | Not planned. |
| Saving transcripts or audio, transcript history, export | Not planned. |
| Any cloud service, accounts, sync | Out (0003). A future network feature must be opt-in and outside the caption path. |
| Meeting bots, Feishu or other integrations | Out. |
| Intel Macs, macOS before 26, other platforms | Out (0002). |
| Notarized or App Store builds | Not yet. CI builds are ad-hoc signed (0004). |
| A configurable shortcut | Not yet; ⌃⌥C is fixed (0014). |

Changing any of this needs an owner decision, recorded in
[DECISIONS.md](DECISIONS.md), and an update to this file.
