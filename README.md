# Cinema Player

<p align="center">
  <img src="Brand/cinema-player-mark.svg" width="104" alt="Cinema Player logo">
</p>

<p align="center"><strong>A private, local-first cinema for the videos already on your Mac.</strong></p>

Cinema Player is an open-source macOS video player built with SwiftUI and AVKit. It has no accounts, ads, analytics, or streaming catalogue. You choose what plays — files on your Mac, or a direct video link you paste in yourself — and nothing is sent anywhere else.

## What it does

- Imports local video files by open panel, drag-and-drop, or a recursive folder scan, with persistent security-scoped access
- Plays videos from a direct `http`/`https` link — MP4, MOV, and HLS (`.m3u8`) streams — added with ⌘L, the link button, or by dropping a URL onto the window
- Shows thumbnails, duration, resolution, file size, and format
- Remembers where you stopped watching and lets you resume
- Keeps a searchable library with favorites and recently added titles
- Plays through a playlist with autoplay, next and previous, repeat, and shuffle
- Provides keyboard controls, 10-second skips, speed, volume, aspect-fit modes, and a clean fullscreen experience
- Hides player controls when idle and reveals them on mouse movement or keyboard interaction
- Lets you choose embedded subtitle tracks or load external `.srt` files, with a simple subtitle timing adjustment
- Switches between embedded audio tracks when a file has more than one
- Reveals a title in Finder, copies a stream's link, or moves a file to the Trash straight from the library
- Reports to the system Now Playing widget and Control Center and answers the keyboard media keys

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

To publish a website edit, run `zsh Scripts/publish-site.sh`.

To build, package, and publish a release (plus the website when needed), use `zsh Scripts/release.sh v0.3.0 --publish-site`. The complete, safe release checklist is in [docs/RELEASING.md](docs/RELEASING.md).

## Contributing and security

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request. Please report security concerns privately as described in [SECURITY.md](SECURITY.md).

Released under the [MIT License](LICENSE).
