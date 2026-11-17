import XCTest
import SuperflowKernel
import SuperflowMeetingIntelligence
@testable import SuperflowFeatureIntelligence

final class IntelligenceCoreTests: XCTestCase {
    // MARK: prompt enumeration parity with source

    func testThemeEnumerationParityWithMeetingModeSource() throws {
        let themes = IntelligenceTheme.allFromSource()
        XCTAssertEqual(themes.count, MeetingMode.allCases.count)
        XCTAssertEqual(Set(themes.map(\.id)), Set(MeetingMode.allCases.map(\.rawValue)))
        XCTAssertEqual(Set(themes.map(\.id)).count, themes.count, "No duplicate theme ids")
        for mode in MeetingMode.allCases {
            let theme = try XCTUnwrap(themes.first { $0.id == mode.rawValue })
            XCTAssertFalse(theme.label.isEmpty)
            XCTAssertEqual(theme.label, IntelligenceTheme.label(for: mode))
        }
    }

    func testEveryKnownThemeHasANonGenericLabel() throws {
        let labels = Dictionary(uniqueKeysWithValues:
            IntelligenceTheme.allFromSource().map { ($0.id, $0.label) })
        XCTAssertEqual(labels["normal"], "General Meeting")
        XCTAssertEqual(labels["codingInterview"], "Coding Interview")
        XCTAssertEqual(labels["sales"], "Sales Call")
        XCTAssertEqual(labels["custom"], "Personal / Custom")
    }

    // MARK: one shared messy-transcript block

    func testMessyBlockIsSharedByAskDetectionAndSuggestions() throws {
        let block = IntelligencePrompts.messyTranscriptBlock
        XCTAssertFalse(block.isEmpty)
        for task in [IntelligencePrompts.askTask("is this React or Vue"),
                     IntelligencePrompts.meetingDetectionTask(),
                     IntelligencePrompts.suggestionsTask()] {
            XCTAssertEqual(task.components(separatedBy: block).count - 1, 1,
                           "Each task embeds the shared block exactly once")
        }
        XCTAssertTrue(IntelligencePrompts.askTask("cooper netties").contains("cooper netties"))
    }

    // MARK: question detection with an exposed sensitivity constant

    func testQuestionDetectorIgnoresSilenceAndFillers() throws {
        for text in ["", "   \n ", "uh", "um, you know", "..."] {
            XCTAssertFalse(IntelligenceQuestionDetector.looksLikeQuestion(text), "\(text)")
        }
    }

    func testQuestionDetectorCatchesCleanAndMessyQuestions() throws {
        XCTAssertTrue(IntelligenceQuestionDetector.looksLikeQuestion("What is the deadline?"))
        XCTAssertTrue(IntelligenceQuestionDetector.looksLikeQuestion("um so how would we even deploy this thing"))
        XCTAssertTrue(IntelligenceQuestionDetector.looksLikeQuestion("can you explain that again"))
        XCTAssertTrue(IntelligenceQuestionDetector.looksLikeQuestion("why does cooper netties break"))
    }

    func testQuestionDetectorSensitivityIsExposedAndBounded() throws {
        let value = IntelligenceQuestionDetector.sensitivity
        XCTAssertTrue(value > 0 && value <= 1)
        XCTAssertEqual(value, IntelligenceQuestionDetector.sensitivity)
    }
}
