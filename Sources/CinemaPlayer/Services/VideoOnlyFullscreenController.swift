@preconcurrency import AppKit
import Foundation

@MainActor
final class VideoOnlyFullscreenController: ObservableObject {
    @Published private(set) var isActive = false

    init() {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didExitFullScreenNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isActive = false
            }
        }
    }

    func toggle() {
        isActive ? exit() : enter()
    }

    private func enter() {
        guard let window = NSApp.keyWindow else { return }
        isActive = true

        DispatchQueue.main.async {
            window.toggleFullScreen(nil)
        }
    }

    private func exit() {
        NSApp.keyWindow?.toggleFullScreen(nil)
    }
}
