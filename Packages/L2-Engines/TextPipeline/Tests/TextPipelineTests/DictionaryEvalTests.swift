import XCTest
import SuperflowKernel
import SuperflowTextLexicon
import SuperflowTechDictionary
@testable import SuperflowTextPipeline

final class DictionaryEvalTests: XCTestCase {
    private func stage() -> LexiconStage {
        let gate = TechDictionaryGate(userEntries: [], project: nil)
        return LexiconStage(entries: TechDictionary.lexiconEntries(),
                            id: "techDictionary",
                            includeCanonical: false,
                            filter: { trigger, canonical, line, context in
                                gate.accepts(trigger: trigger, canonical: canonical,
                                             line: line, context: context)
                            })
    }

    private func lines(_ name: String) throws -> [String] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "txt",
                                                  subdirectory: "Resources"))
        return try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    func testEverydaySentencesAreUntouched() async throws {
        let stage = stage()
        var failures: [String] = []
        let inputs = try lines("negatives")
        XCTAssertGreaterThanOrEqual(inputs.count, 300)
        for line in inputs {
            let output = await stage.apply(TranscriptDraft(text: line),
                                           context: TextContext(activeAppBundleID: "com.apple.iWork.Pages")).text
            if output != line { failures.append("\(line)  ->  \(output)") }
        }
        XCTAssertTrue(failures.isEmpty,
                      "false positives:\n" + failures.prefix(400).joined(separator: "\n"))
    }

    func testDeveloperSentencesReplaceAsExpected() async throws {
        let stage = stage()
        var failures: [String] = []
        let inputs = try lines("positives")
        XCTAssertGreaterThanOrEqual(inputs.count, 300)
        for row in inputs {
            let parts = row.components(separatedBy: "\t")
            guard parts.count == 2 else { XCTFail("malformed positive fixture"); continue }
            let output = await stage.apply(TranscriptDraft(text: parts[0]),
                                           context: TextContext()).text
            if output != parts[1] {
                failures.append("\(parts[0])  ->  \(output)  (expected \(parts[1]))")
            }
        }
        XCTAssertTrue(failures.isEmpty,
                      "missed replacements:\n" + failures.prefix(400).joined(separator: "\n"))
    }

    func testEngineeringDictationRepairsContextualAliases() async {
        let stage = stage()
        let cases = [
            ("Deploy to Virshell for the backend.", "Deploy to Vercel for the backend."),
            ("Use readys for caching.", "Use Redis for caching."),
            ("The Adempotensi key prevents duplicate requests.",
             "The idempotency key prevents duplicate requests."),
            ("Use the resord schema for validation.", "Use the Zod schema for validation."),
            ("HTTP 429 triggered the main rail limit too early.",
             "HTTP 429 triggered the rate limit too early."),
            ("The issue is congruency, memory location, or model initialization.",
             "The issue is concurrency, memory allocation, or model initialization."),
            ("Rust Ffi connects the two services.", "Rust FFI connects the two services."),
        ]

        for (input, expected) in cases {
            let output = await stage.apply(TranscriptDraft(text: input),
                                           context: TextContext()).text
            XCTAssertEqual(output, expected, "input: \(input)")
        }
    }

    func testEngineeringDictionaryPreservesAmbiguousWordsAndNumbers() async {
        let stage = stage()
        let cases = [
            "Ready for caching?",
            "The congruency of the triangles is correct.",
            "The memory location is read only.",
            "HTTP 404 oh one is the reported value.",
            "Target 200 ms on an M1 with 8 GB.",
            "Rust FFI targets a localos process.",
        ]

        for input in cases {
            let output = await stage.apply(TranscriptDraft(text: input),
                                           context: TextContext()).text
            XCTAssertEqual(output, input, "input: \(input)")
        }
    }
}
