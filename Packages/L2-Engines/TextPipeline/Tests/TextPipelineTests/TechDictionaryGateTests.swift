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

    func testEverydayNextYearNeverBecomesTech() {
        let gate = TechDictionaryGate(userEntries: [], project: nil)
        for line in ["see you next year", "let's meet next year's party", "see you next years friend"] {
            let trigger = line.contains("next year's") ? "next year's" : (line.contains("next years") ? "next years" : "next year")
            XCTAssertFalse(gate.accepts(trigger: trigger, canonical: "Next.js",
                                        line: line, context: TextContext()), line)
        }
        // Same words with genuine dev context do fire.
        XCTAssertTrue(gate.accepts(trigger: "next year", canonical: "Next.js",
                                   line: "deploy the next year app to vercel", context: TextContext()))
        XCTAssertTrue(gate.accepts(trigger: "next js", canonical: "Next.js",
                                   line: "deploy the next js app", context: TextContext()))
    }

    func testDisabledPersonalTermDoesNotPinTierB() {
        let entry = LexiconEntry(id: "disabled", kind: .term, triggers: ["textract"],
                                 canonical: "tech stack", enabled: false, source: .user)
        let gate = TechDictionaryGate(userEntries: [entry], project: nil)
        XCTAssertFalse(gate.accepts(trigger: "textract", canonical: "tech stack",
                                    line: "textract", context: TextContext()))
    }
}
