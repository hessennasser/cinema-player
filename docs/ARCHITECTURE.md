# Architecture

Cinema Player is a small, native macOS application with deliberately separated layers.

```text
Sources/CinemaPlayer/
├── Models/       Local media and presentation values
├── Services/     Library persistence, playback, keyboard and fullscreen state
├── Views/        SwiftUI screens and AppKit/AVKit bridges
└── CinemaPlayerApp.swift
```

- **Models** contain plain values with no UI dependency.
- **Services** own long-lived state and native framework integration. `MediaLibrary` stores security-scoped bookmarks; `PlaybackController` owns the `AVPlayer` and resume position.
- **Views** compose the interface. `NativePlayerView` and `MouseActivityTrackingView` are minimal AppKit bridges isolated from playback logic.

The project intentionally uses only Apple frameworks. A future contributor can add subtitles, media session controls, or richer metadata without replacing the app’s core layers.
