import Foundation

struct ResolvedVideo {
    let url: URL
    let title: String
}

enum StreamLinkError: LocalizedError {
    case notAnAddress
    case playerOnlySite(String)
    case unreachable(String)
    case insecurePage
    case noVideoOnPage(String)

    var errorDescription: String? {
        switch self {
        case .notAnAddress:
            "That does not look like a video link. Paste an address that starts with http:// or https://."
        case let .playerOnlySite(service):
            "\(service) videos play only inside \(service)'s own player, so Cinema Player cannot open this link. A direct link to a video file or an HLS playlist works."
        case let .unreachable(reason):
            "Cinema Player could not reach that link: \(reason)"
        case .insecurePage:
            "Cinema Player reads pages over https only. An http link straight to a video file still plays." 
        case let .noVideoOnPage(host):
            "That page on \(host) does not offer a video Cinema Player can open. Look for a direct link to the video file itself."
        }
    }
}

/// Turns a pasted link into something AVPlayer can open. A direct media link is
/// used as it is; an ordinary web page is read for the video it advertises.
enum PageVideoResolver {
    private static let requestTimeout: TimeInterval = 15
    private static let maximumPageBytes = 8 * 1_024 * 1_024

    /// Sites that hand their video to their own player and never expose a
    /// stream we could open, so guessing wastes the user's time.
    private static let playerOnlyHosts: [String: String] = [
        "youtube.com": "YouTube",
        "youtu.be": "YouTube",
        "vimeo.com": "Vimeo",
        "twitch.tv": "Twitch",
        "netflix.com": "Netflix",
        "dailymotion.com": "Dailymotion",
        "tiktok.com": "TikTok",
        "instagram.com": "Instagram",
        "facebook.com": "Facebook",
        "disneyplus.com": "Disney+",
    ]

    static func resolve(_ url: URL) async throws -> ResolvedVideo {
        if let service = playerOnlyService(for: url) {
            throw StreamLinkError.playerOnlySite(service)
        }

        let linkType = try await contentType(of: url)
        if StreamSupport.isMediaContentType(linkType, at: url) {
            return ResolvedVideo(url: url, title: StreamSupport.title(for: url))
        }

        guard StreamSupport.isPageContentType(linkType) else {
            throw StreamLinkError.noVideoOnPage(url.host ?? "that host")
        }

        let page = try await loadPage(url)
        guard let candidate = videoURL(inHTML: page, relativeTo: url) else {
            throw StreamLinkError.noVideoOnPage(url.host ?? "that host")
        }

        // A page often advertises another page — an embedded player, say — so
        // the candidate has to prove it is really media.
        let candidateType = try await contentType(of: candidate)
        guard StreamSupport.isMediaContentType(candidateType, at: candidate) else {
            throw StreamLinkError.noVideoOnPage(url.host ?? "that host")
        }

        return ResolvedVideo(
            url: candidate,
            title: pageTitle(inHTML: page) ?? StreamSupport.title(for: candidate)
        )
    }

    static func playerOnlyService(for url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }

        return playerOnlyHosts.first { knownHost, _ in
            host == knownHost || host.hasSuffix(".\(knownHost)")
        }?.value
    }

    /// The video a page advertises, in the order of how reliable each hint is.
    static func videoURL(inHTML html: String, relativeTo pageURL: URL) -> URL? {
        let metadata = metaTags(inHTML: html)
        let metaKeys = [
            "og:video:secure_url", "og:video:url", "og:video",
            "twitter:player:stream",
        ]

        let candidates = metaKeys.compactMap { metadata[$0] } + embeddedSourceValues(inHTML: html)

        for candidate in candidates {
            guard let url = absoluteURL(candidate, relativeTo: pageURL),
                  StreamSupport.isStreamable(url),
                  url.absoluteString != pageURL.absoluteString else {
                continue
            }
            return url
        }
        return nil
    }

    static func pageTitle(inHTML html: String) -> String? {
        if let ogTitle = metaTags(inHTML: html)["og:title"], !ogTitle.isEmpty {
            return decodeEntities(ogTitle)
        }

        guard let match = firstMatch(#"<title[^>]*>([\s\S]*?)</title>"#, in: html, group: 1) else {
            return nil
        }
        let title = decodeEntities(match).trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
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

    private static func embeddedSourceValues(inHTML html: String) -> [String] {
        let patterns = [
            #"<video\b[^>]*\bsrc\s*=\s*["']([^"']+)["']"#,
            #"<source\b[^>]*\bsrc\s*=\s*["']([^"']+)["']"#,
            #""contentUrl"\s*:\s*"([^"]+)""#,
        ]
        return patterns.flatMap { allMatches($0, in: html, group: 1) }.map(decodeEntities)
    }

    private static func absoluteURL(_ value: String, relativeTo pageURL: URL) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("//") {
            return URL(string: "\(pageURL.scheme ?? "https"):\(trimmed)")
        }
        return URL(string: trimmed, relativeTo: pageURL)?.absoluteURL
    }

    private static func decodeEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#38;", with: "&")
            .replacingOccurrences(of: "&#x26;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "\\/", with: "/")
    }

    private static func contentType(of url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = requestTimeout

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return "" }

            // Not every host answers HEAD; a one-byte range works everywhere.
            if http.statusCode == 405 || http.statusCode == 501 {
                return try await contentTypeByRange(of: url)
            }
            guard (200..<400).contains(http.statusCode) else {
                throw StreamLinkError.unreachable("the host answered \(http.statusCode).")
            }
            return http.value(forHTTPHeaderField: "Content-Type") ?? ""
        } catch let error as StreamLinkError {
            throw error
        } catch {
            throw transportError(error)
        }
    }

    private static func transportError(_ error: Error) -> StreamLinkError {
        let code = (error as NSError).code
        if code == NSURLErrorAppTransportSecurityRequiresSecureConnection {
            return .insecurePage
        }
        return .unreachable(error.localizedDescription)
    }

    private static func contentTypeByRange(of url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        request.timeoutInterval = requestTimeout

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return "" }
        guard (200..<400).contains(http.statusCode) else {
            throw StreamLinkError.unreachable("the host answered \(http.statusCode).")
        }
        return http.value(forHTTPHeaderField: "Content-Type") ?? ""
    }

    private static func loadPage(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = requestTimeout

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<400).contains(http.statusCode) {
                throw StreamLinkError.unreachable("the host answered \(http.statusCode).")
            }
            return String(decoding: data.prefix(maximumPageBytes), as: UTF8.self)
        } catch let error as StreamLinkError {
            throw error
        } catch {
            throw transportError(error)
        }
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
