import XCTest
@testable import CinemaPlayer

final class PageVideoResolverTests: XCTestCase {
    private let pageURL = URL(string: "https://example.com/films/watch")!

    private func firstVideo(_ html: String, page: URL? = nil) -> String? {
        PageVideoResolver.videoURLs(inHTML: html, relativeTo: page ?? pageURL).first?.absoluteString
    }

    func testPrefersJSONLDThenOpenGraphThenMarkup() {
        let html = """
        <html><head>
        <script type="application/ld+json">{"@type":"VideoObject","contentUrl":"https://cdn.example.com/canonical.mp4"}</script>
        <meta property="og:video:secure_url" content="https://cdn.example.com/social.mp4">
        </head><body><video src="https://cdn.example.com/inline.mp4"></video></body></html>
        """
        XCTAssertEqual(
            PageVideoResolver.videoURLs(inHTML: html, relativeTo: pageURL).map(\.absoluteString),
            [
                "https://cdn.example.com/canonical.mp4",
                "https://cdn.example.com/social.mp4",
                "https://cdn.example.com/inline.mp4",
            ]
        )
    }

    func testOpenGraphVariantsAreRankedAmongThemselves() {
        let html = """
        <meta property="og:video" content="https://cdn.example.com/plain.mp4">
        <meta property="og:video:url" content="https://cdn.example.com/url.mp4">
        <meta property="og:video:secure_url" content="https://cdn.example.com/secure.mp4">
        """
        XCTAssertEqual(firstVideo(html), "https://cdn.example.com/secure.mp4")
    }

    func testReadsVideoAndSourceTagsWhenThereIsNoMetadata() {
        XCTAssertEqual(
            firstVideo("<body><video controls src=\"/media/movie.mp4\"></video></body>"),
            "https://example.com/media/movie.mp4"
        )
        XCTAssertEqual(
            firstVideo("<body><video><source src=\"stream.m3u8\" type=\"application/x-mpegURL\"></video></body>"),
            "https://example.com/films/stream.m3u8"
        )
    }

    func testPrefersAFormatAVFoundationCanDecode() {
        let html = """
        <video>
          <source src="/movie.webm" type="video/webm">
          <source src="/movie.ogv" type="video/ogg">
          <source src="/movie.mp4" type="video/mp4">
        </video>
        """
        let found = PageVideoResolver.videoURLs(inHTML: html, relativeTo: pageURL).map(\.lastPathComponent)
        XCTAssertEqual(found.first, "movie.mp4")
        XCTAssertEqual(found.count, 3, "the others stay as fallbacks")
    }

    func testHonoursBaseHref() {
        let html = """
        <head><base href="https://cdn.example.com/assets/"></head>
        <body><video src="movie.mp4"></video></body>
        """
        XCTAssertEqual(firstVideo(html), "https://cdn.example.com/assets/movie.mp4")
    }

    func testResolvesProtocolRelativeAddressesAndDecodesEntities() {
        let html = #"<meta property="og:video" content="//cdn.example.com/movie.mp4?a=1&amp;b=2">"#
        XCTAssertEqual(firstVideo(html), "https://cdn.example.com/movie.mp4?a=1&b=2")
    }

    func testRemovesDuplicateCandidates() {
        let html = """
        <meta property="og:video:secure_url" content="https://cdn.example.com/movie.mp4">
        <meta property="og:video" content="https://cdn.example.com/movie.mp4">
        <video src="https://cdn.example.com/movie.mp4"></video>
        """
        XCTAssertEqual(PageVideoResolver.videoURLs(inHTML: html, relativeTo: pageURL).count, 1)
    }

    func testSkipsCandidatesThatAreNotFetchable() {
        let html = """
        <meta property="og:video" content="rtmp://example.com/live">
        <video src="blob:https://example.com/9f8a"></video>
        <source src="data:video/mp4;base64,AAAA">
        <source src="http://127.0.0.1:8080/private.mp4">
        <source src="http://192.168.1.10/nas.mp4">
        """
        XCTAssertTrue(PageVideoResolver.videoURLs(inHTML: html, relativeTo: pageURL).isEmpty)
    }

    func testSurvivesMalformedMarkupAndJSON() {
        let html = """
        <html><head><meta property="og:video" content=
        <script type="application/ld+json">{"contentUrl": not json</script>
        <video src=></video><source src="">
        """
        XCTAssertTrue(PageVideoResolver.videoURLs(inHTML: html, relativeTo: pageURL).isEmpty)
    }

    func testFindsNothingOnAPageWithoutAVideo() {
        XCTAssertTrue(PageVideoResolver.videoURLs(inHTML: "<html><body><p>No video</p></body></html>", relativeTo: pageURL).isEmpty)
    }

    func testTitlePrefersOpenGraphAndFallsBackToTheTitleTag() {
        XCTAssertEqual(
            PageVideoResolver.pageTitle(inHTML: "<head><meta property=\"og:title\" content=\"Big Buck Bunny\"><title>ignored</title></head>"),
            "Big Buck Bunny"
        )
        XCTAssertEqual(
            PageVideoResolver.pageTitle(inHTML: "<head><title>  Sintel &amp; Friends  </title></head>"),
            "Sintel & Friends"
        )
        XCTAssertNil(PageVideoResolver.pageTitle(inHTML: "<head></head>"))
    }

    func testNamesProvidersItCannotSupport() {
        XCTAssertEqual(PageVideoResolver.unsupportedProvider(for: URL(string: "https://www.youtube.com/watch?v=abc")!), "YouTube")
        XCTAssertEqual(PageVideoResolver.unsupportedProvider(for: URL(string: "https://youtu.be/abc")!), "YouTube")
        XCTAssertNil(PageVideoResolver.unsupportedProvider(for: URL(string: "https://notyoutube.com/watch")!))
        XCTAssertNil(PageVideoResolver.unsupportedProvider(for: URL(string: "https://cdn.example.com/movie.mp4")!))
    }

    func testVimeoIsTriedRatherThanRefusedOutright() {
        // Some Vimeo pages do expose a progressive or HLS address, so the page
        // is read instead of being rejected on the host name alone.
        XCTAssertNil(PageVideoResolver.unsupportedProvider(for: URL(string: "https://vimeo.com/123456")!))
    }
}
