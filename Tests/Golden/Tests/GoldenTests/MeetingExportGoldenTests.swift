import Foundation
import SuperflowKernel
import SuperflowMeetingEngine
import XCTest

final class MeetingExportGoldenTests: XCTestCase {
    private func fixture() throws -> MeetingExportFixture {
        try Golden.load("meeting-export/cases.json")
    }

    func testMarkdownExport() throws {
        let fixture = try fixture()
        let doc = try fixture.document.document()
        let markdown = MeetingExport.markdown(doc)
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        XCTAssertEqual(lines.count, fixture.expectedMarkdownLines.count,
                       "markdown line count differs:\n\(markdown)")
        for (index, expected) in fixture.expectedMarkdownLines.enumerated() where index < lines.count {
            if expected.contains("{{date}}") {
                XCTAssertTrue(lines[index].hasPrefix("**Date:** "), "date line missing: \(lines[index])")
                let value = lines[index].dropFirst("**Date:** ".count)
                XCTAssertFalse(value.isEmpty, "date line is empty")
            } else {
                XCTAssertEqual(lines[index], expected, "markdown line \(index) differs")
            }
        }
        XCTAssertTrue(markdown.hasSuffix("\n"))
    }

    func testJSONExportIsStableAndSorted() throws {
        let fixture = try fixture()
        let doc = try fixture.document.document()
        let data = try MeetingExport.jsonData(doc, options: .deterministic)
        let actual = String(decoding: data, as: UTF8.self)
        XCTAssertEqual(actual, fixture.expectedJSON)
        XCTAssertEqual(try MeetingExport.jsonData(doc, options: .deterministic), data,
                       "JSON export is not deterministic")
    }

    func testTurnsAreSortedByStartTimeThenIndex() throws {
        let fixture = try fixture()
        let doc = try fixture.document.document()
        let markdown = MeetingExport.markdown(doc)
        let you = try XCTUnwrap(markdown.range(of: "**You** · 0:00"))
        let priya = try XCTUnwrap(markdown.range(of: "**Priya** · 1:05"))
        XCTAssertLessThan(you.lowerBound, priya.lowerBound)
    }

    func testDurationLabels() {
        func label(_ ms: Int) -> String {
            MeetingDocument(sessionID: SessionID("x"), title: "t", startedAt: Date(timeIntervalSince1970: 0),
                            endedAt: nil, durationMs: ms, speakers: [], turns: []).durationLabel
        }
        XCTAssertEqual(label(9_000), "9s")
        XCTAssertEqual(label(60_000), "1m 00s")
        XCTAssertEqual(label(2_700_000), "45m 00s")
        XCTAssertEqual(label(3_661_000), "1h 01m")
    }

    func testGapTurnsUseItalicMarker() throws {
        let fixture = try fixture()
        let doc = try fixture.document.document()
        XCTAssertTrue(MeetingExport.markdown(doc).contains("_[System audio was lost for 5 s.]_"))
    }
}
