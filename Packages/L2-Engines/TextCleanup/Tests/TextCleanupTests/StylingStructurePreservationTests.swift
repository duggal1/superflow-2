import XCTest
import SuperflowKernel
@testable import SuperflowTextCleanup

final class StylingStructurePreservationTests: XCTestCase {
    func testProseStructureKeepsEnumerationsInline() async {
        var settings = AppSettings.default
        settings.cleanupStructure = "prose"
        let context = TextContext(settings: settings)
        let draft = TranscriptDraft(text: "So for the trip, we need to pack sunscreen and then a first aid kit and chargers for everything.")
        let result = await FormattingStage().apply(draft, context: context)
        XCTAssertFalse(result.text.contains("\n- "))
        XCTAssertFalse(result.text.contains("\n1. "))
    }

    func testListsStructureAllowsModelBulletsThrough() async {
        var settings = AppSettings.default
        settings.cleanupStructure = "lists"
        let context = TextContext(settings: settings)
        let modelOutput = "So for the trip, we need to pack:\n- Sunscreen\n- A first aid kit\n- Chargers for everything"
        let draft = TranscriptDraft(text: modelOutput)
        let result = await FormattingStage().apply(draft, context: context)
        XCTAssertTrue(result.text.contains("- Sunscreen"), result.text)
        XCTAssertTrue(result.text.contains("- A first aid kit"), result.text)
    }
}
