import AppKit
import Foundation

struct VideoPresentation {
    let thumbnail: NSImage?
    let duration: Double?
    let resolution: String?
    let fileSize: String?
    let format: String
    var isStream = false

    var detailLine: String {
        var parts: [String?] = [duration.map(TimeFormatter.string), resolution, fileSize, format]
        if isStream { parts.append("Stream") }
        return parts
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

enum TimeFormatter {
    static func string(for seconds: Double) -> String {
        let totalSeconds = max(Int(seconds.rounded(.down)), 0)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let remainingSeconds = totalSeconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
            : String(format: "%d:%02d", minutes, remainingSeconds)
    }
}
