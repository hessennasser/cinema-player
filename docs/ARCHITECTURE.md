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
- **Services** own long-lived state and native framework integration. `MediaLibrary` stores security-scoped bookmarks; `PlaybackController` owns the `AVPlayer` and resume position. `StreamSupport` is the single place that decides whether an address can be handed to `AVPlayer`, so a `MediaItem` is either a bookmarked file or a plain `http`/`https` URL and the rest of the app branches on `MediaItem.isRemote`. `PageVideoResolver` sits in front of that: it asks the host what a link actually is and, when the answer is a web page, reads the video the page advertises, so its parsing stays pure and testable while the network work is confined to a few small functions.
- **Views** compose the interface. `NativePlayerView` and `MouseActivityTrackingView` are minimal AppKit bridges isolated from playback logic.

The project intentionally uses only Apple frameworks. A future contributor can add subtitles, media session controls, or richer metadata without replacing the app’s core layers.
