import Foundation

enum SubtitleParserError: LocalizedError, Equatable {
    case unreadableFile
    case noCues

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            "Cinema Player could not read this subtitle file."
        case .noCues:
            "No valid SRT subtitles were found in this file."
        }
    }
}

enum SubtitleParser {
    static func parse(_ source: String) throws -> [SubtitleCue] {
        let normalizedSource = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{FEFF}", with: "")

        let blocks = normalizedSource.components(separatedBy: "\n\n")
        let cues = blocks.compactMap(parseBlock)

        guard !cues.isEmpty else { throw SubtitleParserError.noCues }
        return cues.sorted { $0.startTime < $1.startTime }
    }

    private static func parseBlock(_ block: String) -> SubtitleCue? {
        let lines = block.components(separatedBy: "\n")
        guard let timeRangeIndex = lines.firstIndex(where: { $0.contains("-->") }) else {
            return nil
        }

        let timeRange = lines[timeRangeIndex]
            .components(separatedBy: "-->")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard timeRange.count == 2,
              let startTime = parseTime(timeRange[0]),
              let endTime = parseTime(timeRange[1]),
              endTime > startTime else {
            return nil
        }

        let text = lines
            .dropFirst(timeRangeIndex + 1)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        return SubtitleCue(startTime: startTime, endTime: endTime, text: text)
    }

    private static func parseTime(_ value: String) -> TimeInterval? {
        let sanitizedValue = value
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        let components = sanitizedValue.split(separator: ":", omittingEmptySubsequences: false)

        guard components.count == 3,
              let hours = Double(components[0]),
              let minutes = Double(components[1]),
              let seconds = Double(components[2]),
              hours >= 0,
              minutes >= 0,
              minutes < 60,
              seconds >= 0,
              seconds < 60 else {
            return nil
        }

        return (hours * 3_600) + (minutes * 60) + seconds
    }
}
