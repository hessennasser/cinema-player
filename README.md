# Cinema Player

<p align="center">
  <img src="Brand/cinema-player-mark.svg" width="104" alt="Cinema Player logo">
</p>

<p align="center"><strong>A private, local-first cinema for the videos already on your Mac.</strong></p>

Cinema Player is an open-source macOS video player built with SwiftUI and AVKit. It has no accounts, ads, analytics, or streaming catalogue. You choose the files; they stay on your device.

## What it does

- Imports local video files with persistent, security-scoped access
- Shows thumbnails, duration, resolution, file size, and format
- Remembers where you stopped watching and lets you resume
- Keeps a searchable library with favorites and recently added titles
- Provides keyboard controls, 10-second skips, speed, volume, aspect-fit modes, and a clean fullscreen experience
- Hides player controls when idle and reveals them on mouse movement or keyboard interaction

## Download

Download the current macOS app from the [latest release](https://github.com/hessennasser/cinema-player/releases/latest). The app is ad-hoc signed for local use; macOS may require you to confirm that you want to open it.

## Development

Requirements: macOS 14 or later and Swift 6.

```sh
git clone https://github.com/hessennasser/cinema-player.git
cd cinema-player
swift test
swift run CinemaPlayer
```

Create a distributable local bundle:

```sh
zsh Scripts/build-app.sh
open "build/Cinema Player.app"
```

## Project map

- `Sources/CinemaPlayer/Models` — media and presentation values
- `Sources/CinemaPlayer/Services` — playback, library, fullscreen, and input state
- `Sources/CinemaPlayer/Views` — SwiftUI screens and minimal AppKit/AVKit bridges
- `Brand/` — shared logo and color palette
- `Website/` — the GitHub Pages source
- `docs/ARCHITECTURE.md` — structure and extension points

## Contributing and security

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request. Please report security concerns privately as described in [SECURITY.md](SECURITY.md).

Released under the [MIT License](LICENSE).
