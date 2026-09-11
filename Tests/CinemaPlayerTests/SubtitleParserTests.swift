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

    // MARK: - WebVTT

    func testReadsAWebVTTFileWithItsHeader() throws {
        let source = """
        WEBVTT

        00:00:01.000 --> 00:00:02.500
        First line

        00:00:03.000 --> 00:00:04.000
        Second line
        """
        let cues = try SubtitleParser.parse(source)

        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].text, "First line")
        XCTAssertEqual(cues[0].startTime, 1, accuracy: 0.001)
        XCTAssertEqual(cues[0].endTime, 2.5, accuracy: 0.001)
    }

    func testKeepsCuesThatCarrySettingsAfterTheTimestamp() throws {
        let source = """
        WEBVTT

        00:00:01.000 --> 00:00:02.000 align:start position:10% line:0
        Positioned
        """
        let cues = try SubtitleParser.parse(source)

        XCTAssertEqual(cues.first?.text, "Positioned")
        XCTAssertEqual(try XCTUnwrap(cues.first).endTime, 2, accuracy: 0.001)
    }

    func testAcceptsTimestampsWithoutAnHoursField() throws {
        let source = """
        WEBVTT

        01:30.500 --> 01:32.000
        No hours here
        """
        let cues = try SubtitleParser.parse(source)

        let cue = try XCTUnwrap(cues.first)
        XCTAssertEqual(cue.startTime, 90.5, accuracy: 0.001)
        XCTAssertEqual(cue.endTime, 92, accuracy: 0.001)
    }

    func testKeepsCueIdentifiersOutOfTheText() throws {
        let source = """
        WEBVTT

        intro-line
        00:00:01.000 --> 00:00:02.000
        Spoken words
        """
        XCTAssertEqual(try SubtitleParser.parse(source).first?.text, "Spoken words")
    }

    func testStripsMarkupAndDecodesEntities() throws {
        let source = """
        WEBVTT

        00:00:01.000 --> 00:00:02.000
        <i>Tilted</i> and <b>bold</b> &amp; &quot;quoted&quot;

        00:00:03.000 --> 00:00:04.000
        <v Narrator>Someone speaks

        00:00:05.000 --> 00:00:06.000
        <c.loud>Shouted</c>
        """
        let cues = try SubtitleParser.parse(source)

        XCTAssertEqual(cues[0].text, "Tilted and bold & \"quoted\"")
        XCTAssertEqual(cues[1].text, "Someone speaks")
        XCTAssertEqual(cues[2].text, "Shouted")
    }

    func testSkipsBlocksThatCarryNoCue() throws {
        // A NOTE may hold free text with an arrow in it, which must not be
        // mistaken for a timestamp.
        let source = """
        WEBVTT

        NOTE this range 00:01 --> 00:02 is only a comment

        STYLE
        ::cue { color: yellow }

        REGION
        id:speaker width:40%

        00:00:01.000 --> 00:00:02.000
        The only cue
        """
        let cues = try SubtitleParser.parse(source)

        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues.first?.text, "The only cue")
    }

    func testStillReadsSubRipAfterWebVTTSupport() throws {
        let source = """
        1
        00:00:01,000 --> 00:00:02,000
        Comma milliseconds

        2
        00:00:03,000 --> 00:00:04,000
        Second cue
        """
        let cues = try SubtitleParser.parse(source)

        XCTAssertEqual(cues.map(\.text), ["Comma milliseconds", "Second cue"])
    }

    func testRejectsAWebVTTFileWithNothingPlayable() {
        let source = """
        WEBVTT

        NOTE nothing but comments here
        """
        XCTAssertThrowsError(try SubtitleParser.parse(source)) { error in
            XCTAssertEqual(error as? SubtitleParserError, .noCues)
        }
    }
}
