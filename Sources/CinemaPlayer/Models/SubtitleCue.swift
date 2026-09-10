import Foundation

struct SubtitleCue: Equatable, Sendable {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String

    func contains(_ time: TimeInterval) -> Bool {
        time >= startTime && time < endTime
    }
}

struct EmbeddedSubtitleTrack: Identifiable, Equatable {
    let id: String
    let title: String
}
