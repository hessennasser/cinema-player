import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class SubtitleController: ObservableObject {
    @Published private(set) var activeCue: SubtitleCue?
    @Published private(set) var loadedSubtitleName: String?
    @Published private(set) var syncOffset: TimeInterval = 0
    @Published var errorMessage: String?

    private var cues: [SubtitleCue] = []
    private var activeCueIndex: Int?
    private var scopedURL: URL?

    var isLoaded: Bool {
        !cues.isEmpty
    }

    var syncOffsetTitle: String {
        let sign = syncOffset >= 0 ? "+" : "−"
        return "\(sign)\(abs(syncOffset).formatted(.number.precision(.fractionLength(1))))s"
    }

    func chooseSubtitle(onLoad: (() -> Void)? = nil) {
        let panel = NSOpenPanel()
        panel.title = "Choose an SRT subtitle"
        panel.message = "Cinema Player reads the subtitle file you choose."
        panel.prompt = "Use Subtitle"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType(filenameExtension: "srt") ?? .plainText]

        guard panel.runModal() == .OK, let url = panel.url else { return }
        if load(from: url) {
            onLoad?()
        }
    }

    @discardableResult
    func load(from url: URL) -> Bool {
        clearAccess()
        errorMessage = nil

        if url.startAccessingSecurityScopedResource() {
            scopedURL = url
        }

        do {
            let source = try String(contentsOf: url, encoding: .utf8)
            cues = try SubtitleParser.parse(source)
            loadedSubtitleName = url.deletingPathExtension().lastPathComponent
            syncOffset = 0
            activeCue = nil
            activeCueIndex = nil
            return true
        } catch {
            clear()
            errorMessage = (error as? LocalizedError)?.errorDescription ?? SubtitleParserError.unreadableFile.errorDescription
            return false
        }
    }

    func update(for playbackTime: TimeInterval) {
        guard isLoaded else { return }

        let subtitleTime = playbackTime + syncOffset
        if let activeCueIndex, cues[activeCueIndex].contains(subtitleTime) {
            return
        }

        let nextIndex = cueIndex(at: subtitleTime)
        activeCueIndex = nextIndex
        activeCue = nextIndex.map { cues[$0] }
    }

    func adjustSync(by seconds: TimeInterval) {
        syncOffset = min(max(syncOffset + seconds, -10), 10)
        activeCue = nil
        activeCueIndex = nil
    }

    func resetSync() {
        syncOffset = 0
        activeCue = nil
        activeCueIndex = nil
    }

    func clear() {
        cues = []
        activeCue = nil
        activeCueIndex = nil
        loadedSubtitleName = nil
        syncOffset = 0
        clearAccess()
    }

    private func cueIndex(at time: TimeInterval) -> Int? {
        var lowerBound = 0
        var upperBound = cues.count

        while lowerBound < upperBound {
            let midpoint = (lowerBound + upperBound) / 2
            if cues[midpoint].startTime <= time {
                lowerBound = midpoint + 1
            } else {
                upperBound = midpoint
            }
        }

        let candidateIndex = lowerBound - 1
        guard candidateIndex >= 0, cues[candidateIndex].contains(time) else {
            return nil
        }
        return candidateIndex
    }

    private func clearAccess() {
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
    }
}
