# Manual testing

CI builds the app and runs the Core and SpeechAdapter tests, but hosted macOS
runners are VMs: they have no system audio, no permission prompts, no notch
and no on-device speech model. These checks need a real Apple Silicon Mac
with macOS 26. Run them for every PR that touches capture, speech, the
overlay or the menu, and note the result in the PR.

Get a build as described in the README ("Try a CI build"). Each CI build has a
new ad-hoc signature, so macOS may ask for the permission again.

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
