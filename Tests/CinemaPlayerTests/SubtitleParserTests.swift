import XCTest
@testable import CinemaPlayer

final class SubtitleParserTests: XCTestCase {
    func testParsesBOMCommaMillisecondsAndMultilineCues() throws {
        let source = """
        \u{FEFF}1
        00:00:01,250 --> 00:00:03,500
        Welcome to Cinema
        Player

        2
        01:02:03.004 --> 01:02:05.250
        Second cue
        """

        let cues = try SubtitleParser.parse(source)

        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].startTime, 1.25, accuracy: 0.0001)
        XCTAssertEqual(cues[0].endTime, 3.5, accuracy: 0.0001)
        XCTAssertEqual(cues[0].text, "Welcome to Cinema\nPlayer")
        XCTAssertEqual(cues[1].startTime, 3_723.004, accuracy: 0.0001)
    }

    func testSortsValidCuesAndSkipsMalformedBlocks() throws {
        let source = """
        3
        00:00:09,000 --> 00:00:11,000
        Later

        2
        This is not a time range
        Broken

        1
        00:00:02,000 --> 00:00:04,000
        First
        """

        let cues = try SubtitleParser.parse(source)

        XCTAssertEqual(cues.map(\.text), ["First", "Later"])
        XCTAssertTrue(cues[0].contains(2.5))
        XCTAssertFalse(cues[0].contains(4))
    }

    func testRejectsSubtitleSourceWithoutValidCues() {
        XCTAssertThrowsError(try SubtitleParser.parse("00:00:01,000 --> 00:00:00,500\nBackwards")) { error in
            XCTAssertEqual(error as? SubtitleParserError, .noCues)
        }
    }
}
