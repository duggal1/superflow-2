import Foundation
import SuperflowKernel
import SuperflowPorts
import SuperflowTextCodeAware
import XCTest

final class CodeAwareGoldenTests: XCTestCase {
    private struct Fixture: Decodable {
        var paths: [String]
        var cases: [Case]
    }

    private struct Case: Decodable {
        var name: String
        var input: String
        var expected: String
        var coding: Bool?
    }

    private func project(paths: [String], coding: Bool = true) -> ProjectContext {
        ProjectContext(root: FileManager.default.temporaryDirectory
            .appendingPathComponent("codeaware-golden", isDirectory: true),
            paths: paths, isCoding: coding, approvedByUser: true)
    }

    func testRealStyleCodingDictationCorpus() async throws {
        let fixture: Fixture = try Golden.load("codeaware/cases.json")
        for c in fixture.cases {
            let context = project(paths: fixture.paths, coding: c.coding ?? true)
            let stage = CodeAwareStage(project: context)
            let settings = Golden.stageSettings(nil)
            let result = await stage.apply(
                TranscriptDraft(text: c.input),
                context: TextContext(settings: settings, project: context))
            assertGolden(result.text, c.expected, name: c.name)
        }
    }

    func testCodeAwareIsIdempotent() async throws {
        let fixture: Fixture = try Golden.load("codeaware/cases.json")
        for c in fixture.cases {
            let context = project(paths: fixture.paths, coding: c.coding ?? true)
            let stage = CodeAwareStage(project: context)
            let settings = Golden.stageSettings(nil)
            let once = await stage.apply(
                TranscriptDraft(text: c.input),
                context: TextContext(settings: settings, project: context))
            let twice = await stage.apply(
                TranscriptDraft(text: once.text),
                context: TextContext(settings: settings, project: context))
            XCTAssertEqual(twice.text, once.text, "not idempotent: \(c.name)")
        }
    }

    func testProtectedLiteralIsNeverRewritten() async {
        let context = project(paths: ["src/main.ts"])
        let stage = CodeAwareStage(project: context)
        let draft = TranscriptDraft(text: "hero dot t s x", protected: Protected(literals: ["hero dot t s x"]))
        let result = await stage.apply(draft, context: TextContext(settings: Golden.stageSettings(nil),
                                                                   project: context))
        XCTAssertEqual(result.text, "hero dot t s x")
    }
}
