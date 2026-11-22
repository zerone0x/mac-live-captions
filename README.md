<h1 align="center">
  <img src="App/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" width="64" alt=""><br>
  LiveCaptions
</h1>

<h2 align="center">Live English captions for anything your Mac plays.</h2>

<p align="center">
  Follow calls, videos, and podcasts with captions at the notch.
  Speech recognition runs on your Mac, and audio and transcripts stay in memory.
</p>

<p align="center">
  <strong><a href="https://github.com/zerone0x/mac-live-captions/releases/download/v0.1.3/LiveCaptions-0.1.3-mac-arm64.dmg">Download DMG</a></strong>
  · <a href="#install">Install guide</a>
  · <a href="CHANGELOG.md">Changelog</a>
  <br>
  <sub>Apple Silicon · macOS 26 or later · English (US)</sub>
</p>

<p align="center">
  <img src="scripts/fixtures/screenshots/overlay-notch-4-two-line-final.png" width="760" alt="LiveCaptions showing two lines of English captions in a black overlay at the MacBook notch">
</p>

## Features

- **Caption system audio.** Follow English speech from meeting apps, browser tabs, and media players.
- **Keep captions in view.** The overlay sits at the notch, appears below the menu bar on displays without a notch, or moves to the bottom of the screen. It lets clicks pass through and offers four text sizes. Settings can also hide the overlay from screen sharing where supported.
- **Start from any app.** Press **⌃⌥C** (Control–Option–C) or use the menu bar. The menu shows whether LiveCaptions is listening, waiting for audio, or needs setup.
- **Keep speech on your Mac.** Apple’s SpeechAnalyzer processes audio locally. LiveCaptions saves only preferences. The one-time English speech model download comes from Apple.

LiveCaptions captions English system audio. Microphone captions, translation, and transcript export are outside the [current scope](docs/SCOPE.md).

## Install

Requires an **Apple Silicon Mac with macOS 26 or later**.

### DMG

1. Download the [LiveCaptions v0.1.3 DMG](https://github.com/zerone0x/mac-live-captions/releases/download/v0.1.3/LiveCaptions-0.1.3-mac-arm64.dmg).
2. Open the DMG and drag **LiveCaptions** to **Applications**. Quit any
   running copy before replacing it.
3. Eject the DMG, then open LiveCaptions from Applications. Starting with
   v0.1.3, both the app and DMG are Developer ID signed and notarized by Apple.

The [release page](https://github.com/zerone0x/mac-live-captions/releases/tag/v0.1.3)
also has the ZIP and SHA-256 files. To verify a download, keep it beside
its `.sha256` file and run `shasum -a 256 -c` with the checksum filename.
If you use the ZIP, unzip it and move `LiveCaptions.app` to Applications.

### Terminal

```sh
curl -fsSL https://raw.githubusercontent.com/zerone0x/mac-live-captions/main/scripts/install.sh | bash
```

The [installer](scripts/install.sh) downloads the latest release ZIP,
verifies its SHA-256 checksum, installs LiveCaptions in `/Applications`,
and opens the app. It runs without `sudo`. Run the same command to update,
or use `bash -s -- 0.1.3` in place of `bash` to select a version.

macOS may request permissions again when you upgrade from an older ad-hoc
signed build. To uninstall, quit LiveCaptions and delete
`/Applications/LiveCaptions.app`. To remove its preferences as well, run
`defaults delete dev.trine.LiveCaptions`.

## First run

LiveCaptions appears in the menu bar.

1. Open **Welcome and Setup…** from the LiveCaptions icon in the menu bar.
2. Click **Download English Speech Model** and wait for macOS to finish downloading it.
3. Click **Ask for Permission**, allow LiveCaptions in **System Settings → Privacy & Security → Screen & System Audio Recording**, then click **Relaunch**.
4. Play something with English speech. Choose **Start Captions** in the menu bar or press **⌃⌥C**.

To preview the overlay without playing audio, choose **Debug: Demo Captions** from the menu.

## Report a problem

[Open an issue](https://github.com/zerone0x/mac-live-captions/issues/new) with:

- the app version (`defaults read /Applications/LiveCaptions.app/Contents/Info.plist CFBundleShortVersionString`),
  your Mac model and macOS version (Apple menu → About This Mac);
- the menu's status line and detail text (or a screenshot of the menu);
- what you did, what you expected and what happened instead (for example:
  which app was playing audio, built-in display or external, notch or not).

Known limitations are in [CHANGELOG.md](CHANGELOG.md); hardware checks still
open are on [#29](https://github.com/zerone0x/mac-live-captions/issues/29).
LiveCaptions saves no transcripts or audio, so there is nothing to attach
beyond what you describe; leave out anything private you saw in captions.
