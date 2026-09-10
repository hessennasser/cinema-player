@preconcurrency import AppKit
import Foundation

@MainActor
final class KeyboardControlMonitor: ObservableObject {
    private weak var playback: PlaybackController?
    private weak var fullscreen: VideoOnlyFullscreenController?
    private weak var controlsVisibility: PlaybackControlsVisibility?
    private var eventMonitor: Any?

    func start(
        with playback: PlaybackController,
        fullscreen: VideoOnlyFullscreenController,
        controlsVisibility: PlaybackControlsVisibility
    ) {
        self.playback = playback
        self.fullscreen = fullscreen
        self.controlsVisibility = controlsVisibility
        guard eventMonitor == nil else { return }

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard playback?.currentItem != nil,
              !isEditingText,
              event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
            return false
        }

        controlsVisibility?.revealTemporarily()

        switch event.keyCode {
        case 49: // Space
            playback?.togglePlayback()
        case 123: // Left arrow
            playback?.skip(by: -5)
        case 124: // Right arrow
            playback?.skip(by: 5)
        case 126: // Up arrow
            playback?.changeVolume(by: 0.05)
        case 125: // Down arrow
            playback?.changeVolume(by: -0.05)
        case 46: // M
            playback?.toggleMute()
        case 3, 36, 76: // F, Return, Enter
            fullscreen?.toggle()
        default:
            return false
        }

        return true
    }

    private var isEditingText: Bool {
        NSApp.keyWindow?.firstResponder is NSTextView
    }
}
