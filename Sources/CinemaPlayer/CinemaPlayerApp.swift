import SwiftUI

@main
struct CinemaPlayerApp: App {
    @StateObject private var library = MediaLibrary()
    @StateObject private var playback = PlaybackController()
    @StateObject private var keyboardControls = KeyboardControlMonitor()
    @StateObject private var fullscreen = VideoOnlyFullscreenController()
    @StateObject private var controlsVisibility = PlaybackControlsVisibility()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .environmentObject(playback)
                .environmentObject(fullscreen)
                .environmentObject(controlsVisibility)
                .task {
                    keyboardControls.start(
                        with: playback,
                        fullscreen: fullscreen,
                        controlsVisibility: controlsVisibility
                    )
                }
                .frame(minWidth: 980, minHeight: 640)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Videos…") {
                    library.chooseVideos()
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandMenu("Playback") {
                Button(playback.isPlaying ? "Pause" : "Play") {
                    playback.togglePlayback()
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(playback.currentItem == nil)

                Divider()

                Button("Skip Back 10 Seconds") {
                    playback.skip(by: -10)
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(playback.currentItem == nil)

                Button("Skip Forward 10 Seconds") {
                    playback.skip(by: 10)
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(playback.currentItem == nil)

                Divider()

                Menu("Playback Speed") {
                    ForEach(PlaybackRate.allCases) { rate in
                        Button(rate.title) {
                            playback.setRate(rate)
                        }
                    }
                }
            }
        }
    }
}
