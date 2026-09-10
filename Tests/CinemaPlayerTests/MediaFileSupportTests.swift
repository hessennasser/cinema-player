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
}
