import SuperflowKernel
import SuperflowPorts
import SuperflowTextDisfluency
import XCTest

final class DisfluencyGoldenTests: XCTestCase {
    private func fixture() throws -> CaseFixture {
        try Golden.load("disfluency/cases.json")
    }

    func testRealStyleDictationCorpus() async throws {
        let fixture = try fixture()
        let stage = DisfluencyStage()
        for c in fixture.cases {
            let context = TextContext(settings: Golden.stageSettings(c.settings))
            let result = await stage.apply(TranscriptDraft(text: c.input), context: context)
            assertGolden(result.text, c.expected, name: c.name)
        }
    }

    func testDisfluencyIsIdempotent() async throws {
        let fixture = try fixture()
        let stage = DisfluencyStage()
        for c in fixture.cases {
            let context = TextContext(settings: Golden.stageSettings(c.settings))
            let once = await stage.apply(TranscriptDraft(text: c.input), context: context)
            let twice = await stage.apply(TranscriptDraft(text: once.text), context: context)
            XCTAssertEqual(twice.text, once.text, "not idempotent: \(c.name)")
        }
    }
}
