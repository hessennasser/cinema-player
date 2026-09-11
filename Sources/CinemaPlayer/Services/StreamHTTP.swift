import Foundation

/// What a link turned out to be once the host was asked.
struct LinkProbe {
    enum Kind: Equatable {
        case media
        case page
        case unknown
    }

    let finalURL: URL
    let contentType: String
    let kind: Kind
    /// False when the host ignores `Range`, which stops AVPlayer from streaming
    /// a progressive file whose moov atom sits at the end.
    let supportsRanges: Bool
    let expectedSize: Int64?
}

enum StreamHTTPError: LocalizedError {
    case blockedAddress(String)
    case tooManyRedirects
    case tooLarge
    case status(Int)
    case transport(String)
    case insecure

    var errorDescription: String? {
        switch self {
        case let .blockedAddress(reason):
            "Cinema Player will not open that link because \(reason)."
        case .tooManyRedirects:
            "That link redirects too many times."
        case .tooLarge:
            "That page is too large for Cinema Player to read."
        case let .status(code):
            "The host answered \(code)."
        case let .transport(reason):
            reason
        case .insecure:
            "Cinema Player reads pages over https only. An http link straight to a video file still plays."
        }
    }
}

/// Every network read the resolver performs. Redirects are re-checked against
/// the address policy, bodies are capped, and nothing is trusted on the
/// strength of a file extension alone.
enum StreamHTTP {
    static let timeout: TimeInterval = 15
    static let maximumRedirects = 5
    static let maximumPageBytes = 2 * 1_024 * 1_024
    static let maximumManifestBytes = 1_024 * 1_024
    private static let probeBytes = 65_535

    // MARK: - Probing

    /// Asks what a link is: HEAD first, then a ranged GET when HEAD is refused
    /// or says nothing useful. The body's first bytes settle the ambiguous cases.
    static func probe(_ url: URL) async throws -> LinkProbe {
        try check(url)

        if let head = try? await headProbe(url), head.kind != .unknown {
            return head
        }
        return try await rangeProbe(url)
    }

    private static func headProbe(_ url: URL) async throws -> LinkProbe {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = timeout

        let (_, response) = try await send(request)
        let contentType = response.value(forHTTPHeaderField: "Content-Type") ?? ""
        let finalURL = response.url ?? url

        guard (200..<300).contains(response.statusCode) else {
            // A refused HEAD is not an error; a refused GET will be.
            if [403, 405, 501].contains(response.statusCode) {
                return LinkProbe(finalURL: finalURL, contentType: "", kind: .unknown, supportsRanges: false, expectedSize: nil)
            }
            throw StreamHTTPError.status(response.statusCode)
        }

        return LinkProbe(
            finalURL: finalURL,
            contentType: contentType,
            kind: kind(forContentType: contentType, at: finalURL, body: nil),
            supportsRanges: response.value(forHTTPHeaderField: "Accept-Ranges")?.lowercased().contains("bytes") == true,
            expectedSize: response.expectedContentLength >= 0 ? response.expectedContentLength : nil
        )
    }

    private static func rangeProbe(_ url: URL) async throws -> LinkProbe {
        var request = URLRequest(url: url)
        request.setValue("bytes=0-\(probeBytes)", forHTTPHeaderField: "Range")
        request.timeoutInterval = timeout

        let (data, response) = try await send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw StreamHTTPError.status(response.statusCode)
        }

        let contentType = response.value(forHTTPHeaderField: "Content-Type") ?? ""
        let finalURL = response.url ?? url
        // A host that honours the range answers 206 with only the bytes asked for.
        let honoursRange = response.statusCode == 206

