import Foundation
import SuperflowPorts
import XCTest
@testable import SuperflowGrammarHarper

private actor RecordingLinter: HarperLinting {
    var lints: [HarperLint]
    private(set) var words: [String] = []

    init(lints: [HarperLint]) { self.lints = lints }

    func lint(_ text: String, customWords: [String]) async -> [HarperLint] {
        words = customWords
        return lints
    }
}

final class HarperCheckerTests: XCTestCase {
    func testDisabledCheckerNeverLints() async {
        let linter = RecordingLinter(lints: [HarperLint(utf16Start: 0, utf16Length: 2,
                                                        kind: "Spelling", suggestion: "Hi")])
        let checker = HarperChecker(linter: linter, config: HarperConfig(enabled: false))
        let lints = await checker.lint("helo", customWords: [])
        XCTAssertTrue(lints.isEmpty)
        let words = await linter.words
        XCTAssertTrue(words.isEmpty)
    }

    func testGateAllowlistMatchesPlan() async {
        let raw = [
            HarperLint(utf16Start: 0, utf16Length: 4, kind: "Spelling", suggestion: "hello"),
            HarperLint(utf16Start: 5, utf16Length: 3, kind: "Style", suggestion: "utilize"),
            HarperLint(utf16Start: 9, utf16Length: 1, kind: "Punctuation", suggestion: "."),
            HarperLint(utf16Start: 11, utf16Length: 2, kind: "Repetition", suggestion: "the"),
            HarperLint(utf16Start: 14, utf16Length: 1, kind: "aOrAn", suggestion: "an"),
        ]
        let checker = HarperChecker(linter: RecordingLinter(lints: raw),
                                    config: HarperConfig(enabled: true))
        let lints = await checker.lint("helo use x the the a", customWords: [])
        XCTAssertEqual(lints.map(\.kind), ["Spelling", "Repetition", "aOrAn"])
    }

    func testArticleRuleIsReclassifiedFromMiscellaneous() async {
        let raw = [
            HarperLint(utf16Start: 0, utf16Length: 1, kind: "Miscellaneous", suggestion: "an",
                       message: "A rule that looks for incorrect indefinite articles."),
            HarperLint(utf16Start: 2, utf16Length: 1, kind: "Miscellaneous", suggestion: "x",
                       message: "Some other miscellaneous rule."),
        ]
        let checker = HarperChecker(linter: RecordingLinter(lints: raw),
                                    config: HarperConfig(enabled: true))
        let lints = await checker.lint("a apple x", customWords: [])
        XCTAssertEqual(lints.map(\.kind), ["aOrAn"])
    }

    func testCustomWordsAreMergedAndDeduplicated() async {
        let linter = RecordingLinter(lints: [])
        let checker = HarperChecker(linter: linter,
                                    config: HarperConfig(enabled: true, customWords: ["Superflow", "Harper"]))
        _ = await checker.lint("text", customWords: ["Superflow", "Parakeet"])
        let words = await linter.words
        XCTAssertEqual(Set(words), Set(["Superflow", "Harper", "Parakeet"]))
        XCTAssertEqual(words.count, 3)
    }

    func testOutOfBoundsLintsAreDropped() {
        let config = HarperConfig(enabled: true)
        let raw = [
            HarperLint(utf16Start: 0, utf16Length: 5, kind: "Spelling", suggestion: nil),
            HarperLint(utf16Start: 10, utf16Length: 5, kind: "Spelling", suggestion: nil),
            HarperLint(utf16Start: -1, utf16Length: 2, kind: "Spelling", suggestion: nil),
        ]
        let mapped = HarperMapper.map(raw, config: config, utf16Length: 8)
        XCTAssertEqual(mapped.count, 1)
        XCTAssertEqual(mapped[0].utf16Start, 0)
    }

    func testMaxLintsCapsOutput() {
        let raw = (0..<10).map { HarperLint(utf16Start: $0, utf16Length: 1, kind: "Spelling",
                                             suggestion: nil) }
        let mapped = HarperMapper.map(raw, config: HarperConfig(enabled: true, maxLints: 3),
                                      utf16Length: 20)
        XCTAssertEqual(mapped.count, 3)
    }

    func testUTF16OffsetsSurviveEmoji() async {
        let text = "😀 helo"
        let start = (text as NSString).range(of: "helo").location
        let checker = HarperChecker(linter: RecordingLinter(lints: [
            HarperLint(utf16Start: start, utf16Length: 4, kind: "Spelling", suggestion: "hello"),
        ]), config: HarperConfig(enabled: true))
        let lints = await checker.lint(text, customWords: [])
        XCTAssertEqual(lints.first?.utf16Start, start)
        XCTAssertEqual(lints.first?.suggestion, "hello")
    }

    func testAvailabilityExplainsMissingBuild() {
        XCTAssertFalse(HarperAvailability.explanation.isEmpty)
        if !HarperAvailability.isCompiledIn {
            XCTAssertTrue(HarperAvailability.explanation.contains("not compiled in"))
        }
    }

    // MARK: - Real backend tests (skip when only the stub is linked)

    func testStubBackendIsReported() async throws {
        let linter = HarperFFILinter()
        let lints = await linter.lint("teh cat", customWords: [])
        if !HarperAvailability.isCompiledIn {
            XCTAssertTrue(lints.isEmpty)
        }
    }

    func testRealBackendFindsSpellingAfterEmoji() async throws {
        try XCTSkipUnless(HarperAvailability.isCompiledIn, "real Harper XCFramework not built")
        let linter = HarperFFILinter()
        let text = "😀 teh cat"
        let lints = await linter.lint(text, customWords: [])
        let spelling = try XCTUnwrap(lints.first { $0.kind == "Spelling" })
        XCTAssertEqual(spelling.utf16Start, 3)
        XCTAssertEqual(spelling.utf16Length, 3)
        XCTAssertEqual(spelling.suggestion, "the")
        let range = NSRange(location: spelling.utf16Start, length: spelling.utf16Length)
        XCTAssertEqual((text as NSString).substring(with: range), "teh")
    }

    func testRealBackendFindsSpellingAfterCJK() async throws {
        try XCTSkipUnless(HarperAvailability.isCompiledIn, "real Harper XCFramework not built")
        let linter = HarperFFILinter()
        let text = "你好 teh cat"
        let lints = await linter.lint(text, customWords: [])
        let spelling = try XCTUnwrap(lints.first { $0.kind == "Spelling" })
        XCTAssertEqual(spelling.utf16Start, 3)
        XCTAssertEqual(spelling.utf16Length, 3)
    }

    func testRealBackendRespectsCustomDictionary() async throws {
        try XCTSkipUnless(HarperAvailability.isCompiledIn, "real Harper XCFramework not built")
        let linter = HarperFFILinter()
        let lints = await linter.lint("superflow ships", customWords: ["superflow"])
        XCTAssertFalse(lints.contains { $0.kind == "Spelling" })
    }

    func testRealBackendReportsRepetition() async throws {
        try XCTSkipUnless(HarperAvailability.isCompiledIn, "real Harper XCFramework not built")
        let linter = HarperFFILinter()
        let lints = await linter.lint("the the cat", customWords: [])
        XCTAssertTrue(lints.contains { $0.kind == "Repetition" })
    }
}
