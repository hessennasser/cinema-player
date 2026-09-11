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

    func testIgnoresTrickPlayTracksWhenReadingAManifest() {
        // An I-frame playlist carries a RESOLUTION but is never a rendition
        // anyone watches, so it must not raise the advertised ceiling.
        let manifest = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=2227464,CODECS="avc1.640020",RESOLUTION=960x540
        low.m3u8
        #EXT-X-I-FRAME-STREAM-INF:BANDWIDTH=200000,CODECS="avc1.640020",RESOLUTION=3840x2160,URI="iframe.m3u8"
        """
        XCTAssertEqual(
            StreamSupport.highestManifestResolution(in: manifest).map(StreamSupport.resolutionLabel),
            "960 × 540"
        )
    }

    func testIgnoresAudioOnlyVariants() {
        let manifest = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=128000,CODECS="mp4a.40.2",RESOLUTION=1920x1080
        audio.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=2227464,CODECS="avc1.640020,mp4a.40.2",RESOLUTION=1280x720
        video.m3u8
        """
        XCTAssertEqual(
            StreamSupport.highestManifestResolution(in: manifest).map(StreamSupport.resolutionLabel),
            "1280 × 720"
        )
    }

    func testAdvertisedResolutionIsLabelledAsACeiling() {
        let size = CGSize(width: 1_920, height: 1_080)
        XCTAssertEqual(StreamSupport.resolutionLabel(for: size), "1920 × 1080")
        XCTAssertEqual(StreamSupport.advertisedResolutionLabel(for: size), "Up to 1920 × 1080")
    }

    func testStreamPresentationsAreLabelledInTheLibrary() {
        let presentation = VideoPresentation(
            thumbnail: nil,
            duration: 65,
            resolution: "Up to 1920 × 1080",
            fileSize: nil,
            format: "HLS",
            isStream: true
        )
        XCTAssertEqual(presentation.detailLine, "1:05 · Up to 1920 × 1080 · HLS · Stream")
    }
}