        return LinkProbe(
            finalURL: finalURL,
            contentType: contentType,
            kind: kind(forContentType: contentType, at: finalURL, body: data),
            supportsRanges: honoursRange,
            expectedSize: contentRangeTotal(response) ?? (response.expectedContentLength >= 0 ? response.expectedContentLength : nil)
        )
    }

    private static func contentRangeTotal(_ response: HTTPURLResponse) -> Int64? {
        guard let header = response.value(forHTTPHeaderField: "Content-Range"),
              let total = header.split(separator: "/").last else {
            return nil
        }
        return Int64(total)
    }

    /// The declared type decides when it is specific; otherwise the leading
    /// bytes do, because plenty of hosts label a movie `application/octet-stream`
    /// or a playlist `text/plain`.
    static func kind(forContentType contentType: String, at url: URL, body: Data?) -> LinkProbe.Kind {
        if StreamSupport.isPageContentType(contentType) {
            return .page
        }
        if StreamSupport.isDefinitelyMediaContentType(contentType) {
            return .media
        }

        if let body, let sniffed = sniff(body) {
            return sniffed
        }
        if StreamSupport.isMediaContentType(contentType, at: url) {
            return .media
        }
        return .unknown
    }

    /// Magic numbers for the containers AVFoundation opens, plus HTML.
    static func sniff(_ data: Data) -> LinkProbe.Kind? {
        let head = [UInt8](data.prefix(16))
        guard head.count >= 8 else { return nil }

        // ISO base media (MP4, M4V, MOV) carries "ftyp" at offset 4.
        if head[4...7] == [0x66, 0x74, 0x79, 0x70] { return .media }
        // Matroska and WebM share an EBML header.
        if head[0...3] == [0x1A, 0x45, 0xDF, 0xA3] { return .media }
        // RIFF....AVI
        if head[0...3] == [0x52, 0x49, 0x46, 0x46], head.count >= 12, head[8...11] == [0x41, 0x56, 0x49, 0x20] { return .media }
        // MPEG transport stream
        if head[0] == 0x47 { return .media }
        // QuickTime with a leading moov/mdat
        if head[4...7] == [0x6D, 0x6F, 0x6F, 0x76] || head[4...7] == [0x6D, 0x64, 0x61, 0x74] { return .media }

        let text = String(decoding: data.prefix(1_024), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#EXTM3U") { return .media }

        let lowered = text.lowercased()
        if lowered.hasPrefix("<!doctype html") || lowered.hasPrefix("<html") || lowered.hasPrefix("<?xml") && lowered.contains("<html") {
            return .page
        }
        return nil
    }

    // MARK: - Bodies

    static func page(at url: URL) async throws -> String {
        let data = try await body(at: url, limit: maximumPageBytes)
        return String(decoding: data, as: UTF8.self)
    }

    static func manifest(at url: URL) async throws -> String {
        let data = try await body(at: url, limit: maximumManifestBytes)
        return String(decoding: data, as: UTF8.self)
    }

    /// Reads a body no larger than `limit`. A declared length over the cap is
    /// refused before anything is downloaded; an undeclared one is read byte by
    /// byte so it can be stopped the moment it goes over.
    private static func body(at url: URL, limit: Int) async throws -> Data {
        try check(url)

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout

        let delegate = RedirectGuard()
        do {
            let (stream, response) = try await URLSession.shared.bytes(for: request, delegate: delegate)
            guard let http = response as? HTTPURLResponse else {
                throw StreamHTTPError.transport("The host gave no usable answer.")
            }
            guard (200..<300).contains(http.statusCode) else {
                throw StreamHTTPError.status(http.statusCode)
            }
            if http.expectedContentLength > Int64(limit) {
                throw StreamHTTPError.tooLarge
            }

            var data = Data()
            data.reserveCapacity(min(limit, 256 * 1_024))
            for try await byte in stream {
                data.append(byte)
                if data.count > limit {
                    throw StreamHTTPError.tooLarge
                }
            }
            return data
        } catch let error as StreamHTTPError {
            throw error
        } catch {
            throw translate(error)
        }
    }

    // MARK: - Plumbing

    private static func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await URLSession.shared.data(for: request, delegate: RedirectGuard())
            guard let http = response as? HTTPURLResponse else {
                throw StreamHTTPError.transport("The host gave no usable answer.")
            }
            return (data, http)
        } catch let error as StreamHTTPError {
            throw error
        } catch {
            throw translate(error)
        }
    }

    private static func check(_ url: URL) throws {
        if case let .blocked(reason) = StreamAddressPolicy.verdict(for: url) {
            throw StreamHTTPError.blockedAddress(reason)
        }
    }

    private static func translate(_ error: Error) -> StreamHTTPError {
        if error is CancellationError { return .transport("The check was cancelled.") }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorAppTransportSecurityRequiresSecureConnection:
                return .insecure
            case NSURLErrorCancelled:
                // The guard cancels a task that redirects somewhere it should not.
                return .blockedAddress("it redirects to an address on this machine or your local network")
            case NSURLErrorHTTPTooManyRedirects:
                return .tooManyRedirects
            default:
                break
            }
        }
        return .transport(error.localizedDescription)
    }
}

/// Re-applies the address policy to every hop, and stops a chain that will not
/// settle. A public link is allowed to end at a private address otherwise.
private final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var followed = 0

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        lock.lock()
        followed += 1
        let count = followed
        lock.unlock()

        guard count <= StreamHTTP.maximumRedirects else {
            completionHandler(nil)
            return
        }
        guard let url = request.url, StreamAddressPolicy.isPublic(url) else {
            task.cancel()
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
