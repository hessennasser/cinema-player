import Foundation

/// Recognises the remote addresses Cinema Player can hand to AVPlayer, so a
/// video can come from a link as easily as from the Movies folder.
enum StreamSupport {
    static let supportedSchemes: Set<String> = ["http", "https"]

    /// Names that carry no meaning on their own, so the host reads better.
    private static let genericNames: Set<String> = [
        "index", "manifest", "master", "media", "play", "playlist", "stream", "video", "watch",
    ]

    /// Turns typed or pasted text into a streamable URL, filling in `https://`
    /// when the address omits a scheme.
    static func streamURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let escaped = trimmed.replacingOccurrences(of: " ", with: "%20")
        let candidate = escaped.contains("://") ? escaped : "https://\(escaped)"

        guard let url = URL(string: candidate), isStreamable(url) else { return nil }
        return url
    }

    static func isStreamable(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), supportedSchemes.contains(scheme) else { return false }
        guard let host = url.host, !host.isEmpty else { return false }
        return true
    }

    /// A readable library title for a stream, taken from the last path
    /// component and falling back to the host when that says nothing.
    static func title(for url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
        let readableName = (name.removingPercentEncoding ?? name)
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespaces)

        guard !readableName.isEmpty,
              readableName != "/",
              !genericNames.contains(readableName.lowercased()) else {
            return url.host ?? url.absoluteString
        }
        return readableName
    }

    /// The short format badge shown in the library row.
    static func formatLabel(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "m3u8", "m3u": "HLS"
        case "": "LINK"
        default: url.pathExtension.uppercased()
        }
    }
}
