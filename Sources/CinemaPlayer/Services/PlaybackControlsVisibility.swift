@preconcurrency import AppKit
import Foundation

@MainActor
final class PlaybackControlsVisibility: ObservableObject {
    @Published private(set) var isVisible = true

    private var hideTask: Task<Void, Never>?
    private var mouseMonitor: Any?

    func startMonitoring() {
        guard mouseMonitor == nil else {
            revealTemporarily()
            return
        }

        mouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel]
        ) { [weak self] event in
            Task { @MainActor in
                self?.revealTemporarily()
            }
            return event
        }
        revealTemporarily()
    }

    func stopMonitoring() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
        }
        mouseMonitor = nil
        hideTask?.cancel()
        hideTask = nil
        isVisible = true
    }

    func revealTemporarily() {
        isVisible = true
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            self?.isVisible = false
        }
    }
}
