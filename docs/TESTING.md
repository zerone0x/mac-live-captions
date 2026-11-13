# Manual testing

CI builds the app and runs the Core and SpeechAdapter tests, but hosted macOS
runners are VMs: they have no system audio, no permission prompts, no notch
and no on-device speech model. These checks need a real Apple Silicon Mac
with macOS 26. Run them for every PR that touches capture, speech, the
overlay or the menu, and note the result in the PR.

To see the UI without a Mac, use the CI screenshots (next section).
Get a build as described in the README ("Try a CI build"). Each CI build has a
new ad-hoc signature, so macOS may ask for the permission again.

## Screenshots from CI

Every CI run uploads two screenshot artifacts (kept 14 days). `<sha>` is the
PR head commit, or the pushed commit on `main`. Reviewers and verifier agents
without a Mac read the PNGs to see the UI. A PR that changes the overlay, the
menu, Settings or the welcome window should say that its screenshots were
looked at (see the PR template).

```sh
gh run list --repo zerone0x/mac-live-captions --workflow ci.yml --branch <branch>
gh run download <run-id> --repo zerone0x/mac-live-captions --pattern '*-screenshots-*'
```

`gh run download` makes one folder per artifact. Open the PNGs in any image
viewer; agents can read them as images directly.

### Rendered views: `overlay-screenshots-<sha>`

`make screenshots` runs the built app with `--render-overlay-snapshots <dir>`.
It needs no permission, and the output does not depend on timing.

| Files | What they show |
|---|---|
| `overlay-notch-<state>.png`, `overlay-pill-<state>.png` | The caption overlay at the notch and as the pill (displays without a notch), on a fake menu bar. Four states, played from the demo script through the real `CaptionComposer`: `1-final-line`, `2-final-plus-volatile` (grey tentative tail), `3-two-line-wrap-volatile`, `4-two-line-final`. |
| `overlay-*-xl-3-*.png`, `overlay-bottom-3-*.png` | The two-line wrap at the extra large text size, and in the bottom position above a fake Dock. |
| `overlay-*-increase-contrast-*`, `overlay-pill-reduce-transparency-*`, `overlay-pill-*light-desktop-*` | The accessibility variants (see Accessibility below). |
| `menu-<state>.png` | A stand-in for the open menu-bar menu: the menu-bar icon and the menu's first items for twelve `SessionStatus` states (`off`, `off-model-missing`, `busy-*`, `listening*`, `attention-*`). Grey items are disabled, as in the real menu. The real menu is an `NSMenu` that only exists while it is open, so this is drawn from the same status and phase, not captured. |
| `settings.png`, `welcome.png` | The real Settings and welcome views, hosted in an off-screen window (real pickers and toggles). The welcome window says "Checking English speech model…" because it is drawn before the check finishes. |

### Reference images

The overlay renders that have a file in `scripts/fixtures/screenshots/` (the
four states in notch and pill style, the extra large and the bottom renders;
not the accessibility variants) are compared with it by
`make compare-screenshots` (`scripts/compare-screenshots.swift`). A pixel
differs when a channel (alpha too) is off by more than 8 of 255; an image
fails when more than 0.1 % of its pixels differ, or when its size differs. A
failing image gets `<name>.diff.png` (differing pixels in red) in the same
artifact. `scripts/compare-screenshots-selftest.sh` pins both thresholds
from each side with synthetic images: 10 of 10 000 pixels changed passes and
11 fails; a channel off by 8 passes and by 9 fails; an alpha-only change
fails. It also covers a different size, a missing image and an unreadable
reference (exit 2).

The renders were byte-identical on separate CI runners, so a failure means
the overlay changed. If the change is intended, look at the new PNGs, then
replace the references from the CI artifact and commit them with the PR:

```sh
make record-screenshots SHOTS=<downloaded overlay-screenshots-<sha> folder>
```

A new macOS or Xcode on the runner image can change font rendering. Then
every image fails at once, and re-recording is the fix. The menu, Settings,
welcome and accessibility renders have no references.

### The running app: `live-screenshots-<sha>`

CI switches the desktop to a grey picture (the runner's default desktop is
black, like the pill). Then `make live-screenshots`
(`scripts/live-screenshots.sh`) starts the built app directly with
`--demo-captions` (the scripted caption feed: no audio, no permissions) and,
3, 7 and 12 seconds after launch, runs `screencapture -x` for the whole
screen (`live-full-<t>s.png`) and the top 240 points (`live-top-<t>s.png`).
`windows-<t>s.txt` lists the app's on-screen windows (layer and frame), so a
window missing from a PNG can be told apart from a capture problem.
`app.log` is the app's output.

The step fails (exit 1) if the app quits, if it does not have exactly one
overlay window (layer above 0) on screen, or if the overlay is not in the
capture. The welcome window (layer 0) may be there or not: it only opens
until it has been closed once. The menu-bar icon is not in the window list.
Without Screen Recording, `screencapture` still succeeds and the window list
still has the overlay, but the PNG shows only the desktop and the menu bar.
So `screen-info.swift overlay-check` samples the full capture at the
overlay's frame: the desktop colour is the median of bands left, right and
below the frame, and at least half of the frame (inset from its rounded
corners) must differ from it by more than 40 of 255 in some channel. If the
desktop around the frame is not one colour (fewer than 90 % of its pixels
near the median), the check can't tell and fails with exit 2: locally, use a
solid desktop picture such as Solid Colors > Silver. A black desktop hides
the black overlay and fails too.

