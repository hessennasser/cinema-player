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

    /// Content types that are media beyond doubt, so no sniffing is needed.
    static func isDefinitelyMediaContentType(_ contentType: String) -> Bool {
        let type = contentType.lowercased()
        return type.hasPrefix("video/")
            || type.hasPrefix("audio/")
            || type.hasPrefix("application/mp4")
            || type.hasPrefix("application/vnd.apple.mpegurl")
            || type.hasPrefix("application/x-mpegurl")
            || type.hasPrefix("application/dash+xml")
    }

    /// The looser test, which falls back to the extension when the declared
    /// type says nothing. Only for use once the body has told us no more.
    static func isMediaContentType(_ contentType: String, at url: URL) -> Bool {
        if isDefinitelyMediaContentType(contentType) { return true }

        let type = contentType.lowercased()
        guard type.isEmpty
            || type.hasPrefix("application/octet-stream")
            || type.hasPrefix("binary/octet-stream")
            || type.hasPrefix("text/plain") else {
            return false
        }
        let pathExtension = url.pathExtension.lowercased()
        return MediaFileSupport.supportedExtensions.contains(pathExtension)
            || playlistExtensions.contains(pathExtension)
    }

    static func isPageContentType(_ contentType: String) -> Bool {
        let type = contentType.lowercased()
        return type.hasPrefix("text/html") || type.hasPrefix("application/xhtml+xml")
    }

    static let playlistExtensions: Set<String> = ["m3u8", "m3u", "mpd"]

    /// Video codec prefixes, so an audio-only variant is not mistaken for a
    /// rendition the viewer could ever see.
    private static let videoCodecPrefixes = ["avc1", "avc3", "hvc1", "hev1", "dvh1", "dvhe", "av01", "vp08", "vp09"]

    /// The highest `RESOLUTION` a master playlist advertises. AVFoundation
    /// exposes no tracks for an HLS asset, so the manifest is the only place a
    /// size can be read before playback — but this is the ceiling on offer, not
    /// what the viewer will get, so label it as such.
    static func highestManifestResolution(in manifest: String) -> CGSize? {
        var best: CGSize?

        for line in manifest.split(whereSeparator: \.isNewline) {
            // #EXT-X-I-FRAME-STREAM-INF carries a RESOLUTION too, but it is a
            // trick-play track and never a rendition anyone watches.
            guard line.hasPrefix("#EXT-X-STREAM-INF:") else { continue }
            guard let range = line.range(of: "RESOLUTION=") else { continue }
            guard describesVideo(line) else { continue }

            let value = line[range.upperBound...].prefix { !$0.isWhitespace && $0 != "," }
            let dimensions = value.split(separator: "x")
            guard dimensions.count == 2,
                  let width = Double(dimensions[0]),
                  let height = Double(dimensions[1]),
                  width > 0, height > 0 else {
                continue
            }

            if width * height > (best.map { $0.width * $0.height } ?? 0) {
                best = CGSize(width: width, height: height)
            }
        }
        return best
    }

    private static func describesVideo(_ line: Substring) -> Bool {
        guard let range = line.range(of: "CODECS=\"") else {
            return true  // No codec list at all; the RESOLUTION is all we have.
        }
        let codecs = line[range.upperBound...].prefix { $0 != "\"" }.lowercased()
        return videoCodecPrefixes.contains { codecs.contains($0) }
    }

    static func resolutionLabel(for size: CGSize) -> String {
        "\(Int(size.width.rounded())) × \(Int(size.height.rounded()))"
    }

    /// A ceiling rather than a measurement, worded so nobody reads it as the
    /// resolution they are actually being served.
    static func advertisedResolutionLabel(for size: CGSize) -> String {
        "Up to \(resolutionLabel(for: size))"
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
