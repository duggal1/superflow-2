import XCTest
import SuperflowKernel
import SuperflowTextLexicon
@testable import SuperflowTextPipeline

final class TechDictionaryGateTests: XCTestCase {
    func testTextractRequiresDeveloperContext() {
        let gate = TechDictionaryGate(userEntries: [], project: nil)
        XCTAssertFalse(gate.accepts(trigger: "textract", canonical: "tech stack",
                                    line: "Tell me about textract", context: TextContext()))
        XCTAssertTrue(gate.accepts(trigger: "textract", canonical: "tech stack",
                                   line: "build the textract", context: TextContext()))
        XCTAssertTrue(gate.accepts(trigger: "textract", canonical: "tech stack",
                                   line: "textract", context: TextContext(activeAppBundleID: "com.microsoft.VSCode")))
    }

    func testAWSExclusionOverridesDeveloperApp() {
        let gate = TechDictionaryGate(userEntries: [], project: nil)
        XCTAssertFalse(gate.accepts(trigger: "textract", canonical: "tech stack",
                                    line: "Use textract to parse the PDF", context: TextContext(activeAppBundleID: "com.microsoft.VSCode")))
    }

    func testDisabledPersonalTermDoesNotPinTierB() {
        let entry = LexiconEntry(id: "disabled", kind: .term, triggers: ["textract"],
                                 canonical: "tech stack", enabled: false, source: .user)
        let gate = TechDictionaryGate(userEntries: [entry], project: nil)
        XCTAssertFalse(gate.accepts(trigger: "textract", canonical: "tech stack",
                                    line: "textract", context: TextContext()))
    }
}