Every command in the script runs under `scripts/with-timeout.sh` (also
outside CI): `swift` helpers get 180 s, `screencapture` 30 s. A timeout kills
the command's whole process group and is exit 2, like any tool error. An app
that ignores SIGTERM at the end is killed after 5 s.
`scripts/live-screenshots-selftest.sh` checks the time limits (on Linux too)
and the overlay check on synthetic screenshots (shown, desktop only, at 1x
and 2x, black and busy desktops).

What the `macos-26` runner shows:

- The screen is 1024 × 768 points with no notch, so the overlay is the pill
  under the menu bar (the layer-27 window). The captions change between the
  shots as the demo plays.
- The welcome window (layer 0) is open, because every runner is a first
  launch. It says on-device speech is not supported (the runner is a VM) and
  that Screen & System Audio Recording is allowed: the runner agent holds
  that permission, and an app started from a step inherits it.
- The menu-bar icon (the outline captions bubble) is in the menu bar.
- Other apps' window contents are visible, because `screencapture` started
  from a step has Screen Recording through the runner agent. On a Mac where
  the terminal lacks that permission, the PNGs show only the desktop and the
  menu bar.

Not possible in CI, so these stay on the manual checklist below: real system
audio and speech (silence, and no speech model in a VM), the permission
prompt, and a real notch.

## First run

- [ ] Open the app. The welcome window opens, and the menu-bar icon is the
      outline captions bubble ("Not listening").
- [ ] The model step says whether the English speech model is installed. Its
      text says macOS downloads it once from Apple and that this is the only
      network use.
- [ ] Close the welcome window, quit and reopen: it does not open again.
      "Welcome and Setup…" in the menu brings it back.

## Speech model missing

Only possible on a Mac where the en-US model is not installed yet (or after
removing it).

- [ ] Click Start Captions. The menu says "Waiting for the English speech
      model" and offers "Download English Speech Model". Nothing is captured
      (no purple recording indicator).
- [ ] Click Download. The menu shows the download percentage, then captions
      start by themselves when it finishes.
- [ ] Stop during the download: the session ends; the menu keeps showing the
      download until it is done.
- [ ] Start a download, then quit and reopen (or Relaunch from the welcome
      window) while it runs, and click Start Captions. The menu shows the
      download; captions start by themselves when it finishes, without
      another click (DECISIONS 0021).
- [ ] If the download fails (for example with Wi-Fi off), the menu shows the
      error and offers "Download English Speech Model" again, with or
      without a session.

## Permission denied

- [ ] With Screen & System Audio Recording off for LiveCaptions, click Start
      Captions. The menu says "Waiting for permission", explains where to
      turn it on, and offers "Open Privacy Settings…" and "Relaunch
      LiveCaptions". The icon is the exclamation bubble.
- [ ] Allow the permission, click Relaunch LiveCaptions, then Start.

## End to end

- [ ] Play an English YouTube video. Click Start Captions (or press ⌃⌥C in
      any app). The menu says "Listening" only once audio is captured, and
      captions appear at the notch within about 1–2 s of the speech.
- [ ] The tentative (lighter) words update a few times a second, not on
      every word; finished sentences turn white and do not move.
- [ ] Pause the video. After a few seconds the menu says "Listening, no audio
      playing" and the overlay fades out. Resume: captions come back.
- [ ] Switch output (speakers to headphones) while captions run. The menu may
      show "reconnecting" briefly, then captions continue.
- [ ] Stop Captions (menu or ⌃⌥C). The menu says "Not listening", the icon is
      the outline bubble again and the recording indicator goes away.
- [ ] Start again: captions resume without relaunching.

## Menu honesty, demo and capture test

- [ ] With captions off, run Debug: Audio Capture > Test System Audio
      Capture. The menu says "Listening (audio capture test)" and the icon is
      filled.
- [ ] Start Captions while the test runs: the test stops, and the session
      starts.
- [ ] While captions run, Debug: Demo Captions and the capture test are
      disabled. Start Captions while the demo plays: the demo stops.

## Settings

- [ ] Settings… opens the Settings window in front of other apps.
- [ ] Text size: each size changes the overlay at once (use "Preview with Demo
      Captions"); the panel grows with the text and lines are not cut off.
- [ ] Position: "Bottom of the screen" shows a pill above the Dock; "Top"
      goes back to the notch.
- [ ] Hide overlay from screen sharing (best effort): share the whole screen
      in a call app and see whether the overlay is hidden. Results vary by
      app; note which ones.
- [ ] Settings survive a relaunch.

## Accessibility

Use "Preview with Demo Captions" with System Settings > Accessibility >
Display open next to it (decision 0018).

- [ ] Increase contrast on: the pill turns opaque black, the tentative words
      get brighter and italic. Turning it off while captions run goes back
      without a relaunch.
- [ ] Reduce transparency on: the pill turns opaque; the text looks as usual.
- [ ] VoiceOver: the menu-bar item is read as "LiveCaptions, Not listening",
      then "LiveCaptions, Listening" after Start Captions.
- [ ] VoiceOver: the overlay never speaks on its own. If the VoiceOver cursor
      can reach it (it ignores the mouse), it reads "Live captions" and the
      visible text. Note whether it is reachable at all.

## Privacy

- [ ] After a session, nothing new is in `~/Library/Containers`,
      `~/Library/Application Support` or `~/Library/Caches` for LiveCaptions,
      apart from the preferences file
      (`~/Library/Preferences/dev.trine.LiveCaptions.plist`).
- [ ] Console.app shows no caption text from LiveCaptions.
