import XCTest
@testable import CinemaPlayer

final class SubtitleFileSupportTests: XCTestCase {
    private func write(_ data: Data, extension ext: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testAcceptsBothSubtitleFormats() {
        XCTAssertTrue(SubtitleFileSupport.isSupported(URL(fileURLWithPath: "/s/movie.srt")))
        XCTAssertTrue(SubtitleFileSupport.isSupported(URL(fileURLWithPath: "/s/movie.vtt")))
        XCTAssertTrue(SubtitleFileSupport.isSupported(URL(fileURLWithPath: "/s/movie.VTT")))
        XCTAssertFalse(SubtitleFileSupport.isSupported(URL(fileURLWithPath: "/s/movie.ass")))
        XCTAssertFalse(SubtitleFileSupport.isSupported(URL(fileURLWithPath: "/s/movie.mp4")))
    }

    func testOpenPanelAlwaysOffersSomethingSelectable() {
        // The panel must never end up empty, or no file can be chosen at all —
        // which is exactly how .vtt files became unopenable.
        XCTAssertFalse(SubtitleFileSupport.openPanelTypes.isEmpty)
        XCTAssertTrue(SubtitleFileSupport.openPanelTypes.contains(.plainText))
    }

    func testReadsUTF8IncludingNonLatinText() throws {
        let url = try write(Data("WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nمرحبا".utf8), extension: "vtt")
        XCTAssertTrue(try SubtitleFileSupport.readText(at: url).contains("مرحبا"))
    }

    func testReadsAFileThatIsNotUTF8AtAll() throws {
        // Bytes that cannot be UTF-8; the reader must still return something
        // rather than refusing the file.
        let data = Data([0xC7, 0xE1, 0xD3, 0xE1, 0xC7, 0xE3, 0x0A])
        let url = try write(data, extension: "srt")

        let text = try SubtitleFileSupport.readText(at: url)
        XCTAssertFalse(text.isEmpty)
    }

    func testRoundTripsAWebVTTFileFromDiskIntoCues() throws {
        let source = """
        WEBVTT

        00:00:12.000 --> 00:00:14.500
        Read from a file
        """
        let url = try write(Data(source.utf8), extension: "vtt")

        let cues = try SubtitleParser.parse(SubtitleFileSupport.readText(at: url))
        let cue = try XCTUnwrap(cues.first)
        XCTAssertEqual(cue.text, "Read from a file")
        XCTAssertEqual(cue.startTime, 12, accuracy: 0.001)
    }
}
