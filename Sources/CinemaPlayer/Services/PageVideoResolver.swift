import Foundation

struct ResolvedVideo {
    let url: URL
    let title: String
    /// True when the host will not serve byte ranges, so AVPlayer cannot stream
    /// the file and Cinema Player has to fetch a local copy first.
    let needsLocalCopy: Bool
}

enum StreamLinkError: LocalizedError {
    case notAnAddress
    case unsupportedProvider(String)
    case noVideoOnPage(String)
    case playerBuiltInJavaScript(String)
    case drmProtected
    case accessExpired
    case http(StreamHTTPError)

    var errorDescription: String? {
        switch self {
        case .notAnAddress:
            "That does not look like a video link. Paste an address that starts with http:// or https://."
        case let .unsupportedProvider(service):
            "Cinema Player does not support \(service) links. Sites like it hand video to their own player, which needs a provider-specific extractor, a signed-in session, or DRM that only that player can open."
        case let .noVideoOnPage(host):
            "That page on \(host) does not expose a video Cinema Player can open. A direct link to the video file or an HLS playlist works."
        case let .playerBuiltInJavaScript(host):
            "That page on \(host) points only at an embedded player, not at a video. Pages like it build the real address in JavaScript when the player runs, and Cinema Player reads pages without running their scripts. A direct link to the video file or an HLS playlist works."
        case .drmProtected:
            "That stream is DRM-protected and can only be played by its authorised provider."
        case .accessExpired:
            "That video link has expired or needs to be opened through its original website."
        case let .http(error):
            error.errorDescription
        }
    }
}

/// Turns a pasted link into something AVPlayer can open. A direct media link is
/// used as it is; an ordinary web page is read for the video it advertises.
enum PageVideoResolver {
    /// Providers that hand video to their own player. Not a claim that their
    /// video is impossible to obtain — only that doing so needs a per-provider
    /// extractor, an authenticated session, or DRM support that this app has no
    /// business reimplementing.
    private static let unsupportedProviders: [String: String] = [
        "youtube.com": "YouTube",
        "youtu.be": "YouTube",
        "twitch.tv": "Twitch",
        "netflix.com": "Netflix",
        "disneyplus.com": "Disney+",
        "primevideo.com": "Prime Video",
        "hulu.com": "Hulu",
        "tiktok.com": "TikTok",
        "instagram.com": "Instagram",
        "facebook.com": "Facebook",
    ]

    static func resolve(_ url: URL) async throws -> ResolvedVideo {
        if let service = unsupportedProvider(for: url) {
            throw StreamLinkError.unsupportedProvider(service)
        }

        let probe: LinkProbe
        do {
            probe = try await StreamHTTP.probe(url)
        } catch let error as StreamHTTPError {
            throw StreamLinkError.http(error)
        }

        switch probe.kind {
        case .media:
            return try await resolvedMedia(probe)
        case .page:
            return try await resolveFromPage(probe)
        case .unknown:
            throw StreamLinkError.noVideoOnPage(url.host ?? "that host")
        }
    }

    private static func resolvedMedia(_ probe: LinkProbe) async throws -> ResolvedVideo {
        if try await isDRMProtected(probe) {
            throw StreamLinkError.drmProtected
        }

        return ResolvedVideo(
            url: probe.finalURL,
            title: StreamSupport.title(for: probe.finalURL),
            // HLS is fetched segment by segment and never needs ranges.
            needsLocalCopy: !probe.supportsRanges && !isPlaylist(probe)
        )
    }

    private static func resolveFromPage(_ probe: LinkProbe) async throws -> ResolvedVideo {
        let host = probe.finalURL.host ?? "that host"

        let page: String
        do {
            page = try await StreamHTTP.page(at: probe.finalURL)
        } catch let error as StreamHTTPError {
            throw StreamLinkError.http(error)
        }

        let candidates = videoURLs(inHTML: page, relativeTo: probe.finalURL)
        guard !candidates.isEmpty else {
            throw StreamLinkError.noVideoOnPage(host)
        }

        // A page often advertises another page — an embedded player, say — so
        // each candidate has to prove it is really media.
        var lastFailure: Error?
        var sawEmbeddedPage = false
        for candidate in candidates {
            do {
                let candidateProbe = try await StreamHTTP.probe(candidate)
                guard candidateProbe.kind == .media else {
                    if candidateProbe.kind == .page { sawEmbeddedPage = true }
                    continue
                }

                let media = try await resolvedMedia(candidateProbe)
                return ResolvedVideo(
                    url: media.url,
                    title: pageTitle(inHTML: page) ?? media.title,
                    needsLocalCopy: media.needsLocalCopy
                )
            } catch {
                lastFailure = error
                continue
            }
        }

        if let drm = lastFailure as? StreamLinkError, case .drmProtected = drm {
            throw drm
        }
        // The page advertised something, but every candidate was another page —
        // the signature of a player that assembles its address in script.
        throw sawEmbeddedPage
            ? StreamLinkError.playerBuiltInJavaScript(host)
            : StreamLinkError.noVideoOnPage(host)
    }

    /// A playlist whose segments are locked needs a provider's own player.
    private static func isDRMProtected(_ probe: LinkProbe) async throws -> Bool {
        guard isPlaylist(probe) else { return false }

        guard let manifest = try? await StreamHTTP.manifest(at: probe.finalURL) else { return false }
        return manifest.contains("#EXT-X-SESSION-KEY")
            || manifest.range(of: #"#EXT-X-KEY:(?!METHOD=NONE)"#, options: .regularExpression) != nil
    }

    private static func isPlaylist(_ probe: LinkProbe) -> Bool {
        StreamSupport.playlistExtensions.contains(probe.finalURL.pathExtension.lowercased())
            || probe.contentType.lowercased().contains("mpegurl")
            || probe.contentType.lowercased().contains("dash+xml")
    }

    static func unsupportedProvider(for url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }

        return unsupportedProviders.first { knownHost, _ in
            host == knownHost || host.hasSuffix(".\(knownHost)")
        }?.value
    }

