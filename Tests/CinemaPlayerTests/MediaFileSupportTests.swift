import XCTest
@testable import CinemaPlayer

final class MediaFileSupportTests: XCTestCase {
    func testRecognizesCommonMovieFormats() {
        XCTAssertTrue(MediaFileSupport.isSupported(URL(fileURLWithPath: "/Movies/film.mkv")))
        XCTAssertTrue(MediaFileSupport.isSupported(URL(fileURLWithPath: "/Movies/film.mp4")))
        XCTAssertTrue(MediaFileSupport.isSupported(URL(fileURLWithPath: "/Movies/film.MOV")))
    }

    func testRejectsNonVideoFiles() {
        XCTAssertFalse(MediaFileSupport.isSupported(URL(fileURLWithPath: "/Documents/notes.pdf")))
    }

    func testFormatsVideoDurationsForTheLibrary() {
        XCTAssertEqual(TimeFormatter.string(for: 65), "1:05")
        XCTAssertEqual(TimeFormatter.string(for: 3_665), "1:01:05")
    }

    func testVideoFilesInDirectoryCollectsSupportedVideosRecursively() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let nested = root.appendingPathComponent("season-1")
        try fileManager.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        try Data().write(to: root.appendingPathComponent("movie.mp4"))
        try Data().write(to: root.appendingPathComponent("notes.pdf"))
        try Data().write(to: nested.appendingPathComponent("episode.mkv"))

        let found = MediaFileSupport.videoFiles(in: root)
            .map(\.lastPathComponent)
            .sorted()

        XCTAssertEqual(found, ["episode.mkv", "movie.mp4"])
    }
}
