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

    /// Every quality a master playlist advertises, best first and one entry per
    /// resolution. AVFoundation exposes no tracks for an HLS asset, so the
    /// manifest is the only place these can be read.
    static func manifestRenditions(in manifest: String) -> [StreamRendition] {
        var byHeight: [Int: StreamRendition] = [:]

        for line in manifest.split(whereSeparator: \.isNewline) {
            // #EXT-X-I-FRAME-STREAM-INF carries a RESOLUTION too, but it is a
            // trick-play track and never a rendition anyone watches.
            guard line.hasPrefix("#EXT-X-STREAM-INF:"), describesVideo(line) else { continue }
            guard let size = resolution(in: line) else { continue }

            let rendition = StreamRendition(size: size, peakBitRate: bandwidth(in: line))
            // Several variants can share a resolution; keep the richest one so
            // pinning to it does not cap the bitrate below what is on offer.
            if let existing = byHeight[rendition.height],
               (existing.peakBitRate ?? 0) >= (rendition.peakBitRate ?? 0) {
                continue
            }
            byHeight[rendition.height] = rendition
        }

        return byHeight.values.sorted { $0.height > $1.height }
    }

    /// The ceiling on offer, which is not what the viewer is necessarily served.
    static func highestManifestResolution(in manifest: String) -> CGSize? {
        manifestRenditions(in: manifest).first?.size
    }

    private static func resolution(in line: Substring) -> CGSize? {
        guard let range = line.range(of: "RESOLUTION=") else { return nil }

        let value = line[range.upperBound...].prefix { !$0.isWhitespace && $0 != "," }
        let dimensions = value.split(separator: "x")
        guard dimensions.count == 2,
              let width = Double(dimensions[0]),
              let height = Double(dimensions[1]),
              width > 0, height > 0 else {
            return nil
        }
        return CGSize(width: width, height: height)
    }

    private static func bandwidth(in line: Substring) -> Double? {
        // AVERAGE-BANDWIDTH would understate a variable-rate rendition.
        guard let range = line.range(of: "\nBANDWIDTH=") ?? line.range(of: ",BANDWIDTH=") ?? line.range(of: ":BANDWIDTH=") else {
            return nil
        }
        let value = line[range.upperBound...].prefix { $0.isNumber }
        return Double(value)
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
