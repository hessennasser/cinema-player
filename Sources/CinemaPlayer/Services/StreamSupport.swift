import CoreGraphics
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

    /// Content types AVPlayer can open directly, as opposed to a web page
    /// that merely has a video somewhere on it.
    static func isMediaContentType(_ contentType: String, at url: URL) -> Bool {
        let type = contentType.lowercased()

        if type.hasPrefix("video/") || type.hasPrefix("audio/") || type.hasPrefix("application/mp4") {
            return true
        }
        if type.hasPrefix("application/vnd.apple.mpegurl")
            || type.hasPrefix("application/x-mpegurl")
            || type.hasPrefix("application/dash+xml") {
            return true
        }
        // Plenty of hosts serve a movie as an unlabelled blob; trust the
        // extension only when the type says nothing.
        if type.hasPrefix("application/octet-stream") || type.hasPrefix("binary/octet-stream") || type.isEmpty {
            return MediaFileSupport.supportedExtensions.contains(url.pathExtension.lowercased())
                || playlistExtensions.contains(url.pathExtension.lowercased())
        }
        return false
    }

    static func isPageContentType(_ contentType: String) -> Bool {
        let type = contentType.lowercased()
        return type.hasPrefix("text/html") || type.hasPrefix("application/xhtml+xml")
    }

    static let playlistExtensions: Set<String> = ["m3u8", "m3u", "mpd"]

    /// The highest `RESOLUTION` advertised by an HLS master playlist. AVFoundation
    /// exposes no tracks for an HLS asset, so the manifest is the only place the
    /// size can be read before playback starts.
    static func highestManifestResolution(in manifest: String) -> CGSize? {
        var best: CGSize?

        for line in manifest.split(whereSeparator: \.isNewline) {
            guard line.hasPrefix("#EXT-X-STREAM-INF:"),
                  let range = line.range(of: "RESOLUTION=") else { continue }

            let value = line[range.upperBound...].prefix { !$0.isWhitespace && $0 != "," }
            let dimensions = value.split(separator: "x")
            guard dimensions.count == 2,
                  let width = Double(dimensions[0]),
                  let height = Double(dimensions[1]) else { continue }

            if width * height > (best.map { $0.width * $0.height } ?? 0) {
                best = CGSize(width: width, height: height)
            }
        }
        return best
    }

    static func resolutionLabel(for size: CGSize) -> String {
        "\(Int(size.width.rounded())) × \(Int(size.height.rounded()))"
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
