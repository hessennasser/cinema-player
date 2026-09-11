import XCTest
@testable import CinemaPlayer

/// Answers requests in-process so the HTTP behaviour can be exercised without a
/// network. The host is a public literal address, which the address policy
/// clears without a DNS lookup.
final class StubProtocol: URLProtocol {
    struct Reply {
        var status = 200
        var headers: [String: String] = [:]
        var body = Data()
    }

    nonisolated(unsafe) private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: (@Sendable (URLRequest) -> Reply)?
    nonisolated(unsafe) private static var seenMethods: [String] = []

    static func install(_ handler: @escaping @Sendable (URLRequest) -> Reply) {
        lock.lock()
        self.handler = handler
        seenMethods = []
        lock.unlock()
        URLProtocol.registerClass(StubProtocol.self)
    }

    static func uninstall() {
        URLProtocol.unregisterClass(StubProtocol.self)
        lock.lock()
        handler = nil
        seenMethods = []
        lock.unlock()
    }

    static var methods: [String] {
        lock.lock(); defer { lock.unlock() }
        return seenMethods
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let handler = Self.handler
        Self.seenMethods.append(request.httpMethod ?? "?")
        Self.lock.unlock()

        guard let handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let reply = handler(request)
        let response = HTTPURLResponse(
            url: url,
            statusCode: reply.status,
            httpVersion: "HTTP/1.1",
            headerFields: reply.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !reply.body.isEmpty { client?.urlProtocol(self, didLoad: reply.body) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// A minimal MP4 header: a box length, then "ftyp".
private let mp4Bytes = Data([0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, 0x69, 0x73, 0x6F, 0x6D, 0, 0, 0, 0])

final class StreamHTTPTests: XCTestCase {
    private let movieURL = URL(string: "https://93.184.216.34/movie.mp4")!
    private let opaqueURL = URL(string: "https://93.184.216.34/watch")!

    override func tearDown() {
        StubProtocol.uninstall()
        super.tearDown()
    }

    func testFallsBackToARangedGetWhenHeadIsRefused() async throws {
        StubProtocol.install { request in
            request.httpMethod == "HEAD"
                ? .init(status: 405)
                : .init(status: 206, headers: ["Content-Type": "video/mp4", "Content-Range": "bytes 0-15/2848208"], body: mp4Bytes)
        }

        let probe = try await StreamHTTP.probe(movieURL)
        XCTAssertEqual(StubProtocol.methods, ["HEAD", "GET"])
        XCTAssertEqual(probe.kind, .media)
        XCTAssertTrue(probe.supportsRanges)
        XCTAssertEqual(probe.expectedSize, 2_848_208)
    }

    func testSniffsTheBodyWhenTheContentTypeIsMisleading() async throws {
        StubProtocol.install { request in
            request.httpMethod == "HEAD"
                ? .init(status: 200, headers: ["Content-Type": "text/plain"])
                : .init(status: 206, headers: ["Content-Type": "text/plain"], body: mp4Bytes)
        }

        let probe = try await StreamHTTP.probe(opaqueURL)
        XCTAssertEqual(probe.kind, .media, "the leading bytes settle it, not the label")
    }

    func testSniffsAPageServedAsAnOpaqueBlob() async throws {
        StubProtocol.install { request in
            request.httpMethod == "HEAD"
                ? .init(status: 200, headers: ["Content-Type": "application/octet-stream"])
                : .init(status: 200, headers: ["Content-Type": "application/octet-stream"], body: Data("<!DOCTYPE html><html><body>hi".utf8))
        }

        let probe = try await StreamHTTP.probe(opaqueURL)
        XCTAssertEqual(probe.kind, .page)
    }

    func testNoticesWhenTheHostIgnoresRange() async throws {
        // The failure this was written for: a 200 with the whole file in
        // answer to a range request, which stops AVPlayer from streaming.
        StubProtocol.install { request in
            request.httpMethod == "HEAD"
                ? .init(status: 405)
                : .init(status: 200, headers: ["Content-Type": "video/mp4", "Content-Length": "2848208"], body: mp4Bytes)
        }

        let probe = try await StreamHTTP.probe(movieURL)
        XCTAssertEqual(probe.kind, .media)
        XCTAssertFalse(probe.supportsRanges, "a 200 to a ranged GET means ranges are not honoured")
    }

    func testTrustsAcceptRangesFromHead() async throws {
        StubProtocol.install { _ in
            .init(status: 200, headers: ["Content-Type": "video/mp4", "Accept-Ranges": "bytes"])
        }

        let probe = try await StreamHTTP.probe(movieURL)
        XCTAssertEqual(StubProtocol.methods, ["HEAD"], "a conclusive HEAD needs no second request")
        XCTAssertTrue(probe.supportsRanges)
    }

    func testReportsTheStatusWhenAHostRefuses() async {
        StubProtocol.install { _ in .init(status: 404) }

        do {
            _ = try await StreamHTTP.probe(movieURL)
            XCTFail("a 404 should not resolve")
        } catch let error as StreamHTTPError {
            XCTAssertEqual(error.errorDescription, "The host answered 404.")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testRefusesAPageThatDeclaresItselfTooLarge() async {
        let oversized = String(StreamHTTP.maximumPageBytes + 1)
        StubProtocol.install { _ in
            .init(status: 200, headers: ["Content-Type": "text/html", "Content-Length": oversized], body: Data("<html>".utf8))
        }

        do {
            _ = try await StreamHTTP.page(at: opaqueURL)
            XCTFail("an oversized page should be refused")
        } catch let error as StreamHTTPError {
            XCTAssertEqual(error.errorDescription, "That page is too large for Cinema Player to read.")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testStopsAPageThatRunsPastTheCapWithoutDeclaringALength() async {
        let body = Data(repeating: 0x41, count: StreamHTTP.maximumPageBytes + 1_024)
        StubProtocol.install { _ in .init(status: 200, headers: ["Content-Type": "text/html"], body: body) }

        do {
            _ = try await StreamHTTP.page(at: opaqueURL)
            XCTFail("an overlong page should be cut off")
        } catch let error as StreamHTTPError {
            XCTAssertEqual(error.errorDescription, "That page is too large for Cinema Player to read.")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testRefusesToFetchAPrivateAddressAtAll() async {
        StubProtocol.install { _ in .init(status: 200, headers: ["Content-Type": "video/mp4"]) }

        do {
            _ = try await StreamHTTP.probe(URL(string: "http://127.0.0.1/movie.mp4")!)
            XCTFail("a loopback address should never be fetched")
        } catch let error as StreamHTTPError {
            XCTAssertTrue(error.errorDescription?.contains("local network") == true)
            XCTAssertTrue(StubProtocol.methods.isEmpty, "nothing should have been requested")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testSniffsTheContainersAVFoundationOpens() {
        XCTAssertEqual(StreamHTTP.sniff(mp4Bytes), .media)
        XCTAssertEqual(StreamHTTP.sniff(Data([0x1A, 0x45, 0xDF, 0xA3, 0, 0, 0, 0])), .media)
        XCTAssertEqual(StreamHTTP.sniff(Data("#EXTM3U\n#EXT-X-VERSION:3".utf8)), .media)
        XCTAssertEqual(StreamHTTP.sniff(Data("<!DOCTYPE html><html>".utf8)), .page)
        XCTAssertEqual(StreamHTTP.sniff(Data("<html lang=\"en\">".utf8)), .page)
        XCTAssertNil(StreamHTTP.sniff(Data("plain words".utf8)))
        XCTAssertNil(StreamHTTP.sniff(Data()))
    }
}
