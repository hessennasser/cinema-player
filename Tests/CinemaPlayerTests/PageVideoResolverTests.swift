import XCTest
@testable import CinemaPlayer

final class PageVideoResolverTests: XCTestCase {
    private let pageURL = URL(string: "https://example.com/films/watch")!

    func testPrefersOpenGraphVideoOverAnEmbeddedTag() {
        let html = """
        <html><head>
        <meta property="og:video:secure_url" content="https://cdn.example.com/movie.mp4">
        <meta property="og:video" content="https://cdn.example.com/fallback.mp4">
        </head><body><video src="https://cdn.example.com/inline.mp4"></video></body></html>
        """
        XCTAssertEqual(
            PageVideoResolver.videoURL(inHTML: html, relativeTo: pageURL)?.absoluteString,
            "https://cdn.example.com/movie.mp4"
        )
    }

    func testReadsVideoAndSourceTagsWhenThereIsNoMetadata() {
        let videoTag = "<body><video controls src=\"/media/movie.mp4\"></video></body>"
        XCTAssertEqual(
            PageVideoResolver.videoURL(inHTML: videoTag, relativeTo: pageURL)?.absoluteString,
            "https://example.com/media/movie.mp4"
        )

        let sourceTag = "<body><video><source src=\"stream.m3u8\" type=\"application/x-mpegURL\"></video></body>"
        XCTAssertEqual(
            PageVideoResolver.videoURL(inHTML: sourceTag, relativeTo: pageURL)?.absoluteString,
            "https://example.com/films/stream.m3u8"
        )
    }

    func testResolvesProtocolRelativeAddressesAndDecodesEntities() {
        let html = #"<meta property="og:video" content="//cdn.example.com/movie.mp4?a=1&amp;b=2">"#
        XCTAssertEqual(
            PageVideoResolver.videoURL(inHTML: html, relativeTo: pageURL)?.absoluteString,
            "https://cdn.example.com/movie.mp4?a=1&b=2"
        )
    }

    func testIgnoresCandidatesThatAreNotStreamable() {
        let html = """
        <meta property="og:video" content="rtmp://example.com/live">
        <video src="blob:https://example.com/9f8a"></video>
        """
        XCTAssertNil(PageVideoResolver.videoURL(inHTML: html, relativeTo: pageURL))
    }

    func testFindsNothingOnAPageWithoutAVideo() {
        XCTAssertNil(PageVideoResolver.videoURL(inHTML: "<html><body><p>No video</p></body></html>", relativeTo: pageURL))
    }

    func testTitlePrefersOpenGraphAndFallsBackToTheTitleTag() {
        let withMeta = "<head><meta property=\"og:title\" content=\"Big Buck Bunny\"><title>ignored</title></head>"
        XCTAssertEqual(PageVideoResolver.pageTitle(inHTML: withMeta), "Big Buck Bunny")

        let withTitleOnly = "<head><title>  Sintel &amp; Friends  </title></head>"
        XCTAssertEqual(PageVideoResolver.pageTitle(inHTML: withTitleOnly), "Sintel & Friends")

        XCTAssertNil(PageVideoResolver.pageTitle(inHTML: "<head></head>"))
    }

    func testNamesSitesWhoseVideoStaysInTheirOwnPlayer() {
        XCTAssertEqual(PageVideoResolver.playerOnlyService(for: URL(string: "https://www.youtube.com/watch?v=abc")!), "YouTube")
        XCTAssertEqual(PageVideoResolver.playerOnlyService(for: URL(string: "https://youtu.be/abc")!), "YouTube")
        XCTAssertEqual(PageVideoResolver.playerOnlyService(for: URL(string: "https://vimeo.com/12345")!), "Vimeo")
        XCTAssertNil(PageVideoResolver.playerOnlyService(for: URL(string: "https://notyoutube.com/watch")!))
        XCTAssertNil(PageVideoResolver.playerOnlyService(for: URL(string: "https://cdn.example.com/movie.mp4")!))
    }
}

final class StreamContentTypeTests: XCTestCase {
    private let movieURL = URL(string: "https://example.com/movie.mp4")!
    private let opaqueURL = URL(string: "https://example.com/watch")!

    func testRecognisesMediaContentTypes() {
        XCTAssertTrue(StreamSupport.isMediaContentType("video/mp4", at: movieURL))
        XCTAssertTrue(StreamSupport.isMediaContentType("application/x-mpegURL", at: opaqueURL))
        XCTAssertTrue(StreamSupport.isMediaContentType("application/vnd.apple.mpegurl; charset=utf-8", at: opaqueURL))
        XCTAssertFalse(StreamSupport.isMediaContentType("text/html; charset=UTF-8", at: movieURL))
    }

    func testTrustsTheExtensionOnlyWhenTheTypeSaysNothing() {
        XCTAssertTrue(StreamSupport.isMediaContentType("application/octet-stream", at: movieURL))
        XCTAssertFalse(StreamSupport.isMediaContentType("application/octet-stream", at: opaqueURL))
    }

    func testRecognisesPages() {
        XCTAssertTrue(StreamSupport.isPageContentType("text/html; charset=UTF-8"))
        XCTAssertFalse(StreamSupport.isPageContentType("video/mp4"))
    }

    func testReadsTheBestResolutionFromAnHLSManifest() {
        let manifest = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=2227464,CODECS="avc1.640020",RESOLUTION=960x540,FRAME-RATE=60.000
        low.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=8178040,CODECS="avc1.64002a",RESOLUTION=1920x1080,FRAME-RATE=60.000
        high.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=900000,CODECS="mp4a.40.2"
        audio.m3u8
        """
        let size = StreamSupport.highestManifestResolution(in: manifest)
        XCTAssertEqual(size.map(StreamSupport.resolutionLabel), "1920 × 1080")
    }

    func testReturnsNoResolutionWhenTheManifestAdvertisesNone() {
        let manifest = """
        #EXTM3U
        #EXT-X-TARGETDURATION:6
        #EXTINF:6.0,
        segment0.ts
        """
        XCTAssertNil(StreamSupport.highestManifestResolution(in: manifest))
    }
}