    // MARK: - Extraction

    /// Every video a page advertises, best hint first and duplicates removed.
    /// JSON-LD leads because a publisher writes it to describe the work itself;
    /// the social-card tags follow; the markup is the last resort because a
    /// `<video>` can just as easily be a background loop.
    static func videoURLs(inHTML html: String, relativeTo pageURL: URL) -> [URL] {
        let base = baseURL(inHTML: html, relativeTo: pageURL) ?? pageURL
        let metadata = metaTags(inHTML: html)

        let ordered =
            allMatches(#""contentUrl"\s*:\s*"([^"]+)""#, in: html, group: 1).map(decodeEntities)
            + ["og:video:secure_url", "og:video:url", "og:video", "twitter:player:stream"]
                .compactMap { metadata[$0] }
            + sourceValues(inHTML: html)

        var seen = Set<String>()
        var urls: [URL] = []
        for candidate in ordered {
            guard let url = absoluteURL(candidate, relativeTo: base),
                  !StreamAddressPolicy.isObviouslyLocal(url),
                  url.absoluteString != pageURL.absoluteString,
                  seen.insert(url.absoluteString).inserted else {
                continue
            }
            urls.append(url)
        }
        return preferPlayableFormats(urls)
    }

    /// AVFoundation opens some containers and not others, so a page offering
    /// several `<source>` formats should be tried in an order that works.
    private static func preferPlayableFormats(_ urls: [URL]) -> [URL] {
        urls.enumerated()
            .sorted { left, right in
                let leftRank = formatRank(left.element)
                let rightRank = formatRank(right.element)
                return leftRank == rightRank ? left.offset < right.offset : leftRank < rightRank
            }
            .map(\.element)
    }

    private static func formatRank(_ url: URL) -> Int {
        switch url.pathExtension.lowercased() {
        case "mp4", "m4v", "mov": 0
        case "m3u8", "m3u": 1
        case "": 2
        case "webm", "mkv", "ogv", "ogg": 4
        default: 3
        }
    }

    static func pageTitle(inHTML html: String) -> String? {
        if let ogTitle = metaTags(inHTML: html)["og:title"], !ogTitle.isEmpty {
            return ogTitle
        }

        guard let match = firstMatch(#"<title[^>]*>([\s\S]*?)</title>"#, in: html, group: 1) else {
            return nil
        }
        let title = decodeEntities(match).trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    /// `<base href>` changes what every relative address on the page means.
    static func baseURL(inHTML html: String, relativeTo pageURL: URL) -> URL? {
        guard let tag = firstMatch(#"<base\b[^>]*>"#, in: html, group: 0),
              let href = firstMatch(#"href\s*=\s*["']([^"']+)["']"#, in: tag, group: 1) else {
            return nil
        }
        return absoluteURL(decodeEntities(href), relativeTo: pageURL)
    }

    private static func metaTags(inHTML html: String) -> [String: String] {
        var tags: [String: String] = [:]

        for tag in allMatches(#"<meta\b[^>]*>"#, in: html, group: 0) {
            guard let name = firstMatch(#"(?:property|name)\s*=\s*["']([^"']+)["']"#, in: tag, group: 1),
                  let content = firstMatch(#"content\s*=\s*["']([^"']*)["']"#, in: tag, group: 1) else {
                continue
            }
            // The first occurrence wins; pages repeat og tags for each rendition.
            if tags[name.lowercased()] == nil {
                tags[name.lowercased()] = decodeEntities(content)
            }
        }
        return tags
    }

    private static func sourceValues(inHTML html: String) -> [String] {
        let patterns = [
            #"<video\b[^>]*\bsrc\s*=\s*["']([^"']+)["']"#,
            #"<source\b[^>]*\bsrc\s*=\s*["']([^"']+)["']"#,
        ]
        return patterns.flatMap { allMatches($0, in: html, group: 1) }.map(decodeEntities)
    }

    private static func absoluteURL(_ value: String, relativeTo base: URL) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("data:"), !trimmed.hasPrefix("blob:") else { return nil }

        if trimmed.hasPrefix("//") {
            return URL(string: "\(base.scheme ?? "https"):\(trimmed)")
        }
        return URL(string: trimmed, relativeTo: base)?.absoluteURL
    }

    private static func decodeEntities(_ value: String) -> String {
        var decoded = value
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "&#38;", with: "&")
            .replacingOccurrences(of: "&#x26;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#34;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
        // Ampersands last, so "&amp;quot;" does not become a quote.
        decoded = decoded.replacingOccurrences(of: "&amp;", with: "&")
        return decoded
    }

    private static func firstMatch(_ pattern: String, in text: String, group: Int) -> String? {
        allMatches(pattern, in: text, group: group, limit: 1).first
    }

    private static func allMatches(_ pattern: String, in text: String, group: Int, limit: Int = .max) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        var results: [String] = []
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        regex.enumerateMatches(in: text, range: range) { match, _, stop in
            guard let match, let matchRange = Range(match.range(at: group), in: text) else { return }
            results.append(String(text[matchRange]))
            if results.count >= limit { stop.pointee = true }
        }
        return results
    }
}
