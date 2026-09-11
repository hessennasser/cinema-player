import XCTest
@testable import CinemaPlayer

final class StreamSupportTests: XCTestCase {
    func testAcceptsHTTPAndHTTPSLinks() {
        XCTAssertEqual(
            StreamSupport.streamURL(from: "https://example.com/movie.mp4")?.absoluteString,
            "https://example.com/movie.mp4"
        )
        XCTAssertEqual(
            StreamSupport.streamURL(from: "http://example.com/live/index.m3u8")?.absoluteString,
            "http://example.com/live/index.m3u8"
        )
    }

    func testFillsInHTTPSWhenTheSchemeIsMissing() {
        XCTAssertEqual(
            StreamSupport.streamURL(from: "example.com/movie.mp4")?.absoluteString,
            "https://example.com/movie.mp4"
        )
    }

    func testTrimsSurroundingWhitespaceAndEscapesSpaces() {
        XCTAssertEqual(
            StreamSupport.streamURL(from: "  https://example.com/my movie.mp4\n")?.absoluteString,
            "https://example.com/my%20movie.mp4"
        )
    }

    func testRejectsAddressesAVPlayerCannotStream() {
        XCTAssertNil(StreamSupport.streamURL(from: ""))
        XCTAssertNil(StreamSupport.streamURL(from: "   "))
        XCTAssertNil(StreamSupport.streamURL(from: "ftp://example.com/movie.mp4"))
        XCTAssertNil(StreamSupport.streamURL(from: "file:///Movies/film.mp4"))
    }

    func testIsStreamableRejectsLocalFiles() {
        XCTAssertFalse(StreamSupport.isStreamable(URL(fileURLWithPath: "/Movies/film.mp4")))
        XCTAssertTrue(StreamSupport.isStreamable(URL(string: "https://example.com/film.mp4")!))
    }

    func testTitleReadsTheFileNameFromTheLink() {
        let url = URL(string: "https://cdn.example.com/films/big_buck_bunny.mp4")!
        XCTAssertEqual(StreamSupport.title(for: url), "big buck bunny")
    }

    func testTitleFallsBackToTheHostWhenTheNameSaysNothing() {
        XCTAssertEqual(
            StreamSupport.title(for: URL(string: "https://stream.example.com/live/index.m3u8")!),
            "stream.example.com"
        )
        XCTAssertEqual(
            StreamSupport.title(for: URL(string: "https://stream.example.com")!),
            "stream.example.com"
        )
    }

    func testFormatLabelDescribesTheStream() {
        XCTAssertEqual(StreamSupport.formatLabel(for: URL(string: "https://example.com/a.m3u8")!), "HLS")
        XCTAssertEqual(StreamSupport.formatLabel(for: URL(string: "https://example.com/a.mp4")!), "MP4")
        XCTAssertEqual(StreamSupport.formatLabel(for: URL(string: "https://example.com/watch?id=7")!), "LINK")
    }

    func testRemoteItemsAreMarkedAndSurviveBeingSaved() throws {
        let url = URL(string: "https://example.com/movie.mp4")!
        let item = MediaItem(title: "movie", url: url, bookmarkData: nil)
        XCTAssertTrue(item.isRemote)

        let data = try JSONEncoder().encode(PersistedMediaItem(item: item))
        let restored = try JSONDecoder().decode(PersistedMediaItem.self, from: data).makeMediaItem()

        XCTAssertEqual(restored?.url, url)
        XCTAssertEqual(restored?.id, item.id)
    }

    func testStreamPresentationsAreLabelledInTheLibrary() {
        let presentation = VideoPresentation(
            thumbnail: nil,
            duration: 65,
            resolution: "1920 × 1080",
            fileSize: nil,
            format: "HLS",
            isStream: true
        )
        XCTAssertEqual(presentation.detailLine, "1:05 · 1920 × 1080 · HLS · Stream")
    }
}
