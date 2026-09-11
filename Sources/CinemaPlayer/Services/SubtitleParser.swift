import Foundation

enum SubtitleParserError: LocalizedError, Equatable {
    case unreadableFile
    case noCues

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            "Cinema Player could not read this subtitle file."
        case .noCues:
            "No subtitles were found in this file. Cinema Player reads SubRip (.srt) and WebVTT (.vtt)."
        }
    }
}

/// Reads SubRip and WebVTT, which differ in small ways that both formats
/// tolerate: the millisecond separator, an optional hours field, cue settings
/// trailing the timestamp, and inline markup.
enum SubtitleParser {
    /// Blocks that carry no cue. NOTE in particular can hold free text with an
    /// arrow in it, so these are skipped by name rather than by shape.
    private static let headerKeywords = ["WEBVTT", "NOTE", "STYLE", "REGION"]

    static func parse(_ source: String) throws -> [SubtitleCue] {
        let normalizedSource = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let blocks = normalizedSource.components(separatedBy: "\n\n")
        let cues = blocks.compactMap(parseBlock)

        guard !cues.isEmpty else { throw SubtitleParserError.noCues }
        return cues.sorted { $0.startTime < $1.startTime }
    }

    private static func parseBlock(_ block: String) -> SubtitleCue? {
        let lines = block.components(separatedBy: "\n")
        guard let firstLine = lines.first?.trimmingCharacters(in: .whitespaces),
              !headerKeywords.contains(where: { firstLine == $0 || firstLine.hasPrefix("\($0) ") }) else {
            return nil
        }

        guard let timeRangeIndex = lines.firstIndex(where: { $0.contains("-->") }) else {
            return nil
        }

        let timeRange = lines[timeRangeIndex]
            .components(separatedBy: "-->")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard timeRange.count == 2,
              let startTime = parseTime(timeRange[0]),
              // WebVTT allows cue settings after the end time — "align:start
              // position:10%" — which are none of the parser's business.
              let endTime = parseTime(timeRange[1].prefix { !$0.isWhitespace }) else {
            return nil
        }
        guard endTime > startTime else { return nil }

        let text = plainText(
            from: lines
                .dropFirst(timeRangeIndex + 1)
                .joined(separator: "\n")
        )
        guard !text.isEmpty else { return nil }

        return SubtitleCue(startTime: startTime, endTime: endTime, text: text)
    }

    /// Accepts `HH:MM:SS.mmm` and the `MM:SS.mmm` WebVTT also permits, with
    /// either a comma or a full stop before the milliseconds.
    private static func parseTime<S: StringProtocol>(_ value: S) -> TimeInterval? {
        let sanitizedValue = value
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        let components = sanitizedValue.split(separator: ":", omittingEmptySubsequences: false)

        let hoursText: Substring
        let minutesText: Substring
        let secondsText: Substring
        switch components.count {
        case 3:
            (hoursText, minutesText, secondsText) = (components[0], components[1], components[2])
        case 2:
            (hoursText, minutesText, secondsText) = ("0", components[0], components[1])
        default:
            return nil
        }

        guard let hours = Double(hoursText),
              let minutes = Double(minutesText),
              let seconds = Double(secondsText),
              hours >= 0,
              minutes >= 0,
              minutes < 60,
              seconds >= 0,
              seconds < 60 else {
            return nil
        }

        return (hours * 3_600) + (minutes * 60) + seconds
    }

    /// Cue payloads carry markup in both formats — `<i>` and `<b>` in SubRip,
    /// plus voice, class and timestamp spans in WebVTT — none of which the
    /// overlay renders, so showing it raw would be worse than dropping it.
    private static func plainText(from payload: String) -> String {
        var text = payload.replacingOccurrences(
            of: "<[^>]*>",
            with: "",
            options: .regularExpression
        )

        for (entity, character) in [
            ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"),
            ("&apos;", "'"), ("&nbsp;", "\u{00A0}"), ("&lrm;", "\u{200E}"), ("&rlm;", "\u{200F}"),
        ] {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        // Ampersands last, so "&amp;lt;" survives as the text "&lt;".
        text = text.replacingOccurrences(of: "&amp;", with: "&")

        return text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
