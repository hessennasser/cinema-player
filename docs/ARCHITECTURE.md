# Architecture

Cinema Player is a small, native macOS application with deliberately separated layers.

```text
Sources/CinemaPlayer/
├── Models/       Media and presentation values, local or remote
├── Services/     Library persistence, playback, keyboard and fullscreen state
├── Views/        SwiftUI screens and AppKit/AVKit bridges
└── CinemaPlayerApp.swift
```

- **Models** contain plain values with no UI dependency.
- **Services** own long-lived state and native framework integration.
- **Views** compose the interface. `NativePlayerView` and `MouseActivityTrackingView` are minimal AppKit bridges isolated from playback logic.

`MediaLibrary` stores security-scoped bookmarks and `PlaybackController` owns the `AVPlayer`, the resume position, and the streaming-quality cap.

## Opening a link

A `MediaItem` is either a bookmarked local file or a plain `http`/`https` URL, and the rest of the app branches on `MediaItem.isRemote`. Four services turn a pasted address into something `AVPlayer` can open, each with one job:

| Service | Responsibility |
| --- | --- |
| `StreamAddressPolicy` | Decides whether an address may be fetched at all. Refuses loopback, private, link-local and multicast addresses in both families, resolving a host name so a public name pointing inward is caught. |
| `StreamHTTP` | Every network read. Caps bodies and redirects, re-applies the address policy to each hop, and answers what a link *is* — `HEAD` first, a ranged `GET` when that is refused, and the leading bytes when the declared type is not to be trusted. |
| `PageVideoResolver` | Turns a link into a `ResolvedVideo`. Pure extraction (JSON-LD, Open Graph, `<video>`/`<source>`, `<base href>`) is separated from the fetching, so the parsing is testable without a network. |
| `StreamCache` | Keeps a local copy of a video whose host ignores `Range`. `AVPlayer` cannot reach a trailing `moov` atom on such a host, so fetching first is the only way to watch it. |

`StreamSupport` holds the shared vocabulary these use: what counts as a streamable address, which content types are media, and what an HLS master playlist offers — including the rungs behind the quality menu.

## Dependencies

The project intentionally uses only Apple frameworks. A future contributor can add subtitles, media session controls, or richer metadata without replacing the app’s core layers.
