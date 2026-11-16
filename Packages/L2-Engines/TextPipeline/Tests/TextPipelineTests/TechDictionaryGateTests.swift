import XCTest
import SuperflowKernel
import SuperflowTechDictionary
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
        // Even with dev co-words, the ordinary phrase stays ordinary.
        XCTAssertFalse(gate.accepts(trigger: "next year", canonical: "Next.js",
                                    line: "deploy the next year app to vercel", context: TextContext()))
        XCTAssertTrue(gate.accepts(trigger: "next js", canonical: "Next.js",
                                   line: "deploy the next js app", context: TextContext()))
    }

    func testEverydayPhrasesStayOrdinaryInDeveloperApp() {
        let gate = TechDictionaryGate(userEntries: [], project: nil)
        let developer = TextContext(activeAppBundleID: "com.microsoft.VSCode")
        XCTAssertFalse(gate.accepts(trigger: "next year's", canonical: "Next.js",
                                    line: "next year's plan", context: developer))
        XCTAssertFalse(gate.accepts(trigger: "next years", canonical: "Next.js",
                                    line: "next years plan", context: developer))
    }

    func testBundledCatalogHasNoOrdinaryLanguageTriggers() {
        for trigger in ["open eye", "next year", "next year's", "next years",
                        "nexts year", "nexts years", "next year js"] {
            XCTAssertNil(TechDictionary.rule(trigger: trigger, canonical: trigger == "open eye" ? "OpenAI" : "Next.js"),
                         "ordinary phrase '\(trigger)' must not be a bundled technical trigger")
        }
    }

    func testDisabledPersonalTermDoesNotPinTierB() {
        let entry = LexiconEntry(id: "disabled", kind: .term, triggers: ["textract"],
                                 canonical: "tech stack", enabled: false, source: .user)
        let gate = TechDictionaryGate(userEntries: [entry], project: nil)
        XCTAssertFalse(gate.accepts(trigger: "textract", canonical: "tech stack",
                                    line: "textract", context: TextContext()))
    }
}
