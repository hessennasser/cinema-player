import Foundation
import UniformTypeIdentifiers

/// Opening a subtitle file, which is fussier than it looks: the extensions are
/// not registered types on every Mac, and subtitle files are routinely not
/// UTF-8 — a release subtitled in Arabic or Cyrillic often is not.
enum SubtitleFileSupport {
    static let supportedExtensions: Set<String> = ["srt", "vtt"]

    /// `.vtt` and `.srt` have no guaranteed system type, so the panel is given
    /// whatever the Mac does know plus plain text, and the choice is checked
    /// on the way in instead.
    static var openPanelTypes: [UTType] {
        let declared = supportedExtensions.compactMap { UTType(filenameExtension: $0) }
        return declared.isEmpty ? [.plainText, .text] : declared + [.plainText, .text]
    }

    static func isSupported(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    /// Tries UTF-8, then lets the system identify the encoding, then falls back
    /// to Windows-1256. Beyond UTF-8 this is best effort: a single-byte encoding
    /// accepts any bytes at all, so nothing after the system's own guess could
    /// ever be reached by "did it decode" alone.
    static func readText(at url: URL) throws -> String {
        let data = try Data(contentsOf: url)

        if let text = String(data: data, encoding: .utf8) {
            return text
        }

        var detected = String.Encoding.utf8
        if let text = try? String(contentsOf: url, usedEncoding: &detected) {
            return text
        }

        // Subtitles for Arabic releases are commonly saved this way, and it is
        // the encoding a Mac is least likely to identify on its own.
        if let text = String(data: data, encoding: .windowsArabic) {
            return text
        }
        throw SubtitleParserError.unreadableFile
    }
}

private extension String.Encoding {
    /// Windows-1256. Foundation exposes 1250-1254 as constants but not this one.
    static let windowsArabic = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.windowsArabic.rawValue)
        )
    )
}
